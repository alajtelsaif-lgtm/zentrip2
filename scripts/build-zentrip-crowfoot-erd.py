#!/usr/bin/env python3
"""Build a crow's-foot ERD from the saved live Supabase schema reference."""

from __future__ import annotations

import html
import math
import re
import zipfile
from collections import defaultdict
from pathlib import Path
from xml.etree import ElementTree as ET


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "generated-artifacts" / "ZenTrip-Supabase-Database-Diagram.docx"
OUT = ROOT / "generated-artifacts"
SVG_PATH = OUT / "zentrip-supabase-erd-crowfoot.svg"
DRAWIO_PATH = OUT / "zentrip-supabase-erd-crowfoot.drawio"

W_NS = "http://schemas.openxmlformats.org/wordprocessingml/2006/main"
W = {"w": W_NS}
SVG_NS = "http://www.w3.org/2000/svg"
ET.register_namespace("", SVG_NS)

BOX_W = 420
HEADER_H = 42
ROW_H = 25
BOX_PAD_BOTTOM = 12
COL_X = [70, 600, 1130, 1660]
ROW_GAP = 145
GRID = 20

# The order keeps related entities near their referenced tables.
GRID_TABLES = [
    ["partners", "users", "auth.users", "offers"],
    ["partner_listings", "user_profiles", "tourist_monuments", "attraction_visit_counts"],
    ["trips", "travel_preferences", "offer_catalog_metadata", "attraction_visit_dedup"],
    ["bookings", "ai_chat_messages", "airports", "transfers"],
    ["flight_seat_holds", "user_reviews", "api_tokens", "transfer_schedules"],
    ["password_reset_codes", None, None, None],
]


def cell_text(cell: ET.Element) -> str:
    return "".join((node.text or "") for node in cell.findall(".//w:t", W)).strip()


def read_schema() -> tuple[dict[str, list[dict[str, str]]], list[dict[str, str]], str]:
    with zipfile.ZipFile(SOURCE) as docx:
        document = ET.fromstring(docx.read("word/document.xml"))
    body = document.find(".//w:body", W)
    if body is None:
        raise RuntimeError("Could not read the schema reference document.")

    direct_tables = body.findall("./w:tbl", W)
    if len(direct_tables) < 2:
        raise RuntimeError("The schema reference is missing its snapshot metadata or FK register.")

    meta = {}
    for row in direct_tables[0].findall("./w:tr", W)[1:]:
        values = [cell_text(cell) for cell in row.findall("./w:tc", W)]
        if len(values) >= 2:
            meta[values[0]] = values[1]
    snapshot = meta.get("Snapshot date", "Unknown date")

    fk_rows = []
    for row in direct_tables[1].findall("./w:tr", W)[1:]:
        values = [cell_text(cell) for cell in row.findall("./w:tc", W)]
        if len(values) >= 5:
            fk_rows.append({
                "parent": values[0],
                "parent_key": values[1],
                "child": values[2],
                "child_key": values[3],
                "delete_rule": values[4],
            })

    schema: dict[str, list[dict[str, str]]] = {}
    in_dictionary = False
    pending_title = ""
    for child in list(body):
        tag = child.tag.rsplit("}", 1)[-1]
        if tag == "p":
            text = "".join((node.text or "") for node in child.findall(".//w:t", W)).strip()
            if text == "Live Supabase data dictionary":
                in_dictionary = True
                pending_title = ""
            elif in_dictionary and text:
                pending_title = text
        elif tag == "tbl" and in_dictionary:
            rows = child.findall("./w:tr", W)
            if not rows:
                continue
            header = [cell_text(cell) for cell in rows[0].findall("./w:tc", W)]
            if header[:3] != ["Column", "PostgreSQL type", "Key / relation"]:
                continue
            if not pending_title:
                raise RuntimeError("A live schema dictionary table has no entity name.")
            parsed_rows = []
            for row in rows[1:]:
                values = [cell_text(cell) for cell in row.findall("./w:tc", W)]
                if len(values) >= 4:
                    parsed_rows.append({
                        "name": values[0],
                        "type": values[1],
                        "key": values[2],
                        "nullable": values[3],
                    })
            schema[pending_title] = parsed_rows
            pending_title = ""

    if not schema:
        raise RuntimeError("No live public-schema tables were found in the reference document.")
    for fk in fk_rows:
        child_fields = schema.get(fk["child"], [])
        fk_columns = {name.strip() for name in fk["child_key"].split(",")}
        fk["nullable"] = any(
            field["name"] in fk_columns and field["nullable"] == "Yes"
            for field in child_fields
        )
        pk_columns = {
            field["name"] for field in child_fields
            if re.search(r"\bPK\b", field["key"])
        }
        unique_sets = []
        if pk_columns:
            unique_sets.append(pk_columns)
        for field in child_fields:
            match = re.search(r"\bUQ(?:\s*\(([^)]*)\))?", field["key"])
            if not match:
                continue
            columns = match.group(1)
            unique_sets.append(
                {column.strip() for column in columns.split(",")} if columns
                else {field["name"]}
            )
        fk["one_to_one"] = any(fk_columns == unique_columns for unique_columns in unique_sets)
    return schema, fk_rows, snapshot


def expected_code_tables() -> set[str]:
    """Read project-owned table definitions, excluding external dependencies."""
    sources = [ROOT / "backend" / "src" / "main" / "resources" / "schema.sql"]
    sources.extend((ROOT / "backend" / "src" / "main" / "resources" / "migrations").glob("*.sql"))
    table_pattern = re.compile(
        r"CREATE\s+TABLE\s+IF\s+NOT\s+EXISTS\s+(?:public\.)?([a-z_][a-z0-9_]*)",
        re.IGNORECASE,
    )
    names = set()
    for source in sources:
        if source.exists():
            names.update(table_pattern.findall(source.read_text(encoding="utf-8")))
    return names


def get_key_flags(key_text: str) -> list[str]:
    flags = []
    if re.search(r"\bPK\b", key_text):
        flags.append("PK")
    if re.search(r"\bFK\b", key_text):
        flags.append("FK")
    if "UQ" in key_text:
        flags.append("UQ")
    return flags


def place_tables(schema: dict[str, list[dict[str, str]]]) -> tuple[dict[str, dict[str, int]], int, int]:
    max_by_row = []
    for row in GRID_TABLES:
        heights = [
            HEADER_H + len(schema[name]) * ROW_H + BOX_PAD_BOTTOM
            for name in row if name is not None
        ]
        max_by_row.append(max(heights, default=100))

    y_positions = []
    cursor = 185
    for row_height in max_by_row:
        y_positions.append(cursor)
        cursor += row_height + ROW_GAP

    positions = {}
    for r, row in enumerate(GRID_TABLES):
        for c, name in enumerate(row):
            if name:
                positions[name] = {
                    "x": COL_X[c],
                    "y": y_positions[r],
                    "w": BOX_W,
                    "h": HEADER_H + len(schema[name]) * ROW_H + BOX_PAD_BOTTOM,
                }
    return positions, COL_X[-1] + BOX_W + 70, cursor + 230


def inside_box(point: tuple[int, int], rect: dict[str, int], pad: int = 16) -> bool:
    x, y = point
    return (rect["x"] - pad <= x <= rect["x"] + rect["w"] + pad
            and rect["y"] - pad <= y <= rect["y"] + rect["h"] + pad)


def astar(start: tuple[int, int], goal: tuple[int, int], boxes: dict[str, dict[str, int]],
          parent: str, child: str, canvas_w: int, canvas_h: int) -> list[tuple[int, int]]:
    """Find a short orthogonal path which avoids entity boxes."""
    import heapq

    def blocked(p: tuple[int, int]) -> bool:
        if not (GRID <= p[0] <= canvas_w - GRID and GRID <= p[1] <= canvas_h - GRID):
            return True
        return any(inside_box(p, rect, 22) for rect in boxes.values())

    start_grid = (round(start[0] / GRID) * GRID, round(start[1] / GRID) * GRID)
    goal_grid = (round(goal[0] / GRID) * GRID, round(goal[1] / GRID) * GRID)
    neighbors = [(GRID, 0), (-GRID, 0), (0, GRID), (0, -GRID)]
    queue = [(0, start_grid)]
    came_from: dict[tuple[int, int], tuple[int, int] | None] = {start_grid: None}
    cost = {start_grid: 0}
    while queue:
        _, current = heapq.heappop(queue)
        if current == goal_grid:
            path = [current]
            while came_from[path[-1]] is not None:
                path.append(came_from[path[-1]])  # type: ignore[arg-type]
            return list(reversed(path))
        for dx, dy in neighbors:
            nxt = (current[0] + dx, current[1] + dy)
            if blocked(nxt):
                continue
            new_cost = cost[current] + GRID
            if nxt not in cost or new_cost < cost[nxt]:
                cost[nxt] = new_cost
                heuristic = abs(nxt[0] - goal_grid[0]) + abs(nxt[1] - goal_grid[1])
                heapq.heappush(queue, (new_cost + heuristic, nxt))
                came_from[nxt] = current
    return [start, goal]


def simplify_path(points: list[tuple[int, int]]) -> list[tuple[int, int]]:
    if len(points) < 3:
        return points
    result = [points[0]]
    for i in range(1, len(points) - 1):
        a, b, c = result[-1], points[i], points[i + 1]
        if (b[0] - a[0]) * (c[1] - b[1]) != (b[1] - a[1]) * (c[0] - b[0]):
            result.append(b)
    result.append(points[-1])
    return result


def ports(parent: str, child: str, boxes: dict[str, dict[str, int]]) -> tuple[tuple[int, int], tuple[int, int]]:
    a, b = boxes[parent], boxes[child]
    ac = (a["x"] + a["w"] // 2, a["y"] + a["h"] // 2)
    bc = (b["x"] + b["w"] // 2, b["y"] + b["h"] // 2)
    if abs(bc[0] - ac[0]) >= abs(bc[1] - ac[1]):
        if bc[0] >= ac[0]:
            return (a["x"] + a["w"], ac[1]), (b["x"], bc[1])
        return (a["x"], ac[1]), (b["x"] + b["w"], bc[1])
    if bc[1] >= ac[1]:
        return (ac[0], a["y"] + a["h"]), (bc[0], b["y"])
    return (ac[0], a["y"]), (bc[0], b["y"] + b["h"])


def connector_markup(fk: dict[str, str], boxes: dict[str, dict[str, int]],
                     canvas_w: int, canvas_h: int) -> str:
    parent, child = fk["parent"], fk["child"]
    if parent not in boxes or child not in boxes:
        return ""
    start, end = ports(parent, child, boxes)
    p_rect, c_rect = boxes[parent], boxes[child]

    def outward(point: tuple[int, int], rect: dict[str, int]) -> tuple[int, int]:
        center = (rect["x"] + rect["w"] // 2, rect["y"] + rect["h"] // 2)
        dx, dy = point[0] - center[0], point[1] - center[1]
        length = max(1, math.hypot(dx, dy))
        return (round(point[0] + dx / length * 32), round(point[1] + dy / length * 32))

    start_out, end_out = outward(start, p_rect), outward(end, c_rect)
    middle = astar(start_out, end_out, boxes, parent, child, canvas_w, canvas_h)
    points = simplify_path([start, start_out, *middle, end_out, end])
    path = " ".join(f"{x},{y}" for x, y in points)
    start_x, start_y = points[0]
    end_x, end_y = points[-1]
    # Crow's-foot at the child side; single bar at the referenced/parent side.
    before = points[1] if len(points) > 1 else (start_x, start_y)
    after = points[-2] if len(points) > 1 else (end_x, end_y)
    def fork(x: int, y: int, neighbor: tuple[int, int]) -> str:
        dx, dy = x - neighbor[0], y - neighbor[1]
        length = max(1, math.hypot(dx, dy))
        ux, uy = dx / length, dy / length
        px, py = -uy, ux
        depth, spread = 14, 9
        sx, sy = x - ux * depth, y - uy * depth
        return (f'<path d="M {x} {y} L {sx + px * spread} {sy + py * spread} '
                f'M {x} {y} L {sx} {sy} M {x} {y} L {sx - px * spread} {sy - py * spread}" '
                'fill="none" stroke="#455b91" stroke-width="3" stroke-linecap="round"/>')
    def one_marker(x: int, y: int, neighbor: tuple[int, int]) -> str:
        dx, dy = x - neighbor[0], y - neighbor[1]
        length = max(1, math.hypot(dx, dy))
        px, py = -dy / length, dx / length
        return (f'<path d="M {x + px * 10} {y + py * 10} '
                f'L {x - px * 10} {y - py * 10}" stroke="#455b91" stroke-width="3"/>')
    def optional_circle(x: int, y: int, neighbor: tuple[int, int]) -> str:
        dx, dy = neighbor[0] - x, neighbor[1] - y
        length = max(1, math.hypot(dx, dy))
        cx, cy = x + dx / length * 14, y + dy / length * 14
        return f'<circle cx="{cx:.1f}" cy="{cy:.1f}" r="4.5" fill="#fff" stroke="#455b91" stroke-width="2"/>'
    # Parent-side 1 marker (short cross bar).
    one = one_marker(start_x, start_y, before)
    if fk.get("nullable"):
        one += optional_circle(start_x, start_y, before)
    child_marker = one_marker(end_x, end_y, after) if fk.get("one_to_one") else fork(end_x, end_y, after)
    child_marker += optional_circle(end_x, end_y, after)
    cardinality_label = ""
    if fk.get("one_to_one"):
        label_x, label_y = points[len(points) // 2]
        cardinality_label = (
            f'<rect x="{label_x-20}" y="{label_y-13}" width="40" height="20" fill="#ffffff" stroke="#d3d9e4"/>'
            f'<text x="{label_x}" y="{label_y+2}" text-anchor="middle" font-family="Arial,sans-serif" '
            'font-size="12" fill="#455b91">1:1</text>'
        )
    return (f'<polyline points="{path}" fill="none" stroke="#455b91" stroke-width="2.2" '
            'stroke-linecap="round" stroke-linejoin="round"/>'
            + one + child_marker + cardinality_label)


def svg_document(schema: dict[str, list[dict[str, str]]], fks: list[dict[str, str]],
                 positions: dict[str, dict[str, int]], width: int, height: int,
                 snapshot: str, missing_in_live: list[str], missing_ledger: bool) -> str:
    app_tables = [name for name in schema if not name.startswith("auth.")]
    total_columns = sum(len(cols) for name, cols in schema.items() if not name.startswith("auth."))
    footer_y = height - 180
    parts = [
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="0 0 {width} {height}">',
        '<rect width="100%" height="100%" fill="#eaf0fc"/>',
        f'<text x="{width/2}" y="72" text-anchor="middle" font-family="Arial,sans-serif" font-size="42" fill="#343a46">Zentrip — Supabase ER Diagram</text>',
        f'<text x="{width/2}" y="112" text-anchor="middle" font-family="Arial,sans-serif" font-size="18" fill="#596579">Crow’s-foot ERD • {len(app_tables)} live Zentrip tables • {total_columns} columns • {len(fks)} foreign keys • snapshot: {html.escape(snapshot)}</text>',
        '<rect x="70" y="132" width="510" height="38" fill="#ffffff" stroke="#263746" stroke-width="1.5"/>',
        '<text x="92" y="157" font-family="Arial,sans-serif" font-size="15" fill="#243247">PK = primary key    FK = foreign key    UQ = unique</text>',
        '<line x1="620" y1="151" x2="760" y2="151" stroke="#455b91" stroke-width="2.2"/>',
        '<line x1="620" y1="141" x2="620" y2="161" stroke="#455b91" stroke-width="3"/>',
        '<path d="M760 151 L744 141 M760 151 L744 151 M760 151 L744 161" fill="none" stroke="#455b91" stroke-width="3"/>',
        '<text x="780" y="157" font-family="Arial,sans-serif" font-size="15" fill="#243247">bar = one, circle = optional, crowfoot = many</text>',
        '<rect x="1220" y="137" width="42" height="28" fill="#f8fafc" stroke="#65748b" stroke-width="2" stroke-dasharray="7 5"/>',
        '<text x="1275" y="157" font-family="Arial,sans-serif" font-size="15" fill="#243247">External Supabase Auth table</text>',
    ]
    parts.append('<g id="relationships">')
    for fk in fks:
        parts.append(connector_markup(fk, positions, width, height))
    parts.append('</g>')

    parts.append('<g id="entities">')
    for table, fields in schema.items():
        rect = positions[table]
        x, y, w, h = rect["x"], rect["y"], rect["w"], rect["h"]
        is_external = table.startswith("auth.")
        fill = "#f8fafc" if is_external else "#fff"
        dash = ' stroke-dasharray="8 5"' if is_external else ""
        title = f"{table} (Supabase Auth)" if is_external else table
        parts.append(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" fill="{fill}" stroke="#263746" stroke-width="2"{dash}/>')
        parts.append(f'<rect x="{x}" y="{y}" width="{w}" height="{HEADER_H}" fill="{fill}" stroke="#263746" stroke-width="2"{dash}/>')
        parts.append(f'<text x="{x+w/2}" y="{y+28}" text-anchor="middle" font-family="Arial,sans-serif" font-size="19" font-weight="700" fill="#303643">{html.escape(title)}</text>')
        for i, field in enumerate(fields):
            row_y = y + HEADER_H + (i + 1) * ROW_H
            label_y = y + HEADER_H + i * ROW_H + 18
            if i:
                parts.append(f'<line x1="{x+1}" y1="{row_y}" x2="{x+w-1}" y2="{row_y}" stroke="#e8ebf0" stroke-width="1"/>')
            flags = get_key_flags(field["key"])
            flags_text = ", ".join(flags)
            parts.append(f'<text x="{x+14}" y="{label_y}" font-family="Arial,sans-serif" font-size="15" fill="#222b37">{html.escape(field["name"])}</text>')
            if flags_text:
                parts.append(f'<text x="{x+w-14}" y="{label_y}" text-anchor="end" font-family="Arial,sans-serif" font-size="13" font-weight="700" fill="#364f89">{html.escape(flags_text)}</text>')
    if missing_in_live or missing_ledger:
        parts.extend([
            f'<rect x="70" y="{footer_y}" width="{width-140}" height="145" rx="4" fill="#fff8e8" stroke="#b7791f" stroke-width="2"/>',
            f'<text x="92" y="{footer_y+30}" font-family="Arial,sans-serif" font-size="19" font-weight="700" fill="#7b4c11">Project tables not present in this live Supabase snapshot</text>',
        ])
        missing_text = ", ".join(missing_in_live) if missing_in_live else "None"
        parts.append(
            f'<text x="92" y="{footer_y+62}" font-family="Arial,sans-serif" font-size="15" fill="#513f28">'
            f'<tspan x="92" dy="0">{html.escape(missing_text)}</tspan></text>'
        )
        if missing_ledger:
            parts.append(
                f'<text x="92" y="{footer_y+88}" font-family="Arial,sans-serif" font-size="14" fill="#513f28">'
                'The project also defines a schema_migrations tracking table; it is infrastructure, not app data.</text>'
            )
        if "flyway_schema_history" in expected_code_tables():
            pass
        parts.append(
            f'<text x="92" y="{footer_y+119}" font-family="Arial,sans-serif" font-size="13" fill="#705c40">'
            'flyway_schema_history is omitted above because it records migration status, not Zentrip application data.</text>'
        )
    parts.append('</g></svg>')
    return "\n".join(part for part in parts if part)


def drawio_document(schema: dict[str, list[dict[str, str]]], fks: list[dict[str, str]],
                    positions: dict[str, dict[str, int]], width: int, height: int,
                    missing_in_live: list[str], missing_ledger: bool) -> str:
    cells = ['<mxCell id="0"/>', '<mxCell id="1" parent="0"/>']
    table_ids = {name: f"t{i+1}" for i, name in enumerate(schema)}
    for name, fields in schema.items():
        p = positions[name]
        rows = []
        for field in fields:
            flags = ", ".join(get_key_flags(field["key"]))
            flag_html = f'<span style="color:#364f89;font-weight:bold;float:right">{html.escape(flags)}</span>' if flags else ""
            rows.append(f'<tr><td style="padding:3px 8px">{html.escape(field["name"])}{flag_html}</td></tr>')
        external_note = '<tr><td style="padding:3px 8px;color:#65748b"><i>External Supabase Auth table</i></td></tr>' if name.startswith("auth.") else ""
        label = (
            '<table style="width:100%;border-collapse:collapse;font-family:Arial,sans-serif;font-size:13px">'
            f'<tr><th style="background:#ffffff;border:1px solid #263746;padding:8px;font-size:16px">{html.escape(name)}</th></tr>'
            + external_note + "".join(rows) + "</table>"
        )
        value = html.escape(label, quote=True)
        external_style = "dashed=1;dashPattern=8 5;" if name.startswith("auth.") else ""
        fill = "#F8FAFC" if name.startswith("auth.") else "#FFFFFF"
        style = f"rounded=0;whiteSpace=wrap;html=1;align=left;verticalAlign=top;strokeColor=#263746;fillColor={fill};{external_style}fontColor=#222B37;fontSize=13;spacing=0;"
        cells.append(
            f'<mxCell id="{table_ids[name]}" value="{value}" style="{style}" vertex="1" parent="1">'
            f'<mxGeometry x="{p["x"]}" y="{p["y"]}" width="{p["w"]}" height="{p["h"]}" as="geometry"/></mxCell>'
        )
    for i, fk in enumerate(fks):
        if fk["parent"] not in table_ids or fk["child"] not in table_ids:
            continue
        start_arrow = "ERzeroToOne" if fk.get("nullable") else "ERone"
        end_arrow = "ERzeroToOne" if fk.get("one_to_one") else "ERzeroToMany"
        style = f"edgeStyle=orthogonalEdgeStyle;rounded=0;orthogonalLoop=1;jettySize=auto;html=1;strokeColor=#455B91;strokeWidth=2;startArrow={start_arrow};startFill=0;endArrow={end_arrow};endFill=0;"
        value = html.escape(("1:1 · " if fk.get("one_to_one") else "") + f'{fk["child_key"]} → {fk["parent"]}.{fk["parent_key"]}', quote=True)
        cells.append(
            f'<mxCell id="e{i+1}" value="{value}" style="{style}" edge="1" parent="1" '
            f'source="{table_ids[fk["parent"]]}" target="{table_ids[fk["child"]]}">'
            '<mxGeometry relative="1" as="geometry"/></mxCell>'
        )
    if missing_in_live:
        note_lines = ", ".join(missing_in_live)
        ledger_text = "The project also defines a schema_migrations tracking table; it is infrastructure, not app data." if missing_ledger else ""
        note = (
            '<b>Project tables not present in this live Supabase snapshot</b><br/>'
            + html.escape(note_lines)
            + ("<br/>" + html.escape(ledger_text) if ledger_text else "")
            + '<br/>flyway_schema_history is omitted because it records migration status, not Zentrip application data.'
        )
        cells.append(
            f'<mxCell id="schema-status" value="{html.escape(note, quote=True)}" '
            'style="shape=note;whiteSpace=wrap;html=1;size=18;strokeColor=#B7791F;fillColor=#FFF8E8;fontColor=#513F28;fontSize=15;" '
            'vertex="1" parent="1"><mxGeometry x="70" y="'
            f'{height-180}" width="{width-140}" height="145" as="geometry"/></mxCell>'
        )
    return (
        '<mxfile host="app.diagrams.net" version="24.7.17"><diagram id="zentrip-erd" name="Zentrip Supabase ERD">'
        f'<mxGraphModel dx="{width}" dy="{height}" grid="1" gridSize="10" guides="1" tooltips="1" connect="1" '
        f'arrows="1" fold="1" page="1" pageScale="1" pageWidth="{width}" pageHeight="{height}" math="0" shadow="0">'
        '<root>' + "".join(cells) + '</root></mxGraphModel></diagram></mxfile>'
    )


def main() -> None:
    live_schema, fks, snapshot = read_schema()
    system_only = {"flyway_schema_history", "schema_migrations"}
    schema = {name: columns for name, columns in live_schema.items() if name not in system_only}
    for fk in fks:
        parent = fk["parent"]
        if parent not in schema and "." in parent:
            schema.setdefault(parent, [{
                "name": fk["parent_key"],
                "type": "uuid",
                "key": "PK",
                "nullable": "No",
            }])
    missing_layout = sorted(set(schema) - {name for row in GRID_TABLES for name in row if name})
    missing = sorted({name for row in GRID_TABLES for name in row if name} - set(schema))
    if missing_layout or missing:
        raise RuntimeError(f"ERD layout mismatch. Unplaced live tables: {missing_layout}; absent layout tables: {missing}")
    if any(fk["parent"] not in schema or fk["child"] not in schema for fk in fks):
        raise RuntimeError("A live foreign key references an entity missing from the ERD.")
    code_tables = expected_code_tables()
    missing_in_live = sorted((code_tables - set(live_schema)) - system_only)
    missing_ledger = "schema_migrations" in code_tables and "schema_migrations" not in live_schema
    positions, width, height = place_tables(schema)
    OUT.mkdir(exist_ok=True)
    SVG_PATH.write_text(
        svg_document(schema, fks, positions, width, height, snapshot, missing_in_live, missing_ledger),
        encoding="utf-8",
    )
    DRAWIO_PATH.write_text(
        drawio_document(schema, fks, positions, width, height, missing_in_live, missing_ledger),
        encoding="utf-8",
    )
    print(f"Created {SVG_PATH} and {DRAWIO_PATH}")
    app_table_count = len([name for name in live_schema if name not in system_only])
    app_column_count = sum(len(cols) for name, cols in live_schema.items() if name not in system_only)
    print(
        f"Live Supabase: {len(live_schema)} tables; app ERD: {app_table_count} tables, "
        f"{app_column_count} columns, {len(fks)} FKs; "
        f"code-defined tables missing from live: {len(missing_in_live)}."
    )
    if missing_in_live:
        print("Missing app tables: " + ", ".join(missing_in_live))


if __name__ == "__main__":
    main()
