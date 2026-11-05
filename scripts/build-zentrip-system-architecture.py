#!/usr/bin/env python3
"""Generate a reference-style, code-aligned Zentrip system architecture figure."""

from __future__ import annotations

from html import escape
from math import cos, pi, sin
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "docs" / "APP_ANALYSIS.md"
OUTPUT = ROOT / "generated-artifacts"
SVG_PATH = OUTPUT / "ZenTrip-System-Architecture.svg"
HTML_PATH = OUTPUT / "ZenTrip-System-Architecture.html"

WIDTH, HEIGHT = 1800, 1000
items: list[str] = []


def emit(value: str) -> None:
    items.append(value)


def label(
    x: int,
    y: int,
    value: str,
    size: int = 15,
    weight: int = 400,
    color: str = "#263b4a",
    anchor: str = "start",
) -> None:
    emit(
        f'<text x="{x}" y="{y}" font-size="{size}" font-weight="{weight}" '
        f'fill="{color}" text-anchor="{anchor}">{escape(value)}</text>'
    )


def lines(
    x: int,
    y: int,
    values: list[str],
    size: int = 13,
    color: str = "#526979",
    step: int = 18,
    weight: int = 400,
    anchor: str = "start",
) -> None:
    emit(f'<text x="{x}" y="{y}" font-size="{size}" font-weight="{weight}" fill="{color}" text-anchor="{anchor}">')
    for index, value in enumerate(values):
        emit(f'<tspan x="{x}" dy="{0 if index == 0 else step}">{escape(value)}</tspan>')
    emit("</text>")


def box(
    x: int,
    y: int,
    w: int,
    h: int,
    fill: str,
    stroke: str,
    radius: int = 12,
    stroke_width: int = 2,
) -> None:
    emit(
        f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{radius}" '
        f'fill="{fill}" stroke="{stroke}" stroke-width="{stroke_width}"/>'
    )


def arrow(d: str, dashed: bool = False, bidirectional: bool = False, color: str = "#345c77") -> None:
    dash = ' stroke-dasharray="7 7"' if dashed else ""
    start = ' marker-start="url(#arrowHead)"' if bidirectional else ""
    emit(
        f'<path d="{d}" fill="none" stroke="{color}" stroke-width="2.5" '
        f'stroke-linecap="round" stroke-linejoin="round"{dash}{start} '
        'marker-end="url(#arrowHead)"/>'
    )


def actor(x: int, y: int, name: str, detail: str) -> None:
    box(x, y, 210, 70, "#f5faf6", "#8ca995", 12)
    emit(f'<circle cx="{x + 28}" cy="{y + 24}" r="8" fill="#486d58"/>')
    emit(
        f'<path d="M{x + 13} {y + 56}c1-12 7-18 15-18s14 6 15 18" '
        'fill="none" stroke="#486d58" stroke-width="4" stroke-linecap="round"/>'
    )
    label(x + 57, y + 29, name, 16, 700, "#294233")
    label(x + 57, y + 51, detail, 12, 400, "#607669")


def provider(y: int, title: str, detail: str, symbol: str, badge: str | None = None) -> None:
    # Simple category pictograms, not provider logos.
    cx, cy = 1192, y + 24
    emit(f'<circle cx="{cx}" cy="{cy}" r="20" fill="#f0f5fa" stroke="#7190a5" stroke-width="2"/>')
    color = "#315b77"
    if symbol == "plane":
        emit(f'<path d="M{cx-15} {cy+2}l12-3 6-12 3 1-2 10 10-2 3-3 2 1-3 5-12 5-1 8-2 1-3-7-10 1z" fill="{color}"/>')
    elif symbol == "bed":
        emit(f'<path d="M{cx-13} {cy+9}v-17h4v8h18v9M{cx-9} {cy-2}v-5h6v5M{cx-13} {cy+4}h22" fill="none" stroke="{color}" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"/>')
    elif symbol == "landmark":
        emit(f'<path d="M{cx-14} {cy-6}l14-8 14 8zM{cx-11} {cy+10}h22M{cx-8} {cy-4}v12M{cx} {cy-4}v12M{cx+8} {cy-4}v12" fill="none" stroke="{color}" stroke-width="2.2" stroke-linejoin="round"/>')
    elif symbol == "pin":
        emit(f'<path d="M{cx} {cy+14}s-11-12-11-20a11 11 0 1 1 22 0c0 8-11 20-11 20z" fill="none" stroke="{color}" stroke-width="2.2"/>')
        emit(f'<circle cx="{cx}" cy="{cy-6}" r="3" fill="{color}"/>')
    elif symbol == "map":
        emit(f'<path d="M{cx-14} {cy-10}l9-4 10 4 9-4v25l-9 4-10-4-9 4zM{cx-5} {cy-14}v25M{cx+5} {cy-10}v25" fill="none" stroke="{color}" stroke-width="2"/>')
    elif symbol == "chat":
        emit(f'<path d="M{cx-13} {cy-10}h26v18h-15l-8 6v-6h-3z" fill="none" stroke="{color}" stroke-width="2" stroke-linejoin="round"/>')
        emit(f'<path d="M{cx+4} {cy-7}v7M{cx+1} {cy-4}h6" stroke="{color}" stroke-width="2"/>')
    elif symbol == "currency":
        label(cx, cy + 6, "$", 20, 700, color, "middle")
    else:
        emit(f'<path d="M{cx-8} {cy}h16M{cx} {cy-8}v16" stroke="{color}" stroke-width="2.6" stroke-linecap="round"/>')
    label(1227, y + 22, title, 14, 700, "#263e50")
    label(1227, y + 42, detail, 11, 400, "#5c7180")
    if badge:
        label(1690, y + 22, badge, 9, 700, "#8c6d30", "end")


def gear_points(cx: int, cy: int, outer: int, inner: int, count: int = 32) -> str:
    points = []
    for index in range(count):
        radius = outer if index % 4 in (0, 1) else inner
        angle = 2 * pi * index / count - pi / 2
        points.append(f"{cx + radius * cos(angle):.1f},{cy + radius * sin(angle):.1f}")
    return " ".join(points)


def make_svg() -> str:
    emit(f'<svg xmlns="http://www.w3.org/2000/svg" role="img" aria-labelledby="title desc" viewBox="0 0 {WIDTH} {HEIGHT}">')
    emit(
        '<title id="title">Zentrip System Architecture</title>'
        '<desc id="desc">Customer, admin, and partner roles use the Flutter app. '
        'The Spring Boot API verifies access, reads provider data, and persists records in Supabase PostgreSQL.</desc>'
    )
    emit(
        """<defs>
          <marker id="arrowHead" viewBox="0 0 10 10" refX="8.5" refY="5"
            markerWidth="8" markerHeight="8" orient="auto-start-reverse">
            <path d="M0 0L10 5L0 10z" fill="#345c77"/>
          </marker>
          <style>text { font-family: Arial, Helvetica, sans-serif; }</style>
        </defs>"""
    )
    box(0, 0, WIDTH, HEIGHT, "#ffffff", "#ffffff", 0)
    label(68, 57, "4.6  System Architecture", 30, 700, "#20384a")
    label(68, 83, "Zentrip", 14, 400, "#647989")
    box(48, 108, 1704, 790, "#ffffff", "#738b9b", 2)
    label(98, 145, "USERS", 12, 700, "#627b6b")
    label(380, 145, "FLUTTER APP", 12, 700, "#557995")
    label(780, 145, "SPRING BOOT API", 12, 700, "#585b88")
    label(1140, 145, "PROVIDER DATA", 12, 700, "#8f7236")

    # Main request and data flows are behind the component symbols.
    arrow("M310 240H337V365H380")
    arrow("M310 415H380")
    arrow("M310 590H337V500H380")
    arrow("M680 440H765", bidirectional=True)
    arrow("M995 440H1115", bidirectional=True)
    arrow("M1115 188V734", color="#7a93a5")
    for center_y in [188, 266, 344, 422, 500, 578, 656, 734]:
        arrow(f"M1115 {center_y}H1168", bidirectional=True)
    arrow("M880 550V662", bidirectional=True, color="#477b78")
    arrow("M465 560V665", dashed=True, color="#738b9b")
    arrow("M605 560V665", dashed=True, color="#738b9b")

    # User roles.
    actor(100, 205, "Admin", "manages platform")
    actor(100, 380, "Partner", "owns listings")
    actor(100, 555, "Customer", "searches and books")

    # Flutter application interface and client-owned state.
    box(350, 170, 350, 390, "#f8fbfe", "#91abc0", 2)
    # Phone/browser icon.
    box(375, 258, 72, 126, "#ffffff", "#416c8d", 5)
    emit('<rect x="383" y="272" width="56" height="91" rx="3" fill="#edf4f9" stroke="#8aa8bc" stroke-width="1"/>')
    emit('<circle cx="411" cy="374" r="3" fill="#416c8d"/>')
    label(465, 277, "Flutter", 19, 700, "#294c66")
    label(465, 302, "Web + mobile", 13, 500, "#607687")
    lines(
        465,
        331,
        [
            "Search · book · My Trips",
            "Admin / partner dashboards",
            "Flights · hotels · places · AI",
            "REST / JSON · AI stream",
        ],
        13,
        "#526979",
        22,
    )

    # Local-only client storage and map tiles are separate from the backend.
    box(350, 665, 162, 100, "#f4f8f5", "#9cb5a3", 12)
    label(431, 697, "Local state", 14, 700, "#345845", "middle")
    lines(431, 720, ["Session · favorites", "Alerts · locale · chat"], 11, "#607669", 16, 400, "middle")
    box(528, 665, 172, 100, "#f6f9fb", "#a8bac7", 12)
    label(614, 697, "Map tiles", 14, 700, "#3b586b", "middle")
    lines(614, 720, ["OpenStreetMap", "client direct"], 11, "#637987", 16, 400, "middle")
    # Spring Boot is the central hub, like the central processing node in the reference.
    emit(f'<polygon points="{gear_points(880, 445, 116, 103)}" fill="#dbe8f0" stroke="#345f7c" stroke-width="3"/>')
    emit('<circle cx="880" cy="445" r="86" fill="#ffffff" stroke="#345f7c" stroke-width="3"/>')
    label(880, 420, "Spring Boot API", 19, 700, "#23445c", "middle")
    lines(
        880,
        444,
        [
            "Verified roles and ownership",
            "Controllers and services",
            "Partner / provider data",
            "Mock checkout",
        ],
        12,
        "#536b7b",
        19,
        400,
        "middle",
    )

    # Provider labels and small circular icons.
    providers = [
        ("Duffel", "Flights · search only", "plane", "DATA"),
        ("LiteAPI", "Hotels · rates only", "bed", "DATA"),
        ("OpenTripMap", "Tourist places", "landmark", None),
        ("Geoapify", "Geocoding · airports", "pin", None),
        ("SerpAPI", "Nearby · maps", "map", None),
        ("Requesty", "Zen AI", "chat", None),
        ("Frankfurter", "Currency rates", "currency", None),
        ("Optional", "Google Places off · airport import", "plus", "OPTIONAL"),
    ]
    for index, item in enumerate(providers):
        provider(164 + index * 78, *item)

    # Supabase PostgreSQL is backend-only. Use a cylinder, with the main API above it.
    emit('<ellipse cx="880" cy="680" rx="180" ry="18" fill="#edf7f6" stroke="#588986" stroke-width="2"/>')
    emit('<path d="M700 680v144c0 11 81 20 180 20s180-9 180-20V680" fill="#edf7f6" stroke="#588986" stroke-width="2"/>')
    emit('<ellipse cx="880" cy="824" rx="180" ry="20" fill="#edf7f6" stroke="#588986" stroke-width="2"/>')
    label(880, 708, "Supabase PostgreSQL", 17, 700, "#285553", "middle")
    label(880, 731, "Users · partners · listings", 12, 400, "#426c6a", "middle")
    label(880, 749, "Trips · bookings · transfers", 12, 400, "#426c6a", "middle")
    label(880, 767, "Offers · seats · payments", 12, 400, "#426c6a", "middle")
    label(880, 785, "Landmarks · visits · AI chat", 12, 400, "#426c6a", "middle")
    label(880, 803, "Profiles · preferences · reviews", 12, 400, "#426c6a", "middle")

    # Scope and trust boundaries, deliberately placed in the figure footer.
    box(70, 852, 1660, 35, "#f8fafb", "#dce4e8", 7, 1)
    label(90, 874, "Flutter → API → database", 11, 600, "#4c6575")
    label(565, 874, "Duffel / LiteAPI: data only", 11, 600, "#806631")
    label(1010, 874, "Checkout: simulated", 11, 600, "#806631")
    label(880, 951, "Figure 4.6: Zentrip System Architecture", 18, 600, "#405b6c", "middle")
    label(
        880,
        975,
        "Live APIs unverified · production RLS needs verification · push disabled",
        11,
        400,
        "#6d7f8b",
        "middle",
    )
    emit("</svg>")
    return "".join(items)


def make_html(svg: str) -> str:
    return f"""<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Zentrip System Architecture</title>
  <style>
    * {{ box-sizing: border-box; }}
    body {{ margin: 0; padding: 18px; background: #eef2f4; font-family: Arial, Helvetica, sans-serif; }}
    main {{ max-width: 1800px; margin: auto; }}
    .figure {{ overflow: auto; background: white; border: 1px solid #d8e0e5; border-radius: 10px; }}
    svg {{ display: block; width: 100%; height: auto; min-width: 1200px; }}
    @media (max-width: 760px) {{ body {{ padding: 6px; }} svg {{ min-width: 1500px; }} }}
    @media print {{ body {{ padding: 0; background: white; }} .figure {{ overflow: visible; border: 0; }} svg {{ min-width: 0; width: 100%; }} }}
  </style>
</head>
<body><main><div class="figure">{svg}</div></main></body>
</html>"""


def main() -> None:
    if not SOURCE.exists():
        raise SystemExit("Expected docs/APP_ANALYSIS.md as the architecture reference is missing.")
    audit = SOURCE.read_text(encoding="utf-8")
    for expected in ("Flutter", "Spring Boot", "Supabase PostgreSQL", "Duffel", "LiteAPI"):
        if expected not in audit:
            raise SystemExit(f"Architecture audit no longer mentions {expected}; recheck diagram alignment.")
    OUTPUT.mkdir(parents=True, exist_ok=True)
    svg = make_svg()
    SVG_PATH.write_text(svg, encoding="utf-8")
    HTML_PATH.write_text(make_html(svg), encoding="utf-8")
    print(f"Created {SVG_PATH.relative_to(ROOT)}")
    print(f"Created {HTML_PATH.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
