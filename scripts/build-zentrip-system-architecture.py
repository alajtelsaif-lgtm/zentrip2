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
    box(x, y, 212, 76, "#ffffff", "#d7e2ef", 16, 1)
    emit(f'<circle cx="{x + 36}" cy="{y + 38}" r="22" fill="#e8f1ff"/>')
    emit(f'<circle cx="{x + 36}" cy="{y + 29}" r="7" fill="#3d70a6"/>')
    emit(
        f'<path d="M{x + 22} {y + 54}c1-10 6-15 14-15s13 5 14 15" '
        'fill="none" stroke="#3d70a6" stroke-width="3.5" stroke-linecap="round"/>'
    )
    label(x + 72, y + 34, name, 16, 700, "#1c3049")
    label(x + 72, y + 56, detail, 12, 400, "#62758b")


def provider(y: int, title: str, detail: str, symbol: str, badge: str | None = None) -> None:
    # Consistent category pictograms, not provider logos.
    box(1145, y, 570, 56, "#ffffff", "#dce7ed", 14, 1)
    cx, cy = 1175, y + 28
    emit(f'<circle cx="{cx}" cy="{cy}" r="20" fill="#eaf2fb"/>')
    color = "#346b9e"
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
    label(1210, y + 24, title, 14, 700, "#1c3049")
    label(1210, y + 43, detail, 11, 400, "#62758b")
    if badge:
        label(1693, y + 34, badge, 9, 700, "#55799c", "end")


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
        '<desc id="desc">A modern technical architecture diagram showing Zentrip users, Flutter client, '
        'Spring Boot API, external data providers, and Supabase PostgreSQL.</desc>'
    )
    emit(
        """<defs>
          <marker id="arrowHead" viewBox="0 0 10 10" refX="8.5" refY="5"
            markerWidth="8" markerHeight="8" orient="auto-start-reverse">
            <path d="M0 0L10 5L0 10z" fill="#607c9b"/>
          </marker>
          <style>text { font-family: Arial, Helvetica, sans-serif; }</style>
        </defs>"""
    )
    box(0, 0, WIDTH, HEIGHT, "#f1f5fa", "#f1f5fa", 0)
    emit('<rect x="0" y="0" width="1800" height="124" fill="#152b49"/>')
    label(66, 58, "Zentrip System Architecture", 34, 700, "#ffffff")
    label(68, 91, "Current implementation · Flutter · Spring Boot · Supabase", 15, 400, "#c8d7e9")
    box(1538, 39, 194, 42, "#233d60", "#3b587e", 21, 1)
    label(1635, 66, "TECHNICAL BLUEPRINT", 10, 700, "#d7e4f2", "middle")

    # Color-coded lanes form a modern, print-friendly architecture canvas.
    box(42, 142, 1716, 706, "#ffffff", "#dce4ee", 22, 1)
    box(60, 164, 250, 666, "#f4f8fe", "#e1eaf6", 18, 1)
    box(326, 164, 390, 666, "#f6f9fd", "#e1eaf2", 18, 1)
    box(732, 164, 360, 666, "#f7f6fe", "#e7e3f6", 18, 1)
    box(1108, 164, 632, 666, "#f3f9fa", "#dcebed", 18, 1)
    label(84, 202, "ACCESS", 12, 700, "#4777ad")
    label(350, 202, "CLIENT", 12, 700, "#4777ad")
    label(758, 202, "API CORE", 12, 700, "#725fc1")
    label(1138, 202, "EXTERNAL DATA", 12, 700, "#318b91")

    # Request, provider, and persistence paths sit beneath the component cards.
    arrow("M292 298H315V370H350", color="#7189a6")
    arrow("M292 463H350", color="#7189a6")
    arrow("M292 628H315V490H350", color="#7189a6")
    arrow("M700 420H760", bidirectional=True, color="#5d7da3")
    arrow("M1065 420H1124", bidirectional=True, color="#5d7da3")
    emit('<path d="M1124 248V752" fill="none" stroke="#89a0b6" stroke-width="2.5"/>')
    for center_y in [248, 320, 392, 464, 536, 608, 680, 752]:
        arrow(f"M1124 {center_y}H1145", color="#89a0b6")
    arrow("M912 565V635", bidirectional=True, color="#5d9b96")
    arrow("M465 565V625", dashed=True, color="#8399b0")
    arrow("M610 565V625", dashed=True, color="#8399b0")

    # Role cards.
    actor(80, 260, "Admin", "Manages platform")
    actor(80, 425, "Partner", "Owns listings")
    actor(80, 590, "Customer", "Searches and books")

    # Flutter client card and its device-owned data.
    box(350, 245, 350, 320, "#ffffff", "#d7e3f0", 20, 1)
    box(378, 275, 54, 82, "#eaf2ff", "#cbdcf0", 14, 1)
    emit('<rect x="384" y="282" width="42" height="65" rx="6" fill="#ffffff" stroke="#9eb9d7" stroke-width="1.5"/>')
    emit('<circle cx="405" cy="351" r="2" fill="#4777ad"/>')
    label(452, 304, "Flutter", 20, 700, "#1e3552")
    label(452, 328, "Web · mobile", 13, 500, "#62758b")
    lines(
        380,
        395,
        ["Search · book · My Trips", "Role-based dashboards", "Flights · hotels · places · AI", "REST API · AI stream"],
        13,
        "#4e637a",
        25,
    )

    box(350, 625, 165, 135, "#ffffff", "#dce6ee", 18, 1)
    emit('<rect x="414" y="644" width="36" height="27" rx="5" fill="#eaf2ff" stroke="#7da0c4" stroke-width="2"/>')
    emit('<path d="M414 652h36M414 661h36" stroke="#7da0c4" stroke-width="2"/>')
    label(432, 700, "Local state", 14, 700, "#264563", "middle")
    lines(432, 724, ["Session · favorites", "Alerts · chat cache"], 11, "#667b90", 16, 400, "middle")

    box(530, 625, 170, 135, "#ffffff", "#dce6ee", 18, 1)
    emit('<path d="M585 650l14-6 14 6 14-6v28l-14 6-14-6-14 6zM599 644v28M613 650v28" fill="none" stroke="#4777ad" stroke-width="2.2" stroke-linejoin="round"/>')
    label(615, 700, "Map tiles", 14, 700, "#264563", "middle")
    lines(615, 724, ["OpenStreetMap", "client direct"], 11, "#667b90", 16, 400, "middle")

    # Central API card.
    box(760, 280, 305, 285, "#ffffff", "#dcd7f2", 20, 1)
    emit('<circle cx="912" cy="345" r="42" fill="#6d5bc7"/>')
    emit(f'<polygon points="{gear_points(912, 345, 28, 23)}" fill="#ffffff"/>')
    emit('<circle cx="912" cy="345" r="9" fill="#6d5bc7"/>')
    label(912, 420, "Spring Boot API", 20, 700, "#2b2854", "middle")
    lines(
        912,
        454,
        ["Auth · roles · ownership", "Partner + provider data", "Simulated checkout"],
        13,
        "#615d7e",
        23,
        400,
        "middle",
    )

    # Provider cards use consistent semantic icons rather than initials or logos.
    providers = [
        ("Duffel", "Flights · search only", "plane", None),
        ("LiteAPI", "Hotels · rates only", "bed", None),
        ("OpenTripMap", "Tourist places", "landmark", None),
        ("Geoapify", "Geocoding · airports", "pin", None),
        ("SerpAPI", "Nearby · maps", "map", None),
        ("Google Gemini", "Zen AI · streamed replies", "chat", None),
        ("Frankfurter", "Currency rates", "currency", None),
        ("Optional", "Google Places off · airport import", "plus", "OPTIONAL"),
    ]
    for index, item in enumerate(providers):
        provider(220 + index * 72, *item)

    # Backend-only Supabase storage.
    emit('<ellipse cx="912" cy="650" rx="152" ry="16" fill="#e8f6f4" stroke="#65aaa4" stroke-width="2"/>')
    emit('<path d="M760 650v140c0 9 68 16 152 16s152-7 152-16V650" fill="#e8f6f4" stroke="#65aaa4" stroke-width="2"/>')
    emit('<ellipse cx="912" cy="790" rx="152" ry="16" fill="#e8f6f4" stroke="#65aaa4" stroke-width="2"/>')
    label(912, 678, "Supabase PostgreSQL", 17, 700, "#286e69", "middle")
    label(912, 701, "Users · partners · listings", 12, 400, "#4e7774", "middle")
    label(912, 719, "Trips · bookings · transfers", 12, 400, "#4e7774", "middle")
    label(912, 737, "Offers · seats · payments", 12, 400, "#4e7774", "middle")
    label(912, 755, "Landmarks · visits · AI chat", 12, 400, "#4e7774", "middle")
    label(912, 773, "Profiles · preferences · reviews", 12, 400, "#4e7774", "middle")

    # Short scope notes.
    box(62, 866, 1676, 46, "#ffffff", "#dce4ee", 14, 1)
    label(96, 895, "Flutter → API → DB", 12, 700, "#3e658d")
    label(630, 895, "Duffel / LiteAPI: data only", 12, 700, "#3b8a88")
    label(1202, 895, "Checkout: simulated", 12, 700, "#6d5bc7")
    label(912, 952, "Zentrip System Architecture", 18, 700, "#263c58", "middle")
    label(
        912,
        975,
        "Live APIs unverified · production RLS needs verification · push disabled",
        11,
        400,
        "#6b7d91",
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
    body {{ margin: 0; padding: 18px; background: #f1f5fa; font-family: Arial, Helvetica, sans-serif; }}
    main {{ max-width: 1800px; margin: auto; }}
    .figure {{ overflow: auto; background: #f1f5fa; border: 1px solid #dce4ee; border-radius: 16px; }}
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
