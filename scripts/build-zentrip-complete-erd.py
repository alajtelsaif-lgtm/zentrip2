#!/usr/bin/env python3
"""Build a multi-page, A4-landscape ERD from the live schema and project DDL."""

from __future__ import annotations

import html
import importlib.util
import math
import re
import zipfile
from collections import defaultdict
from pathlib import Path
from xml.etree import ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "generated-artifacts" / "zentrip-complete-erd"
LIVE_DOCX = ROOT / "generated-artifacts" / "ZenTrip-Supabase-Database-Diagram.docx"
SVG_NS = "http://www.w3.org/2000/svg"
W_NS = "http://schemas.openxmlformats.org/wordprocessingml/2006/main"
W = {"w": W_NS}
PAGE_W, PAGE_H = 1123, 794
ROW_H = 15
HEADER_H = 43
FONT = "Arial, sans-serif"
NAVY, BLUE, LIGHT, ORANGE = "#22344d", "#455b91", "#eaf0fc", "#a76516"

PAGES = [
    {
        "name": "01 Overview",
        "kind": "overview",
        "tables": [],
        "positions": {},
    },
    {
        "name": "02 Identity and accounts",
        "tables": ["users", "auth.users", "user_profiles", "travel_preferences",
                   "api_tokens", "password_reset_codes"],
        "positions": {
            "auth.users": (28, 100, 300), "users": (390, 100, 340),
            "user_profiles": (760, 100, 330), "travel_preferences": (28, 405, 340),
            "api_tokens": (390, 405, 300), "password_reset_codes": (760, 405, 330),
        },
    },
    {
        "name": "03 User activity and messaging",
        "tables": ["ai_chat_messages", "user_reviews", "user_notifications",
                   "user_push_tokens"],
        "positions": {
            "ai_chat_messages": (28, 115, 340), "user_reviews": (392, 115, 340),
            "user_notifications": (756, 115, 340), "user_push_tokens": (392, 430, 340),
        },
    },
    {
        "name": "04 Partners and listings",
        "tables": ["partners", "partner_listings", "legacy_attraction_partner_reviews"],
        "positions": {
            "partners": (28, 105, 500), "partner_listings": (568, 105, 525),
            "legacy_attraction_partner_reviews": (28, 420, 500),
        },
    },
    {
        "name": "05 Flights, trips, and bookings",
        "tables": ["trips", "bookings", "flight_seat_holds", "payment_attempts"],
        "positions": {
            "trips": (25, 95, 350), "bookings": (395, 95, 345),
            "payment_attempts": (760, 95, 335), "flight_seat_holds": (395, 435, 345),
        },
    },
    {
        "name": "06 Transfers",
        "tables": ["transfers", "transfer_schedules"],
        "positions": {"transfers": (90, 115, 440), "transfer_schedules": (590, 180, 440)},
    },
    {
        "name": "07 Travel catalogs and offers",
        "tables": ["offers", "offer_catalog_metadata", "airports", "hotel_destinations"],
        "positions": {
            "offers": (28, 95, 520), "offer_catalog_metadata": (575, 95, 520),
            "airports": (28, 440, 520), "hotel_destinations": (575, 440, 520),
        },
    },
    {
        "name": "08 Attractions and visit tracking",
        "tables": ["tourist_monuments", "attraction_visit_counts", "attraction_visit_dedup"],
        "positions": {
            "tourist_monuments": (28, 105, 510), "attraction_visit_counts": (575, 105, 520),
            "attraction_visit_dedup": (575, 265, 520),
        },
    },
    {
        "name": "09 Landmark catalog",
        "tables": ["landmark_places", "landmark_place_aliases", "landmark_search_areas",
                   "landmark_merge_candidates"],
        "positions": {
            "landmark_places": (28, 100, 520), "landmark_place_aliases": (575, 100, 520),
            "landmark_search_areas": (575, 325, 520), "landmark_merge_candidates": (28, 475, 520),
        },
    },
    {
        "name": "10 Migration metadata",
        "tables": ["flyway_schema_history", "schema_migrations"],
        "positions": {"flyway_schema_history": (55, 130, 500), "schema_migrations": (570, 130, 500)},
    },
]

APP_LINKS = [
    {
        "parent": "users", "parent_key": "email", "child": "password_reset_codes",
        "child_key": "email", "cardinality": "Application lookup",
        "status": "Code path; not an FK",
        "label": "email lookup · app only",
    },
    {
        "parent": "airports", "parent_key": "code", "child": "trips",
        "child_key": "origin_code / destination_code", "cardinality": "Application lookup",
        "status": "Flight flow; not an FK",
        "label": "flight flow stores selected airport codes",
    },
]


def load_live_reader():
    path = ROOT / "scripts" / "build-zentrip-crowfoot-erd.py"
    spec = importlib.util.spec_from_file_location("zentrip_live_schema", path)
    if spec is None or spec.loader is None:
        raise RuntimeError("Cannot load the verified live-schema reader.")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def sql_chunks(source: str) -> list[str]:
    """Split a CREATE TABLE body on commas outside quotes and nested parentheses."""
    out, start, depth, quote, i = [], 0, 0, None, 0
    while i < len(source):
        char = source[i]
        if quote:
            if char == quote:
                if i + 1 < len(source) and source[i + 1] == quote:
                    i += 1
                else:
                    quote = None
        elif char in ("'", '"'):
            quote = char
        elif char == "(":
            depth += 1
        elif char == ")":
            depth -= 1
        elif char == "," and depth == 0:
            out.append(source[start:i].strip())
            start = i + 1
        i += 1
    out.append(source[start:].strip())
    return [chunk for chunk in out if chunk]


def matching_paren(source: str, opening: int) -> int:
    depth, quote, i = 1, None, opening
    while i < len(source):
        char = source[i]
        if quote:
            if char == quote:
                if i + 1 < len(source) and source[i + 1] == quote:
                    i += 1
                else:
                    quote = None
        elif char in ("'", '"'):
            quote = char
        elif char == "(":
            depth += 1
        elif char == ")":
            depth -= 1
            if depth == 0:
                return i
        i += 1
    return -1


def split_columns(value: str) -> list[str]:
    return [part.strip().strip('"') for part in value.split(",") if part.strip()]


def parse_ddl_sources() -> tuple[dict[str, dict], list[dict]]:
    resource = ROOT / "backend" / "src" / "main" / "resources"
    sources = sorted((resource / "migrations").glob("*.sql"))
    sources += [ROOT / "backend" / "scripts" / "migrate_attraction_visits.sql",
                resource / "schema.sql"]
    tables: dict[str, dict] = {}
    fks: list[dict] = []
    create_re = re.compile(
        r"CREATE\s+TABLE\s+IF\s+NOT\s+EXISTS\s+(?:public\.)?([a-z_][a-z0-9_]*)\s*\(",
        re.I,
    )
    for source_path in sources:
        if not source_path.exists():
            continue
        text = re.sub(r"--[^\n]*", "", source_path.read_text(encoding="utf-8"))
        for match in create_re.finditer(text):
            name, start = match.group(1).lower(), match.end()
            end = matching_paren(text, start)
            if end < 0:
                continue
            table = tables.setdefault(name, {"fields": {}, "unique_sets": [], "source": "code"})
            clauses = sql_chunks(text[start:end])
            local_fks = []
            for clause in clauses:
                clean = clause.strip()
                normalized = re.sub(r"^CONSTRAINT\s+[\w\"]+\s+", "", clean, flags=re.I)
                pk_match = re.match(r"PRIMARY\s+KEY\s*\(([^)]*)\)", normalized, re.I)
                uq_match = re.match(r"UNIQUE\s*\(([^)]*)\)", normalized, re.I)
                fk_match = re.match(
                    r"FOREIGN\s+KEY\s*\(([^)]*)\)\s+REFERENCES\s+(?:public\.)?([\w.]+)\s*\(([^)]*)\)",
                    normalized, re.I,
                )
                if pk_match:
                    cols = split_columns(pk_match.group(1))
                    table["unique_sets"].append(set(cols))
                    for col in cols:
                        table["fields"].setdefault(col, {}).update({"pk": True, "nullable": False})
                    continue
                if uq_match:
                    cols = split_columns(uq_match.group(1))
                    table["unique_sets"].append(set(cols))
                    for col in cols:
                        table["fields"].setdefault(col, {}).update({"uq": True})
                    continue
                if fk_match:
                    child_cols, parent, parent_cols = (
                        split_columns(fk_match.group(1)),
                        fk_match.group(2).lower(),
                        split_columns(fk_match.group(3)),
                    )
                    local_fks.append({
                        "parent": parent, "parent_key": ", ".join(parent_cols),
                        "child": name, "child_key": ", ".join(child_cols),
                        "delete_rule": "from project DDL",
                        "status": "CODE-ONLY",
                    })
                    for col in child_cols:
                        table["fields"].setdefault(col, {}).update({"fk": parent + "." + ", ".join(parent_cols)})
                    continue
                if re.match(r"^(?:CHECK|EXCLUDE)\b", normalized, re.I):
                    continue

                column_match = re.match(r'"?([a-z_][a-z0-9_]*)"?\s+(.+)$', clean, re.I | re.S)
                if not column_match:
                    continue
                col, rest = column_match.group(1).lower(), column_match.group(2).strip()
                cut = re.search(
                    r"\s+(?:NOT\s+NULL|NULL\b|DEFAULT\b|PRIMARY\s+KEY|UNIQUE\b|REFERENCES\b|CHECK\b|CONSTRAINT\b|GENERATED\b)",
                    rest, re.I,
                )
                dtype = (rest[:cut.start()] if cut else rest).strip()
                info = table["fields"].setdefault(col, {})
                info.update({
                    "type": re.sub(r"\s+", " ", dtype),
                    "nullable": not bool(re.search(r"\bNOT\s+NULL\b", rest, re.I)),
                })
                if re.search(r"\bPRIMARY\s+KEY\b", rest, re.I):
                    info.update({"pk": True, "nullable": False})
                    table["unique_sets"].append({col})
                if re.search(r"\bUNIQUE\b", rest, re.I):
                    info["uq"] = True
                    table["unique_sets"].append({col})
                ref = re.search(
                    r"\bREFERENCES\s+(?:public\.)?([\w.]+)\s*\(([^)]*)\)", rest, re.I,
                )
                if ref:
                    parent, parent_cols = ref.group(1).lower(), split_columns(ref.group(2))
                    info["fk"] = parent + "." + ", ".join(parent_cols)
                    local_fks.append({
                        "parent": parent, "parent_key": ", ".join(parent_cols),
                        "child": name, "child_key": col,
                        "delete_rule": "from project DDL",
                        "status": "CODE-ONLY",
                    })
            fks.extend(local_fks)

    # Capture incremental columns and constraints not represented by CREATE TABLE.
    for source_path in sorted((resource / "migrations").glob("*.sql")):
        text = re.sub(r"--[^\n]*", "", source_path.read_text(encoding="utf-8"))
        for match in re.finditer(
            r"ALTER\s+TABLE\s+(?:public\.)?([a-z_][a-z0-9_]*)\s+ADD\s+COLUMN(?:\s+IF\s+NOT\s+EXISTS)?\s+([a-z_][a-z0-9_]*)\s+(.+?);",
            text, re.I | re.S,
        ):
            table_name, col, rest = match.group(1).lower(), match.group(2).lower(), match.group(3).strip()
            cut = re.search(r"\s+(?:NOT\s+NULL|NULL\b|DEFAULT\b|REFERENCES\b|CHECK\b)", rest, re.I)
            dtype = (rest[:cut.start()] if cut else rest).strip()
            info = tables.setdefault(table_name, {"fields": {}, "unique_sets": [], "source": "code"})["fields"].setdefault(col, {})
            info.update({"type": re.sub(r"\s+", " ", dtype), "nullable": not bool(re.search(r"\bNOT\s+NULL\b", rest, re.I))})
            ref = re.search(r"\bREFERENCES\s+(?:public\.)?([\w.]+)\s*\(([^)]*)\)", rest, re.I)
            if ref:
                parent, parent_cols = ref.group(1).lower(), split_columns(ref.group(2))
                info["fk"] = parent + "." + ", ".join(parent_cols)
                fks.append({
                    "parent": parent, "parent_key": ", ".join(parent_cols),
                    "child": table_name, "child_key": col,
                    "delete_rule": "from project migration",
                    "status": "CODE-ONLY",
                })
        for match in re.finditer(
            r"ALTER\s+TABLE\s+(?:public\.)?([a-z_][a-z0-9_]*)\s+ADD\s+CONSTRAINT\s+[\w\"]+\s+FOREIGN\s+KEY\s*\(([^)]*)\)\s+REFERENCES\s+(?:public\.)?([\w.]+)\s*\(([^)]*)\)",
            text, re.I,
        ):
            child, child_cols, parent, parent_cols = (
                match.group(1).lower(), split_columns(match.group(2)),
                match.group(3).lower(), split_columns(match.group(4)),
            )
            fks.append({
                "parent": parent, "parent_key": ", ".join(parent_cols),
                "child": child, "child_key": ", ".join(child_cols),
                "delete_rule": "from project migration",
                "status": "CODE-ONLY",
            })
            for col in child_cols:
                tables.setdefault(child, {"fields": {}, "unique_sets": [], "source": "code"})["fields"].setdefault(col, {}).update(
                    {"fk": parent + "." + ", ".join(parent_cols)}
                )
    return tables, dedupe_fks(fks)


def dedupe_fks(fks: list[dict]) -> list[dict]:
    unique, result = set(), []
    for fk in fks:
        signature = (fk["parent"], fk["parent_key"], fk["child"], fk["child_key"])
        if signature not in unique:
            unique.add(signature)
            result.append(fk)
    return result


def key_flags(field: dict) -> list[str]:
    flags = []
    if field.get("pk"):
        flags.append("PK")
    if field.get("fk"):
        flags.append("FK")
    if field.get("uq"):
        flags.append("UQ")
    return flags


def live_key_flags(key: str) -> list[str]:
    flags = []
    if re.search(r"\bPK\b", key):
        flags.append("PK")
    if re.search(r"\bFK\b", key):
        flags.append("FK")
    if re.search(r"\bUQ\b", key):
        flags.append("UQ")
    return flags


def build_model():
    live_reader = load_live_reader()
    live_schema, live_fks, snapshot = live_reader.read_schema()
    code_schema, code_fks = parse_ddl_sources()
    model: dict[str, dict] = {}

    for table, fields in live_schema.items():
        model[table] = {
            "status": "LIVE · Supabase",
            "fields": {
                field["name"]: {
                    "name": field["name"], "type": field["type"],
                    "nullable": field["nullable"] == "Yes",
                    "flags": live_key_flags(field["key"]),
                    "fk": field["key"].split("→", 1)[1].strip() if "→" in field["key"] else "",
                    "status": "LIVE",
                }
                for field in fields
            },
            "unique_sets": [],
        }

    for table, definition in code_schema.items():
        target = model.setdefault(table, {
            "status": "CODE ONLY · absent from live Supabase",
            "fields": {}, "unique_sets": [],
        })
        if table not in live_schema:
            target["status"] = "CODE ONLY · absent from live Supabase"
        target["unique_sets"] = definition["unique_sets"]
        for name, item in definition["fields"].items():
            if name in target["fields"]:
                continue
            flags = []
            if item.get("pk"):
                flags.append("PK")
            if item.get("uq"):
                flags.append("UQ")
            if item.get("fk"):
                flags.append("FK")
            target["fields"][name] = {
                "name": name,
                "type": item.get("type", "type not found in DDL"),
                "nullable": item.get("nullable", True),
                "flags": flags,
                "fk": item.get("fk", ""),
                "status": "CODE ONLY · not live" if table in live_schema else "CODE ONLY",
            }
    for table, fields in live_schema.items():
        if table == "flyway_schema_history":
            continue
        code_fields = code_schema.get(table, {}).get("fields", {})
        for name, field in model[table]["fields"].items():
            if name not in code_fields:
                field["status"] = "LIVE ONLY · not in project DDL"

    # Supabase Auth is outside public schema; show only the referenced key.
    if any(fk["parent"] == "auth.users" for fk in live_fks):
        model["auth.users"] = {
            "status": "EXTERNAL · Supabase Auth",
            "fields": {"id": {
                "name": "id", "type": "uuid", "nullable": False,
                "flags": ["PK"], "fk": "", "status": "EXTERNAL",
            }},
            "unique_sets": [{"id"}],
        }

    def decorate_fk(fk: dict, status: str) -> dict:
        result = dict(fk)
        result["status"] = status
        fields = model.get(fk["child"], {}).get("fields", {})
        names = [part.strip() for part in fk["child_key"].split(",")]
        result["nullable"] = any(fields.get(name, {}).get("nullable", True) for name in names)
        result["one_to_one"] = fk.get("one_to_one", any(
            set(names) == unique for unique in model.get(fk["child"], {}).get("unique_sets", [])
        ))
        return result

    live_fks = [decorate_fk(fk, "LIVE FK") for fk in live_fks]
    live_signatures = {
        (fk["parent"], fk["parent_key"], fk["child"], fk["child_key"]) for fk in live_fks
    }
    added_code_fks = [
        decorate_fk(fk, "CODE ONLY · not live")
        for fk in code_fks
        if (fk["parent"], fk["parent_key"], fk["child"], fk["child_key"]) not in live_signatures
    ]
    all_fks = live_fks + added_code_fks
    return model, live_fks, added_code_fks, all_fks, snapshot, code_schema


def field_lines(table: str, data: dict) -> list[dict]:
    return sorted(data["fields"].values(), key=lambda field: (
        0 if "PK" in field["flags"] else 1,
        field["name"],
    ))


def card_height(table: str, model: dict) -> int:
    return HEADER_H + len(model[table]["fields"]) * ROW_H + 7


def esc(text: str) -> str:
    return html.escape(str(text), quote=True)


def svg_table(table: str, model: dict, x: int, y: int, width: int) -> str:
    data = model[table]
    fields = field_lines(table, data)
    height = card_height(table, model)
    status_code = data["status"].startswith("CODE ONLY")
    status_external = data["status"].startswith("EXTERNAL")
    status_live_only = data["status"].startswith("LIVE ONLY")
    stroke = ORANGE if status_code else ("#7d8da0" if status_external else ("#536ba7" if status_live_only else "#34465f"))
    fill = "#fffaf0" if status_code else ("#f6f8fb" if status_external else "#ffffff")
    dash = ' stroke-dasharray="7 5"' if status_code or status_external else ""
    parts = [
        f'<rect x="{x}" y="{y}" width="{width}" height="{height}" fill="{fill}" stroke="{stroke}" stroke-width="1.7"{dash}/>',
        f'<rect x="{x}" y="{y}" width="{width}" height="{HEADER_H}" fill="{fill}" stroke="{stroke}" stroke-width="1.7"{dash}/>',
        f'<text x="{x+10}" y="{y+18}" font-family="{FONT}" font-size="15" font-weight="700" fill="{NAVY}">{esc(table)}</text>',
        f'<text x="{x+width-9}" y="{y+17}" text-anchor="end" font-family="{FONT}" font-size="10.8" fill="{ORANGE if status_code else "#536ba7" if status_live_only else "#5e6c7d"}">{esc("CODE ONLY" if status_code else "LIVE ONLY" if status_live_only else "EXTERNAL" if status_external else "LIVE")}</text>',
    ]
    for index, field in enumerate(fields):
        row_y = y + HEADER_H + index * ROW_H
        if index:
            parts.append(f'<line x1="{x+1}" y1="{row_y}" x2="{x+width-1}" y2="{row_y}" stroke="#e7ebf0" stroke-width=".65"/>')
        flags = " ".join(field["flags"])
        not_null = "NOT NULL" if not field["nullable"] else "NULL"
        suffix = " · ".join(part for part in [flags, not_null] if part)
        fk_note = f" → {field['fk']}" if field.get("fk") else ""
        color = ORANGE if field["status"].startswith("CODE ONLY") else ("#536ba7" if field["status"].startswith("LIVE ONLY") else "#263547")
        status_tag = " · LIVE ONLY" if field["status"].startswith("LIVE ONLY") else ""
        content = f'{field["name"]} : {field["type"]} · {suffix}{status_tag}{fk_note}'
        parts.append(
            f'<text x="{x+9}" y="{row_y+11.5}" font-family="{FONT}" font-size="11" fill="{color}">{esc(content)}</text>'
        )
    return "".join(parts)


def entity_edge_svg(fk: dict, positions: dict[str, tuple[int, int, int]], model: dict, index: int) -> str:
    parent, child = fk["parent"], fk["child"]
    if parent not in positions or child not in positions:
        return ""
    px, py, pw = positions[parent]
    cx, cy, cw = positions[child]
    ph, ch = card_height(parent, model), card_height(child, model)
    if parent == child:
        sx, sy, ex, ey = px + pw, py + HEADER_H + 15, px + pw, py + HEADER_H + 45
        route_x = px + pw + 24 + (index % 2) * 13
        points = [(sx, sy), (route_x, sy), (route_x, ey), (ex, ey)]
    else:
        pcx, ccx = px + pw / 2, cx + cw / 2
        if abs(ccx - pcx) > abs((cy + ch/2) - (py + ph/2)):
            sx = px + pw if ccx > pcx else px
            ex = cx if ccx > pcx else cx + cw
            sy, ey = py + HEADER_H + 15, cy + HEADER_H + 15
            midx = (sx + ex) / 2 + (index % 3 - 1) * 12
            points = [(sx, sy), (midx, sy), (midx, ey), (ex, ey)]
        else:
            sx = px + pw - 18 if ccx >= pcx else px + 18
            ex = cx + cw - 18 if ccx >= pcx else cx + 18
            sy = py + ph if cy > py else py
            ey = cy if cy > py else cy + ch
            midy = (sy + ey) / 2 + (index % 3 - 1) * 10
            points = [(sx, sy), (sx, midy), (ex, midy), (ex, ey)]
    path = " ".join(
        ("M" if point_index == 0 else "L") + f" {point[0]:.1f} {point[1]:.1f}"
        for point_index, point in enumerate(points)
    )
    color = BLUE if fk["status"] == "LIVE FK" else ORANGE
    dash = ' stroke-dasharray="6 4"' if fk["status"] != "LIVE FK" else ""
    def bar(x: float, y: float, neighbor: tuple[float, float]) -> str:
        dx, dy = x - neighbor[0], y - neighbor[1]
        length = max(1, math.hypot(dx, dy))
        nx, ny = -dy / length, dx / length
        return f'<path d="M {x+nx*7:.1f} {y+ny*7:.1f} L {x-nx*7:.1f} {y-ny*7:.1f}" stroke="{color}" stroke-width="2.2"/>'
    def crowfoot(x: float, y: float, neighbor: tuple[float, float]) -> str:
        dx, dy = x - neighbor[0], y - neighbor[1]
        length = max(1, math.hypot(dx, dy))
        ux, uy = dx / length, dy / length
        nx, ny = -uy, ux
        bx, by = x - ux * 11, y - uy * 11
        return (
            f'<path d="M {x} {y} L {bx+nx*7:.1f} {by+ny*7:.1f} '
            f'M {x} {y} L {bx:.1f} {by:.1f} M {x} {y} L {bx-nx*7:.1f} {by-ny*7:.1f}" '
            f'fill="none" stroke="{color}" stroke-width="2.1" stroke-linecap="round"/>'
        )
    def optional(x: float, y: float, neighbor: tuple[float, float]) -> str:
        dx, dy = neighbor[0] - x, neighbor[1] - y
        length = max(1, math.hypot(dx, dy))
        ox, oy = x + dx / length * 15, y + dy / length * 15
        return f'<circle cx="{ox:.1f}" cy="{oy:.1f}" r="4" fill="#fff" stroke="{color}" stroke-width="1.8"/>'
    start_neighbor, end_neighbor = points[1], points[-2]
    markers = bar(sx, sy, start_neighbor)
    if fk["nullable"]:
        markers += optional(sx, sy, start_neighbor)
    markers += bar(ex, ey, end_neighbor) if fk["one_to_one"] else crowfoot(ex, ey, end_neighbor)
    markers += optional(ex, ey, end_neighbor)
    segments = list(zip(points, points[1:]))
    (a, b) = max(segments, key=lambda seg: math.hypot(seg[1][0]-seg[0][0], seg[1][1]-seg[0][1]))
    if abs(a[1] - b[1]) < 1:
        lx, ly, anchor = (a[0]+b[0])/2, a[1]-5, "middle"
    else:
        lx, ly, anchor = a[0]+6, (a[1]+b[1])/2, "start"
    label = "FK"
    return (
        f'<path d="{path}" fill="none" stroke="{color}" stroke-width="1.5"{dash}/>'
        + markers
        + f'<text x="{lx:.1f}" y="{ly:.1f}" text-anchor="{anchor}" font-family="{FONT}" font-size="10.8" fill="{color}">{esc(label)}</text>'
    )


def application_edge_svg(link: dict, positions: dict[str, tuple[int, int, int]], model: dict, index: int) -> str:
    """Draw a non-FK association only when both entities share a page."""
    parent, child = link["parent"], link["child"]
    px, py, pw = positions[parent]
    cx, cy, cw = positions[child]
    ph, ch = card_height(parent, model), card_height(child, model)
    # Route the email lookup around the outside of the identity page cards.
    sx, sy = px, py + ph - 10
    ex, ey = cx, cy + ch - 10
    outer_y = min(PAGE_H - 92, 620 + index * 10)
    path = f"M {sx} {sy} L 14 {sy} L 14 {outer_y} L {ex-14} {outer_y} L {ex-14} {ey} L {ex} {ey}"
    mid_x = (sx + ex) / 2
    return (
        f'<path d="{path}" fill="none" stroke="#687789" stroke-width="1.5" stroke-dasharray="3 4"/>'
        f'<rect x="{mid_x-95:.1f}" y="{outer_y-17:.1f}" width="190" height="14" fill="#fff"/>'
        f'<text x="{mid_x:.1f}" y="{outer_y-6:.1f}" text-anchor="middle" font-family="{FONT}" font-size="10.8" fill="#5c6877">{esc(link["label"])}</text>'
    )


def svg_page(page: dict, model: dict, all_fks: list[dict], counts: dict, snapshot: str) -> str:
    parts = [
        f'<svg xmlns="{SVG_NS}" width="297mm" height="210mm" viewBox="0 0 {PAGE_W} {PAGE_H}">',
        f'<rect width="{PAGE_W}" height="{PAGE_H}" fill="#ffffff"/>',
        f'<rect x="0" y="0" width="{PAGE_W}" height="67" fill="{LIGHT}"/>',
        f'<text x="30" y="34" font-family="{FONT}" font-size="23" font-weight="700" fill="{NAVY}">Zentrip — {esc(page["name"])}</text>',
        f'<text x="30" y="56" font-family="{FONT}" font-size="11.2" fill="#526174">A4 landscape · live Supabase snapshot {esc(snapshot)} · keys and nullability shown on each field</text>',
        '<line x1="30" y1="755" x2="1093" y2="755" stroke="#d2d9e3" stroke-width="1"/>',
        f'<text x="30" y="777" font-family="{FONT}" font-size="10.8" fill="#526174">PK primary key · FK foreign key · UQ unique · NULL / NOT NULL · orange = code-only · blue = live-only · cross-page FKs in register</text>',
    ]
    positions = page.get("positions", {})
    local_fks = [fk for fk in all_fks if fk["parent"] in positions and fk["child"] in positions]
    for index, fk in enumerate(local_fks):
        parts.append(entity_edge_svg(fk, positions, model, index))
    for index, link in enumerate(APP_LINKS):
        if link["parent"] in positions and link["child"] in positions:
            parts.append(application_edge_svg(link, positions, model, index))
    for table in page.get("tables", []):
        x, y, width = positions[table]
        parts.append(svg_table(table, model, x, y, width))
    if page.get("kind") == "overview":
        parts.extend(overview_svg(counts, snapshot))
    if page.get("name") == "10 Migration metadata":
        parts.extend([
            '<rect x="55" y="470" width="1010" height="150" rx="5" fill="#fff8e8" stroke="#b7791f" stroke-width="1.5"/>',
            f'<text x="75" y="500" font-family="{FONT}" font-size="15" font-weight="700" fill="#7b4c11">Infrastructure tables — intentionally not linked to application entities</text>',
            f'<text x="75" y="530" font-family="{FONT}" font-size="12" fill="#513f28">These tables record migration execution. Neither has a declared foreign key to Zentrip business data.</text>',
            f'<text x="75" y="557" font-family="{FONT}" font-size="12" fill="#513f28">The project file defines schema_migrations, but the live snapshot contains flyway_schema_history instead.</text>',
            f'<text x="75" y="584" font-family="{FONT}" font-size="12" fill="#513f28">They are shown separately rather than given an invented relationship.</text>',
        ])
    parts.append("</svg>")
    return "\n".join(parts)


def overview_svg(counts: dict, snapshot: str) -> list[str]:
    return [
        '<rect x="35" y="100" width="500" height="132" rx="5" fill="#f6f8fb" stroke="#c5cfdb"/>',
        '<text x="55" y="128" font-family="Arial,sans-serif" font-size="17" font-weight="bold" fill="#22344d">Live Supabase public schema</text>',
        f'<text x="55" y="160" font-family="Arial,sans-serif" font-size="14" fill="#263547">{counts["live_public"]} tables · {counts["live_app"]} application tables · {counts["live_columns"]} columns · {counts["live_fks"]} enforced foreign keys</text>',
        f'<text x="55" y="190" font-family="Arial,sans-serif" font-size="12" fill="#526174">Read-only metadata snapshot: {esc(snapshot)}</text>',
        '<rect x="570" y="100" width="520" height="132" rx="5" fill="#fff8e8" stroke="#b7791f"/>',
        '<text x="590" y="128" font-family="Arial,sans-serif" font-size="17" font-weight="bold" fill="#7b4c11">Project-code schema not yet live</text>',
        f'<text x="590" y="160" font-family="Arial,sans-serif" font-size="14" fill="#513f28">{counts["code_missing_tables"]} expected tables are absent from this snapshot</text>',
        f'<text x="590" y="184" font-family="Arial,sans-serif" font-size="11.5" fill="#513f28">{counts["code_missing_columns"]} expected column · {counts["code_missing_fks"]} expected FK not live</text>',
        f'<text x="590" y="204" font-family="Arial,sans-serif" font-size="11.2" fill="#536ba7">{counts["live_only_columns"]} live-only column not in project DDL</text>',
        '<text x="35" y="278" font-family="Arial,sans-serif" font-size="16" font-weight="bold" fill="#22344d">What this diagram includes</text>',
        '<text x="55" y="309" font-family="Arial,sans-serif" font-size="12" fill="#263547">• Every public table in the live snapshot, plus project tables defined in schema.sql and migrations.</text>',
        '<text x="55" y="335" font-family="Arial,sans-serif" font-size="12" fill="#263547">• The referenced auth.users key, shown as an external Supabase Auth entity.</text>',
        '<text x="55" y="361" font-family="Arial,sans-serif" font-size="12" fill="#263547">• Every FK is drawn on its detail page or the relationship map; code-only links are orange.</text>',
        '<text x="55" y="387" font-family="Arial,sans-serif" font-size="12" fill="#263547">• Each field’s PostgreSQL type, PK/FK/UQ flags, and NULL / NOT NULL state.</text>',
        '<text x="55" y="413" font-family="Arial,sans-serif" font-size="12" fill="#263547">• A separate relationship register lists parent/child columns, cardinality, and source status.</text>',
        '<rect x="35" y="470" width="1055" height="170" rx="5" fill="#fff8e8" stroke="#b7791f"/>',
        '<text x="55" y="500" font-family="Arial,sans-serif" font-size="16" font-weight="bold" fill="#7b4c11">Integrity note: not every table can have a truthful relationship line</text>',
        '<text x="55" y="530" font-family="Arial,sans-serif" font-size="12" fill="#513f28">Some lookup/cache and migration-history tables have no FK. A dotted application link is used only where code evidence supports it.</text>',
        '<text x="55" y="556" font-family="Arial,sans-serif" font-size="12" fill="#513f28">The reviewed schema contains no enforced many-to-many relationship. user_reviews.item_id is polymorphic and has no target FK.</text>',
        '<text x="55" y="582" font-family="Arial,sans-serif" font-size="12" fill="#513f28">No rows, schema, or permissions were changed to create this diagram.</text>',
        '<text x="55" y="615" font-family="Arial,sans-serif" font-size="11" fill="#6b5a42">Application-only associations are listed separately and are not database-enforced constraints.</text>',
    ]


def prepare_register(all_fks: list[dict]) -> list[dict]:
    rows = []
    for fk in all_fks:
        rows.append({
            "parent": fk["parent"], "parent_key": fk["parent_key"],
            "child": fk["child"], "child_key": fk["child_key"],
            "type": "1:1" if fk["one_to_one"] else "1:N",
            "participation": ("per child: 0..1 parent" if fk["nullable"] else "per child: 1 parent")
                             + ("; per parent: 0..1 child" if fk["one_to_one"] else "; per parent: 0..N child"),
            "nullable": fk["nullable"],
            "one_to_one": fk["one_to_one"],
            "status": fk["status"],
            "note": fk.get("delete_rule", ""),
        })
    for link in APP_LINKS:
        rows.append({
            "parent": link["parent"], "parent_key": link["parent_key"],
            "child": link["child"], "child_key": link["child_key"],
            "type": link["cardinality"], "participation": "not enforced by FK",
            "nullable": True, "one_to_one": False,
            "status": link["status"], "note": link["label"],
        })
    return rows


def wrap_register_cell(value: str, width: int) -> list[str]:
    max_chars = max(12, int(width / 5.8))
    lines, current = [], ""
    for word in str(value).split():
        chunks = [word[i:i + max_chars] for i in range(0, len(word), max_chars)]
        for chunk in chunks:
            candidate = f"{current} {chunk}".strip()
            if current and len(candidate) > max_chars:
                lines.append(current)
                current = chunk
            else:
                current = candidate
    if current:
        lines.append(current)
    return lines or [""]


def relationship_map_svg_page(name: str, rows: list[dict], page_index: int) -> str:
    """Render every FK (including cross-detail-page FKs) as a compact relationship row."""
    x0, y0, row_h = 30, 102, 34
    widths = [205, 115, 245, 230, 268]
    headers = ["Parent entity", "Link", "Child entity", "Child → parent columns", "Cardinality and source"]
    svg = [
        f'<svg xmlns="{SVG_NS}" width="297mm" height="210mm" viewBox="0 0 {PAGE_W} {PAGE_H}">',
        '<rect width="100%" height="100%" fill="#fff"/>',
        f'<rect width="{PAGE_W}" height="67" fill="{LIGHT}"/>',
        f'<text x="30" y="34" font-family="{FONT}" font-size="23" font-weight="700" fill="{NAVY}">Zentrip — {esc(name)}</text>',
        f'<text x="30" y="56" font-family="{FONT}" font-size="11.2" fill="#526174">Cross-page relationship map · page {page_index} · all connectors use the cited schema/code source</text>',
    ]
    x = x0
    for header, width in zip(headers, widths):
        svg.extend([
            f'<rect x="{x}" y="{y0}" width="{width}" height="30" fill="#eaf0fc" stroke="#b9c5d5"/>',
            f'<text x="{x+6}" y="{y0+20}" font-family="{FONT}" font-size="11" font-weight="700" fill="{NAVY}">{esc(header)}</text>',
        ])
        x += width

    for index, row in enumerate(rows):
        y = y0 + 30 + index * row_h
        is_app = row["type"] == "Application lookup"
        code_only = "CODE ONLY" in row["status"]
        color = "#687789" if is_app else (ORANGE if code_only else BLUE)
        fill = "#fffaf0" if code_only else "#ffffff"
        x_parent = x0
        x_link = x_parent + widths[0]
        x_child = x_link + widths[1]
        x_cols = x_child + widths[2]
        x_info = x_cols + widths[3]
        center_y = y + row_h / 2
        svg.extend([
            f'<rect x="{x_parent}" y="{y}" width="{widths[0]}" height="{row_h}" fill="{fill}" stroke="#e3e7ed" stroke-width=".7"/>',
            f'<rect x="{x_child}" y="{y}" width="{widths[2]}" height="{row_h}" fill="{fill}" stroke="#e3e7ed" stroke-width=".7"/>',
            f'<rect x="{x_cols}" y="{y}" width="{widths[3]}" height="{row_h}" fill="{fill}" stroke="#e3e7ed" stroke-width=".7"/>',
            f'<rect x="{x_info}" y="{y}" width="{widths[4]}" height="{row_h}" fill="{fill}" stroke="#e3e7ed" stroke-width=".7"/>',
        ])
        for cell_x, cell_w, value in [
            (x_parent, widths[0], row["parent"]),
            (x_child, widths[2], row["child"]),
            (x_cols, widths[3], f'{row["child_key"]} → {row["parent_key"]}'),
        ]:
            lines = wrap_register_cell(value, cell_w - 12)[:2]
            for line_index, line in enumerate(lines):
                svg.append(
                    f'<text x="{cell_x+6}" y="{y+13+line_index*13}" font-family="{FONT}" font-size="11" fill="{color}">{esc(line)}</text>'
                )

        dash = ' stroke-dasharray="4 3"' if is_app or code_only else ""
        svg.append(f'<line x1="{x_link+4}" y1="{center_y}" x2="{x_child}" y2="{center_y}" stroke="{color}" stroke-width="1.6"{dash}/>')
        if is_app:
            svg.append(
                f'<path d="M {x_child-8} {center_y-4} L {x_child} {center_y} L {x_child-8} {center_y+4}" fill="none" stroke="{color}" stroke-width="1.5"/>'
            )
            link_text = "APP"
        else:
            svg.append(f'<path d="M {x_link+4} {center_y-6} L {x_link+4} {center_y+6}" stroke="{color}" stroke-width="1.7"/>')
            if row["nullable"]:
                svg.append(f'<circle cx="{x_link+13}" cy="{center_y}" r="3.5" fill="#fff" stroke="{color}" stroke-width="1.4"/>')
            if row["one_to_one"]:
                svg.append(f'<path d="M {x_child-4} {center_y-6} L {x_child-4} {center_y+6}" stroke="{color}" stroke-width="1.7"/>')
            else:
                svg.append(
                    f'<path d="M {x_child} {center_y} L {x_child-9} {center_y-5} M {x_child} {center_y} L {x_child-9} {center_y} M {x_child} {center_y} L {x_child-9} {center_y+5}" fill="none" stroke="{color}" stroke-width="1.4"/>'
                )
            svg.append(f'<circle cx="{x_child-14}" cy="{center_y}" r="3.5" fill="#fff" stroke="{color}" stroke-width="1.4"/>')
            link_text = "FK"
        svg.append(
            f'<rect x="{x_link+38}" y="{center_y-7}" width="34" height="14" fill="#fff"/>'
            f'<text x="{x_link+55}" y="{center_y+4}" text-anchor="middle" font-family="{FONT}" font-size="10.8" fill="{color}">{link_text}</text>'
        )
        if is_app:
            line1 = "APP lookup · not enforced by FK"
            line2 = row.get("note", "")
        else:
            child_parent = "0..1 parent" if row["nullable"] else "1 parent"
            parent_children = "0..1" if row["one_to_one"] else "0..N"
            line1 = f'{row["type"]} · child {child_parent}; parent {parent_children}'
            line2 = row["status"] + (f' · {row["note"]}' if row.get("note") else "")
        svg.append(
            f'<text x="{x_info+6}" y="{y+13}" font-family="{FONT}" font-size="10.8" fill="{color}">{esc(line1)}</text>'
        )
        line2_y = y + 27
        svg.append(
            f'<text x="{x_info+6}" y="{line2_y}" font-family="{FONT}" font-size="10.8" fill="{color}">{esc(line2)}</text>'
        )

    svg.extend([
        f'<line x1="30" y1="755" x2="1093" y2="755" stroke="#d2d9e3"/>',
        f'<text x="30" y="777" font-family="{FONT}" font-size="10.8" fill="#526174">Bar = one · circle = optional · crowfoot = many · gray dashed = application-only, not a database FK</text>',
        "</svg>",
    ])
    return "\n".join(svg)


def drawio_html_table(table: str, model: dict) -> str:
    data = model[table]
    status_code = data["status"].startswith("CODE ONLY")
    status_live_only = data["status"].startswith("LIVE ONLY")
    stroke = ORANGE if status_code else ("#7d8da0" if data["status"].startswith("EXTERNAL") else ("#536ba7" if status_live_only else "#34465f"))
    rows = []
    for field in field_lines(table, data):
        flags = ", ".join(field["flags"])
        null = "NULL" if field["nullable"] else "NOT NULL"
        fk = f" → {field['fk']}" if field.get("fk") else ""
        labels = [field["type"]]
        if flags:
            labels.append(flags)
        labels.append(null)
        if field["status"].startswith("LIVE ONLY"):
            labels.append("LIVE ONLY")
        text = f'{field["name"]} : {" · ".join(labels)}{fk}'
        color = ORANGE if field["status"].startswith("CODE ONLY") else ("#536ba7" if field["status"].startswith("LIVE ONLY") else "#263547")
        rows.append(f'<tr><td style="padding:2px 5px;color:{color}">{html.escape(text)}</td></tr>')
    title = (
        f'<tr><th style="padding:6px;text-align:left;background:#eaf0fc;color:{NAVY}">'
        f'{html.escape(table)}<br/><span style="font-size:11px;color:{stroke}">{html.escape(data["status"])}</span></th></tr>'
    )
    return '<table style="width:100%;border-collapse:collapse;font-family:Arial,sans-serif;font-size:11px">' + title + "".join(rows) + "</table>"


def drawio_document(pages: list[dict], model: dict, all_fks: list[dict], register_pages: list[list[dict]]) -> str:
    diagrams = []
    page_list = pages + [
        {"name": f"{len(pages)+i+1:02d} Relationship map {i+1}", "kind": "register", "register_rows": rows}
        for i, rows in enumerate(register_pages)
    ]
    for pindex, page in enumerate(page_list):
        cells = ['<mxCell id="0"/>', '<mxCell id="1" parent="0"/>']
        positions = page.get("positions", {})
        ids = {table: f"t_{pindex}_{i}" for i, table in enumerate(page.get("tables", []))}
        for i, fk in enumerate(all_fks):
            if fk["parent"] not in ids or fk["child"] not in ids:
                continue
            status = fk["status"]
            color = "#455B91" if status == "LIVE FK" else ORANGE
            dash = "" if status == "LIVE FK" else "dashed=1;dashPattern=6 4;"
            start = "ERzeroToOne" if fk["nullable"] else "ERone"
            end = "ERzeroToOne" if fk["one_to_one"] else "ERzeroToMany"
            label = f'{fk["child_key"]} → {fk["parent_key"]}'
            style = f"edgeStyle=orthogonalEdgeStyle;rounded=0;orthogonalLoop=1;jettySize=auto;html=1;strokeColor={color};strokeWidth=2;{dash}startArrow={start};startFill=0;endArrow={end};endFill=0;"
            cells.append(
                f'<mxCell id="e_{pindex}_{i}" value="{html.escape(label, quote=True)}" style="{style}" edge="1" parent="1" source="{ids[fk["parent"]]}" target="{ids[fk["child"]]}"><mxGeometry relative="1" as="geometry"/></mxCell>'
            )
        for i, link in enumerate(APP_LINKS):
            if link["parent"] in ids and link["child"] in ids:
                style = "edgeStyle=orthogonalEdgeStyle;rounded=0;orthogonalLoop=1;jettySize=auto;html=1;strokeColor=#687789;strokeWidth=1.5;dashed=1;dashPattern=3 4;endArrow=none;"
                cells.append(
                    f'<mxCell id="app_{pindex}_{i}" value="{html.escape(link["label"], quote=True)}" style="{style}" edge="1" parent="1" source="{ids[link["parent"]]}" target="{ids[link["child"]]}"><mxGeometry relative="1" as="geometry"/></mxCell>'
                )
        if page.get("kind") == "register":
            values = page["register_rows"]
            for row_index, relation in enumerate(values):
                y = 90 + row_index * 44
                is_app = relation["type"] == "Application lookup"
                code_only = "CODE ONLY" in relation["status"]
                color = "#687789" if is_app else (ORANGE if code_only else "#455B91")
                fill = "#FFFAF0" if code_only else "#FFFFFF"
                parent_id = f"rp_{pindex}_{row_index}"
                child_id = f"rc_{pindex}_{row_index}"
                parent_value = html.escape(relation["parent"], quote=True)
                child_value = html.escape(relation["child"], quote=True)
                for entity_id, entity_value, x, width in [
                    (parent_id, parent_value, 30, 210),
                    (child_id, child_value, 390, 245),
                ]:
                    cells.append(
                        f'<mxCell id="{entity_id}" value="{entity_value}" style="rounded=0;whiteSpace=wrap;html=1;align=center;verticalAlign=middle;strokeColor={color};strokeWidth=1.4;{"dashed=1;dashPattern=6 4;" if code_only else ""}fillColor={fill};fontColor=#263547;fontSize=11;" vertex="1" parent="1"><mxGeometry x="{x}" y="{y}" width="{width}" height="34" as="geometry"/></mxCell>'
                    )
                if is_app:
                    edge_style = "edgeStyle=orthogonalEdgeStyle;rounded=0;html=1;strokeColor=#687789;strokeWidth=1.5;dashed=1;dashPattern=3 4;endArrow=none;"
                    link_label = "APP"
                else:
                    start = "ERzeroToOne" if relation["nullable"] else "ERone"
                    end = "ERzeroToOne" if relation["one_to_one"] else "ERzeroToMany"
                    edge_style = f"edgeStyle=orthogonalEdgeStyle;rounded=0;html=1;strokeColor={color};strokeWidth=1.8;{'dashed=1;dashPattern=6 4;' if code_only else ''}startArrow={start};startFill=0;endArrow={end};endFill=0;"
                    link_label = "FK"
                cells.append(
                    f'<mxCell id="re_{pindex}_{row_index}" value="{link_label}" style="{edge_style}" edge="1" parent="1" source="{parent_id}" target="{child_id}"><mxGeometry relative="1" as="geometry"/></mxCell>'
                )
                join_value = html.escape(f'{relation["child_key"]} → {relation["parent_key"]}', quote=True)
                if is_app:
                    info_text = f'APP lookup · not enforced by FK<br/>{relation.get("note", "")}'
                else:
                    child_parent = "0..1 parent" if relation["nullable"] else "1 parent"
                    parent_children = "0..1" if relation["one_to_one"] else "0..N"
                    info_text = (
                        f'{relation["type"]} · child {child_parent}; parent {parent_children}<br/>'
                        f'{relation["status"]}'
                        + (f' · {relation["note"]}' if relation.get("note") else "")
                    )
                info_value = html.escape(info_text, quote=True)
                cells.append(
                    f'<mxCell id="rj_{pindex}_{row_index}" value="{join_value}" style="shape=rectangle;whiteSpace=wrap;html=1;align=left;verticalAlign=middle;strokeColor=#e3e7ed;fillColor={fill};fontColor={color};fontSize=11;" vertex="1" parent="1"><mxGeometry x="650" y="{y}" width="220" height="34" as="geometry"/></mxCell>'
                )
                cells.append(
                    f'<mxCell id="ri_{pindex}_{row_index}" value="{info_value}" style="shape=rectangle;whiteSpace=wrap;html=1;align=left;verticalAlign=middle;strokeColor=#e3e7ed;fillColor={fill};fontColor={color};fontSize=11;" vertex="1" parent="1"><mxGeometry x="875" y="{y}" width="218" height="34" as="geometry"/></mxCell>'
                )
        elif page.get("kind") == "overview":
            value = html.escape("<b>Coverage summary</b><br/>See the matching PDF page for the schema counts, code/live differences, and integrity notes.", quote=True)
            cells.append(f'<mxCell id="overview_{pindex}" value="{value}" style="shape=note;whiteSpace=wrap;html=1;strokeColor=#455B91;fillColor=#EAF0FC;fontColor=#22344D;fontSize=16;" vertex="1" parent="1"><mxGeometry x="35" y="100" width="1000" height="130" as="geometry"/></mxCell>')
        else:
            for i, table in enumerate(page["tables"]):
                x, y, width = positions[table]
                value = html.escape(drawio_html_table(table, model), quote=True)
                status_code = model[table]["status"].startswith("CODE ONLY")
                style = f"rounded=0;whiteSpace=wrap;html=1;align=left;verticalAlign=top;strokeColor={ORANGE if status_code else '#34465F'};strokeWidth=1.5;{'dashed=1;dashPattern=7 5;' if status_code else ''}fillColor={'#FFFAF0' if status_code else '#FFFFFF'};fontColor=#263547;fontSize=11;spacing=0;"
                cells.append(
                    f'<mxCell id="{ids[table]}" value="{value}" style="{style}" vertex="1" parent="1"><mxGeometry x="{x}" y="{y}" width="{width}" height="{card_height(table, model)}" as="geometry"/></mxCell>'
                )
        page_width = PAGE_W
        page_height = PAGE_H
        diagrams.append(
            f'<diagram id="d{pindex+1}" name="{html.escape(page["name"], quote=True)}">'
            f'<mxGraphModel dx="{page_width}" dy="{page_height}" grid="1" gridSize="10" guides="1" tooltips="1" connect="1" arrows="1" fold="1" page="1" pageScale="1" pageWidth="{page_width}" pageHeight="{page_height}" math="0" shadow="0">'
            '<root>' + "".join(cells) + '</root></mxGraphModel></diagram>'
        )
    return '<mxfile host="app.diagrams.net" version="24.7.17">' + "".join(diagrams) + "</mxfile>"


def main() -> None:
    model, live_fks, code_only_fks, all_fks, snapshot, code_schema = build_model()
    live_public = [
        table for table, data in model.items()
        if data["status"].startswith("LIVE") and not table.startswith("auth.")
    ]
    code_missing_fields = [
        (table, field) for table, data in model.items()
        for field, item in data["fields"].items()
        if item["status"].startswith("CODE ONLY · not live")
    ]
    live_only_fields = [
        (table, field) for table, data in model.items()
        for field, item in data["fields"].items()
        if item["status"].startswith("LIVE ONLY")
    ]
    public_app_live = [table for table in live_public if table != "flyway_schema_history"]
    code_expected_app = [table for table in code_schema if table != "schema_migrations"]
    live_names = set(live_public)
    code_names = set(code_schema)
    missing_app_tables = sorted((code_names - live_names) - {"schema_migrations"})
    live_columns = sum(
        1 for table in live_names for item in model[table]["fields"].values()
        if item["status"] == "LIVE" or item["status"].startswith("LIVE ONLY")
    )
    counts = {
        "live_public": len(live_public),
        "live_app": len(public_app_live),
        "live_columns": live_columns,
        "live_fks": len(live_fks),
        "code_missing_tables": len(missing_app_tables) + int("schema_migrations" not in live_names),
        "code_missing_columns": len(code_missing_fields),
        "code_missing_fks": len(code_only_fks),
        "live_only_columns": len(live_only_fields),
        "all_public": len(live_names | code_names),
        "code_app": len(code_expected_app),
    }

    # Validate every entity appears exactly once on the detail pages.
    placed = [table for page in PAGES for table in page["tables"]]
    expected = sorted(set(live_names | code_names) | ({"auth.users"} if "auth.users" in model else set()))
    if sorted(placed) != expected:
        raise RuntimeError(f"Page coverage mismatch. Missing={sorted(set(expected)-set(placed))}; duplicate={sorted(t for t in set(placed) if placed.count(t)>1)}")
    if any(fk["parent"] not in model or fk["child"] not in model for fk in all_fks):
        raise RuntimeError("A foreign key endpoint is missing from the complete ERD.")

    register_rows = prepare_register(all_fks)
    chunk_size = math.ceil(len(register_rows) / 3)
    register_pages = [
        register_rows[start:start + chunk_size]
        for start in range(0, len(register_rows), chunk_size)
    ]
    OUT.mkdir(parents=True, exist_ok=True)

    for index, page in enumerate(PAGES, 1):
        path = OUT / f"page-{index:02d}.svg"
        path.write_text(svg_page(page, model, all_fks, counts, snapshot), encoding="utf-8")
    for index, rows in enumerate(register_pages, len(PAGES) + 1):
        path = OUT / f"page-{index:02d}.svg"
        path.write_text(relationship_map_svg_page(f"{index:02d} Relationship map", rows, index-len(PAGES)), encoding="utf-8")
    (OUT / "Zentrip-Complete-ERD.drawio").write_text(
        drawio_document(PAGES, model, all_fks, register_pages), encoding="utf-8",
    )
    report = [
        "Zentrip complete ERD schema reconciliation",
        f"Live snapshot: {snapshot}",
        f"Live public tables: {len(live_public)} (application: {len(public_app_live)}), columns: {live_columns}, enforced FKs: {len(live_fks)}",
        f"Project SQL tables: {len(code_schema)} (application: {len(code_expected_app)}), missing public tables: {', '.join(missing_app_tables)}",
        f"Code-only columns in existing live tables: {', '.join(f'{t}.{c}' for t,c in code_missing_fields) or 'none'}",
        f"Live-only columns absent from project DDL: {', '.join(f'{t}.{c}' for t,c in live_only_fields) or 'none'}",
        f"Code-only FKs: {len(code_only_fks)}",
        f"Combined public entities: {counts['all_public']}; external referenced entity: auth.users",
        "No database rows, schema, or permissions were modified.",
    ]
    (OUT / "schema-reconciliation.txt").write_text("\n".join(report) + "\n", encoding="utf-8")
    print("\n".join(report))
    print(f"Created {len(PAGES)+len(register_pages)} A4 landscape SVG pages and {OUT / 'Zentrip-Complete-ERD.drawio'}")


if __name__ == "__main__":
    main()
