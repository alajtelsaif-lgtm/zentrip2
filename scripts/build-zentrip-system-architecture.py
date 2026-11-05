#!/usr/bin/env python3
"""Build the reference-style Zentrip system architecture diagram."""

from __future__ import annotations

from html import escape
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "docs" / "zentrip_system_architecture.mmd"
OUTPUT = ROOT / "generated-artifacts"
SVG_PATH = OUTPUT / "ZenTrip-System-Architecture.svg"
HTML_PATH = OUTPUT / "ZenTrip-System-Architecture.html"

WIDTH, HEIGHT = 1800, 1000
parts: list[str] = []


def add(value: str) -> None:
    parts.append(value)


def text(
    x: float,
    y: float,
    value: str,
    size: int = 16,
    weight: int = 400,
    color: str = "#24394a",
    anchor: str = "start",
) -> None:
    add(
        f'<text x="{x}" y="{y}" font-size="{size}" font-weight="{weight}" '
        f'fill="{color}" text-anchor="{anchor}">{escape(value)}</text>'
    )


def multiline(
    x: float,
    y: float,
    lines: list[str],
    size: int = 14,
    weight: int = 400,
    color: str = "#526878",
    line_height: int = 19,
    anchor: str = "start",
) -> None:
    add(
        f'<text x="{x}" y="{y}" font-size="{size}" font-weight="{weight}" '
        f'fill="{color}" text-anchor="{anchor}">'
    )
    for index, line in enumerate(lines):
        dy = 0 if index == 0 else line_height
        add(f'<tspan x="{x}" dy="{dy}">{escape(line)}</tspan>')
    add("</text>")


def rect(
    x: int,
    y: int,
    width: int,
    height: int,
    fill: str = "#ffffff",
    stroke: str = "#c9d5df",
    radius: int = 14,
    stroke_width: int = 2,
) -> None:
    add(
        f'<rect x="{x}" y="{y}" width="{width}" height="{height}" '
        f'rx="{radius}" fill="{fill}" stroke="{stroke}" stroke-width="{stroke_width}"/>'
    )


def path(d: str, color: str = "#566f82", dashed: bool = False, both: bool = False) -> None:
    dash = ' stroke-dasharray="8 7"' if dashed else ""
    start = ' marker-start="url(#arrowBack)"' if both else ""
    add(
        f'<path d="{d}" fill="none" stroke="{color}" stroke-width="2.5" '
        f'stroke-linecap="round" stroke-linejoin="round"{dash}{start} '
        'marker-end="url(#arrow)"/>'
    )


def label(x: int, y: int, lines: list[str], width: int = 180) -> None:
    height = len(lines) * 18 + 14
    rect(x - width // 2, y - 15, width, height, "#ffffff", "#dce4e9", 7, 1)
    multiline(x, y + 1, lines, 12, 600, "#526878", 17, "middle")


def module(
    x: int,
    y: int,
    width: int,
    height: int,
    heading: str,
    lines: list[str],
    fill: str = "#ffffff",
    stroke: str = "#ccd8e1",
    heading_color: str = "#263c4c",
    desc_color: str = "#536979",
    font_size: int = 14,
) -> None:
    rect(x, y, width, height, fill, stroke, 11, 1.7)
    text(x + 15, y + 24, heading, 15, 700, heading_color)
    multiline(x + 15, y + 45, lines, font_size, 400, desc_color, 17)


def actor(x: int, y: int, title: str, detail: str) -> None:
    rect(x, y, 210, 82, "#f5faf6", "#8eaa98", 13, 2)
    # Simple person icon, deliberately geometric so it remains legible in print.
    add(f'<circle cx="{x + 31}" cy="{y + 28}" r="9" fill="#456c56"/>')
    add(
        f'<path d="M{x + 15} {y + 62}c1-13 8-20 16-20s15 7 16 20" '
        'fill="none" stroke="#456c56" stroke-width="5" stroke-linecap="round"/>'
    )
    text(x + 60, y + 33, title, 16, 700, "#243c2d")
    text(x + 60, y + 56, detail, 12, 400, "#60766a")


def provider(y: int, title: str, detail: str, tag: str | None = None) -> None:
    x, width, height = 1350, 390, 70
    rect(x, y, width, height, "#fffaf0", "#cfb77d", 11, 1.7)
    text(x + 17, y + 25, title, 15, 700, "#493c20")
    if tag:
        tag_width = max(66, 9 * len(tag) + 18)
        rect(x + width - tag_width - 13, y + 10, tag_width, 22, "#f1e8d2", "#e0d2b1", 11, 1)
        text(x + width - tag_width / 2 - 13, y + 25, tag, 10, 700, "#705a2d", "middle")
    text(x + 17, y + 49, detail, 12, 400, "#6c624d")


def make_svg() -> str:
    add(
        f'<svg xmlns="http://www.w3.org/2000/svg" role="img" '
        f'aria-labelledby="title desc" viewBox="0 0 {WIDTH} {HEIGHT}">'
    )
    add(
        "<title id=\"title\">Zentrip System Architecture</title>"
        "<desc id=\"desc\">Users access the Flutter client, which calls the "
        "Spring Boot API. The backend accesses provider data and Supabase PostgreSQL.</desc>"
    )
    add(
        """<defs>
          <marker id="arrow" viewBox="0 0 10 10" refX="9" refY="5"
            markerWidth="8" markerHeight="8" orient="auto-start-reverse">
            <path d="M0 0L10 5L0 10z" fill="#566f82"/>
          </marker>
          <marker id="arrowBack" viewBox="0 0 10 10" refX="1" refY="5"
            markerWidth="8" markerHeight="8" orient="auto">
            <path d="M10 0L0 5L10 10z" fill="#566f82"/>
          </marker>
          <style>
            text { font-family: Arial, Helvetica, sans-serif; }
          </style>
        </defs>"""
    )
    rect(0, 0, WIDTH, HEIGHT, "#f5f7f8", "#f5f7f8", 0, 0)
    text(70, 62, "Zentrip System Architecture", 31, 700, "#1c3446")
    text(
        70,
        88,
        "Current implementation · client, server, provider, and persistent-data relationships",
        15,
        400,
        "#5b7181",
    )
    # Main figure boundary and column headings.
    rect(45, 112, 1710, 810, "#ffffff", "#8fa4b3", 2, 2)
    text(100, 151, "USER ROLES", 12, 700, "#627b6b")
    text(350, 151, "FLUTTER CLIENT · WEB + MOBILE", 12, 700, "#577a99")
    text(760, 151, "SPRING BOOT BACKEND · JAVA 25", 12, 700, "#6b6690")
    text(1350, 151, "EXTERNAL DATA SERVICES", 12, 700, "#9a7b37")

    # Connectors are drawn before nodes so they stay behind the boxes.
    path("M310 246H337V320H360")
    path("M310 382H337V412H360")
    path("M310 518H337V560H360")

    path("M690 475H760", both=True)
    label(725, 428, ["REST / JSON", "bearer token · AI SSE"], 170)

    # Server-to-provider trunk with bidirectional data request/response lines.
    path("M1180 485H1285", both=True)
    path("M1285 192V816", "#7890a1")
    for center_y in [212, 294, 376, 458, 540, 622, 704, 786]:
        path(f"M1285 {center_y}H1350", both=True)
    label(1230, 414, ["provider", "adapters"], 108)

    # Main service sequence, payment simulation, and database persistence.
    path("M970 263V285")
    path("M970 376V398")
    path("M970 500V522")
    path("M1160 450H1210V735H1130")
    path("M1160 558H1200V820H1156", "#547f7d")
    path("M970 766V800", "#547f7d")

    # Actor roles.
    actor(100, 205, "Admin", "global app controls")
    actor(100, 341, "Partner", "owned listings only")
    actor(100, 477, "Customer", "search · book · travel")

    # Flutter UI boundary.
    rect(350, 170, 350, 600, "#f7faff", "#9db4ca", 16, 2)
    module(
        370,
        187,
        310,
        83,
        "App interface",
        [
            "Explore · Nearby/maps · Zen AI · My Trips",
            "Profile and role-specific dashboards",
            "Map tiles load directly from OpenStreetMap",
        ],
        "#edf4fc",
        "#b6c8d8",
    )
    module(
        370,
        291,
        310,
        92,
        "Feature modules",
        ["Flights · Hotels · Places · Cars", "Transfers · Auth · Admin · Partner"],
    )
    module(
        370,
        404,
        310,
        100,
        "Controllers and models",
        ["Feature state and normalized results", "Use the shared API service"],
    )
    module(
        370,
        525,
        310,
        73,
        "ApiService · Dio",
        ["Adds bearer token; calls the /api contract"],
        "#edf4fc",
        "#b6c8d8",
    )
    module(
        350,
        654,
        350,
        94,
        "Device-local state",
        ["Session, favorites, preferences, notifications,", "and part of Zen AI chat history"],
        "#f1f8f2",
        "#a9c4b1",
    )

    # Backend boundary and actual service responsibilities.
    rect(750, 170, 440, 615, "#faf9fd", "#aaa7c5", 16, 2)
    module(
        780,
        190,
        380,
        73,
        "Spring Boot API · /api",
        ["Receives client requests and returns app responses"],
        "#f0eff8",
        "#c4c1d8",
    )
    module(
        780,
        285,
        380,
        91,
        "Authentication and access control",
        ["Validates bearer token; loads role and partner ID", "from server-side user records"],
        "#f4f2fa",
        "#c4c1d8",
    )
    module(
        780,
        398,
        380,
        102,
        "Controllers and feature services",
        ["Auth · Customer · Partner · Admin · AI", "Inventory merge · provider adapters · normalization"],
        "#f4f2fa",
        "#c4c1d8",
    )
    module(
        780,
        522,
        380,
        73,
        "Persistence boundary",
        ["JDBC/JPA · scoped reads/writes · RLS context"],
    )
    # Payment simulator is shown as a distinct internal component.
    module(
        810,
        703,
        320,
        63,
        "Payment simulator",
        ["Mock only · save supported booking after success"],
        "#fff8ed",
        "#ddc49d",
    )

    # Provider panel and nodes.
    rect(1325, 170, 410, 705, "#fffdf8", "#d4c293", 16, 2)
    providers = [
        ("Duffel", "Flight offers only · no airline order", "SEARCH ONLY"),
        ("LiteAPI", "Hotel data and rates · no provider booking", "DATA ONLY"),
        ("OpenTripMap", "Tourist places, suggestions, and details", None),
        ("Geoapify", "Geocoding and airport lookup fallback", None),
        ("SerpAPI", "Nearby and map search", None),
        ("Requesty", "Zen AI completion stream", None),
        ("Frankfurter", "Exchange-rate lookup", None),
        ("Optional / import jobs", "Google Places sync · OurAirports import", "OPTIONAL"),
    ]
    for index, (name, detail, tag) in enumerate(providers[:8]):
        provider(177 + index * 82, name, detail, tag)

    # The shared external-data services respond back to backend adapters.
    # Database is a separate platform service below the backend.
    add('<ellipse cx="970" cy="820" rx="186" ry="19" fill="#edf7f7" stroke="#6a9b99" stroke-width="2"/>')
    add('<path d="M784 820v57c0 11 83 20 186 20s186-9 186-20v-57" fill="#edf7f7" stroke="#6a9b99" stroke-width="2"/>')
    add('<ellipse cx="970" cy="877" rx="186" ry="20" fill="#edf7f7" stroke="#6a9b99" stroke-width="2"/>')
    text(970, 839, "Supabase PostgreSQL", 17, 700, "#285553", "middle")
    text(970, 860, "users · api_tokens · partner inventory · trips · bookings · transfers", 11, 400, "#426c6a", "middle")
    text(970, 879, "offers · places · AI chat · preferences", 11, 400, "#426c6a", "middle")
    # Note under the database cylinder, within the figure.
    text(970, 912, "Backend-only access · row-level security is an additional layer", 11, 600, "#547977", "middle")

    # Keep the legend and scope limitations visible in print.
    rect(70, 925, 1660, 42, "#f7f9fa", "#dbe3e8", 9, 1)
    text(90, 951, "Solid arrows: app/API and persistence flow", 12, 600, "#506879")
    text(505, 951, "Two-headed arrows: provider data requests/responses", 12, 600, "#506879")
    text(1010, 951, "Duffel/LiteAPI are data-only · checkout is simulated", 12, 600, "#8a6b35")
    text(WIDTH / 2, 991, "Figure. Zentrip System Architecture", 18, 600, "#435a69", "middle")
    add("</svg>")
    return "".join(parts)


def make_html(svg: str) -> str:
    return f"""<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Zentrip System Architecture</title>
  <style>
    * {{ box-sizing: border-box; }}
    body {{ margin: 0; padding: 22px; background: #eef2f4; font-family: Arial, Helvetica, sans-serif; }}
    main {{ max-width: 1800px; margin: auto; }}
    .frame {{ overflow: auto; border-radius: 12px; background: #fff; box-shadow: 0 8px 28px #1d354314; }}
    svg {{ display: block; width: 100%; min-width: 1200px; height: auto; }}
    @media (max-width: 760px) {{ body {{ padding: 8px; }} svg {{ min-width: 1400px; }} }}
    @media print {{ body {{ padding: 0; background: #fff; }} main {{ max-width: none; }} .frame {{ box-shadow: none; overflow: visible; }} svg {{ min-width: 0; width: 100%; }} }}
  </style>
</head>
<body><main><div class="frame">{svg}</div></main></body>
</html>"""


def main() -> None:
    if not SOURCE.is_file():
        raise SystemExit(f"Architecture model is missing: {SOURCE}")
    source = SOURCE.read_text(encoding="utf-8")
    required_facts = ["Duffel", "LiteAPI", "Supabase PostgreSQL", "Spring Boot"]
    missing = [fact for fact in required_facts if fact not in source]
    if missing:
        raise SystemExit("Architecture source is missing: " + ", ".join(missing))
    OUTPUT.mkdir(parents=True, exist_ok=True)
    svg = make_svg()
    SVG_PATH.write_text(svg, encoding="utf-8")
    HTML_PATH.write_text(make_html(svg), encoding="utf-8")
    print(f"Rendered {SVG_PATH.relative_to(ROOT)}")
    print(f"Rendered {HTML_PATH.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
