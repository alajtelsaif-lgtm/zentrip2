#!/usr/bin/env python3
"""Build the current Zentrip activity diagram, HTML viewer, and Word document.

The diagram is intentionally generated from the flow data below so its SVG,
HTML, and DOCX versions cannot drift apart.
"""

from __future__ import annotations

import html
import shutil
import subprocess
import zipfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "generated-artifacts"
SVG_PATH = OUT / "zentrip-activity-diagram.svg"
HTML_PATH = OUT / "zentrip-activity-diagram.html"
DOCX_PATH = OUT / "ZenTrip-Activity-Diagram-Integrated.docx"
PNG_PATH = OUT / "zentrip-activity-diagram.png"

WIDTH = 3500
HEIGHT = 2380

COLORS = {
    "ink": "#263a33",
    "muted": "#62756d",
    "lane-stroke": "#d9e4dd",
    "lane-entry": "#eef4ef",
    "lane-flight": "#f3f1f9",
    "lane-hotel": "#f3f1f9",
    "lane-places": "#eef4f9",
    "lane-trips": "#eef4f9",
    "user-fill": "#f9fcf9",
    "user-stroke": "#8eac99",
    "system-fill": "#fbfaff",
    "system-stroke": "#a89cbe",
    "api-fill": "#f9fcff",
    "api-stroke": "#91acc0",
    "success-fill": "#edf5fa",
    "success-stroke": "#668ba5",
    "error-fill": "#fff9f6",
    "error-stroke": "#d49a88",
    "line": "#839d8e",
    "api-line": "#456984",
    "error-line": "#c17d68",
    "start-fill": "#d9eee3",
    "start-stroke": "#75a48b",
    "white": "#ffffff",
}


def node(
    ident: str,
    x: int,
    y: int,
    w: int,
    h: int,
    label: str,
    kind: str = "system",
    shape: str = "box",
) -> dict:
    return {
        "id": ident,
        "x": x,
        "y": y,
        "w": w,
        "h": h,
        "label": label.split("\n"),
        "kind": kind,
        "shape": shape,
    }


NODES = [
    node("start", 90, 270, 68, 68, "Start", "start", "start"),
    node("restore", 330, 270, 220, 86, "Restore saved session\nor continue onboarding", "user"),
    node("session", 650, 270, 160, 122, "Session\navailable?", "decision", "diamond"),
    node("signin", 650, 420, 230, 82, "Sign in or\ncreate account", "user"),
    node("role", 990, 270, 190, 132, "Verified\nrole?", "decision", "diamond"),
    node("customer-app", 1340, 270, 300, 92, "Customer AppShell\nExplore · Nearby · Zen AI", "user"),
    node("admin-dashboard", 1280, 445, 260, 82, "Admin dashboard\nstaff-only access", "system"),
    node("partner-dashboard", 1630, 445, 260, 82, "Partner dashboard\nown-partner scope", "system"),
    node("module-select", 2130, 270, 440, 92, "Choose area\nFlights · Hotels · Places · Zen AI · My Trips", "user"),
    node("logout", 2700, 270, 84, 84, "Log out", "end", "end"),

    # Flights: three provider branches visibly converge before normalization.
    node("flight-input", 470, 850, 240, 106, "Search route, dates /\nflexible months,\npassengers and cabin", "user"),
    node("flight-endpoint", 760, 850, 230, 106, "GET /flights/search\nor /flights/search/flexible", "system"),
    node("flight-airports", 1040, 770, 190, 62, "Airport directory", "api"),
    node("flight-partner", 1040, 850, 190, 62, "Partner offers", "api"),
    node("flight-duffel", 1040, 930, 190, 62, "Duffel offers", "api"),
    node("flight-merge", 1290, 850, 88, 88, "M", "system", "merge"),
    node("flight-normalize", 1510, 850, 230, 106, "Merge / normalize;\nwarn, sort and filter", "system"),
    node("flight-available", 1780, 850, 170, 132, "Any flight\noffers?", "decision", "diamond"),
    node("flight-review", 2030, 850, 220, 106, "Review results\nand select a flight", "user"),
    node("flight-details", 2300, 850, 250, 106, "Fare, passenger details,\nseats and extras", "user"),
    node("flight-checkout", 2590, 850, 220, 106, "Zentrip simulated\npayment", "system"),
    node("flight-payment", 2860, 850, 170, 132, "Payment\nsuccessful?", "decision", "diamond"),
    node("flight-save", 3160, 850, 260, 106, "Save trip and show\nconfirmation; no ticket", "success"),
    node("flight-provider-warning", 1500, 1010, 270, 76, "Provider issue:\npartial or empty results", "error"),
    node("flight-empty", 1780, 1010, 260, 76, "No offers: show empty\nstate and retry", "error"),
    node("flight-payment-failed", 2860, 1010, 260, 76, "Failed attempt only;\nrelease seat hold", "error"),
    node("flight-cancelled", 3260, 1010, 84, 84, "Cancelled", "end", "end"),

    # Hotels use partner inventory and LiteAPI data, with the same simulated
    # payment boundary and no supplier reservation.
    node("hotel-input", 470, 1270, 240, 106, "Choose destination,\nstay dates, rooms\nand guests", "user"),
    node("hotel-endpoint", 760, 1270, 230, 106, "GET /hotels/search", "system"),
    node("hotel-partner", 1040, 1190, 190, 62, "Partner listings", "api"),
    node("hotel-liteapi", 1040, 1270, 190, 62, "LiteAPI hotel data", "api"),
    node("hotel-merge", 1290, 1270, 88, 88, "M", "system", "merge"),
    node("hotel-normalize", 1510, 1270, 230, 106, "Merge / normalize;\nshow provider warnings", "system"),
    node("hotel-available", 1780, 1270, 170, 132, "Any stays\navailable?", "decision", "diamond"),
    node("hotel-review", 2030, 1270, 220, 106, "Review hotel results\nand details", "user"),
    node("hotel-room", 2300, 1270, 250, 106, "Check selected stay /\nroom availability", "system"),
    node("hotel-checkout", 2590, 1270, 220, 106, "Zentrip simulated\npayment", "system"),
    node("hotel-payment", 2860, 1270, 170, 132, "Payment\nsuccessful?", "decision", "diamond"),
    node("hotel-save", 3160, 1270, 260, 106, "POST /bookings and\nshow confirmation", "success"),
    node("hotel-provider-warning", 1500, 1450, 270, 76, "Provider issue:\npartial or empty results", "error"),
    node("hotel-empty", 1780, 1450, 260, 76, "No stays: show empty\nstate and retry", "error"),
    node("hotel-payment-failed", 2860, 1450, 260, 76, "Failed attempt;\nno booking created", "error"),
    node("hotel-cancelled", 3260, 1450, 84, 84, "Cancelled", "end", "end"),

    # Places and AI are distinct, non-booking paths from the AppShell.
    node("places-input", 470, 1645, 240, 88, "Search nearby or\nby destination", "user"),
    node("places-coordinates", 770, 1645, 150, 116, "Coordinates\nknown?", "decision", "diamond"),
    node("places-geocode", 770, 1760, 230, 76, "Geoapify geocoding\nonly if needed", "api"),
    node("places-opentripmap", 1100, 1645, 250, 88, "OpenTripMap\nplaces search", "api"),
    node("places-results", 1450, 1645, 270, 88, "View place details;\nvisit counter only", "user"),
    node("places-return", 1810, 1645, 230, 88, "Return to AppShell", "user"),
    node("places-error", 1450, 1760, 270, 76, "Empty / error state;\nretry search", "error"),
    node("ai-input", 470, 1830, 240, 72, "Enter a Zen AI\nchat prompt", "user"),
    node("ai-endpoint", 850, 1830, 280, 72, "POST /api/ai/chat\nRequesty provider", "api"),
    node("ai-response", 1230, 1830, 280, 72, "Read streamed reply;\nsave chat locally", "system"),
    node("ai-return", 1600, 1830, 230, 72, "Return to AppShell", "user"),

    # My Trips reads the current user's saved trip, booking, and transfer
    # records. Flight and hotel success connect into this shared persistence.
    node("trips-open", 470, 2110, 240, 92, "Open My Trips", "user"),
    node("trips-fetch", 800, 2110, 270, 92, "GET /trips,\n/bookings and /transfers", "system"),
    node("trips-db", 1200, 2110, 300, 110, "Supabase PostgreSQL\ncurrent-user records", "success"),
    node("trips-display", 1570, 2110, 260, 92, "Display trips, bookings\nand transfers", "user"),
    node("trips-cancel-choice", 1900, 2110, 170, 132, "Cancel a\nbooking?", "decision", "diamond"),
    node("trips-return", 2240, 2060, 240, 82, "Return to AppShell", "user"),
    node("trips-cancel-status", 2240, 2220, 280, 72, "Show cancellation\nstatus; provider terms vary", "system"),
    node("trips-cancelled", 2660, 2220, 84, 84, "Cancelled", "end", "end"),
    node("trips-complete", 3070, 2070, 84, 84, "Trip complete", "end", "end"),
]


def edge(
    ident: str,
    points: list[tuple[int, int]],
    kind: str = "main",
    label: str | None = None,
    label_at: tuple[int, int] | None = None,
) -> dict:
    for (x1, y1), (x2, y2) in zip(points, points[1:]):
        if x1 != x2 and y1 != y2:
            raise ValueError(f"Edge {ident} is not orthogonal: {(x1, y1)} -> {(x2, y2)}")
    return {
        "id": ident,
        "points": points,
        "kind": kind,
        "label": label,
        "label_at": label_at,
    }


EDGES = [
    edge("start-restore", [(124, 270), (220, 270)]),
    edge("restore-session", [(440, 270), (570, 270)]),
    edge("session-yes-role", [(730, 270), (895, 270)], label="Yes · continue", label_at=(805, 252)),
    edge("session-no-signin", [(650, 331), (650, 378)], label="No", label_at=(672, 360)),
    edge("signin-role", [(765, 420), (830, 420), (830, 270), (895, 270)], label="Signed in", label_at=(845, 395)),
    edge("role-customer", [(1085, 270), (1190, 270)], label="Customer", label_at=(1135, 250)),
    edge("role-admin", [(990, 336), (990, 445), (1150, 445)], label="Admin", label_at=(1010, 395)),
    edge("role-partner", [(1080, 270), (1120, 270), (1120, 485), (1500, 485)], label="Partner", label_at=(1150, 465)),
    edge("app-modules", [(1490, 270), (1910, 270)]),
    edge("modules-logout", [(2350, 270), (2658, 270)], label="Sign out", label_at=(2500, 250)),

    # Shared AppShell module dispatcher: each path is orthogonal and reaches
    # its own feature entry without relying on an implicit default city.
    edge("dispatch-flight", [(1970, 316), (1970, 520), (200, 520), (200, 850), (350, 850)], "api", "Flights", (390, 505)),
    edge("dispatch-hotel", [(2030, 316), (2030, 550), (240, 550), (240, 1270), (350, 1270)], "api", "Hotels", (390, 537)),
    edge("dispatch-places", [(2090, 316), (2090, 580), (280, 580), (280, 1645), (350, 1645)], "api", "Places", (390, 567)),
    edge("dispatch-ai", [(2150, 316), (2150, 610), (320, 610), (320, 1830), (350, 1830)], "api", "Zen AI", (390, 597)),
    edge("dispatch-trips", [(2210, 316), (2210, 640), (360, 640), (360, 2110), (350, 2110)], "api", "My Trips", (390, 627)),

    edge("flight-input-api", [(590, 850), (645, 850)]),
    edge("flight-api-airports", [(875, 850), (920, 850), (920, 770), (945, 770)], "api"),
    edge("flight-api-partner", [(875, 850), (945, 850)], "api"),
    edge("flight-api-duffel", [(875, 850), (920, 850), (920, 930), (945, 930)], "api"),
    edge("flight-airports-merge", [(1135, 770), (1180, 770), (1180, 850), (1246, 850)], "api"),
    edge("flight-partner-merge", [(1135, 850), (1246, 850)], "api"),
    edge("flight-duffel-merge", [(1135, 930), (1180, 930), (1180, 850), (1246, 850)], "api"),
    edge("flight-merge-normalize", [(1334, 850), (1395, 850)]),
    edge("flight-normalize-available", [(1625, 850), (1695, 850)]),
    edge("flight-available-review", [(1865, 850), (1920, 850)], "main", "Yes", (1890, 830)),
    edge("flight-available-empty", [(1780, 916), (1780, 972)], "error", "No", (1800, 950)),
    edge("flight-empty-retry", [(1780, 1048), (1780, 1080), (330, 1080), (330, 850), (350, 850)], "error", "Retry", (1080, 1065)),
    edge("flight-merge-warning", [(1290, 894), (1290, 1010), (1365, 1010)], "error", "Provider failure", (1305, 962)),
    edge("flight-warning-normalize", [(1500, 972), (1500, 903), (1510, 903)], "error", "Continue with available data", (1515, 940)),
    edge("flight-review-details", [(2140, 850), (2175, 850)]),
    edge("flight-details-checkout", [(2425, 850), (2480, 850)]),
    edge("flight-checkout-payment", [(2700, 850), (2775, 850)]),
    edge("flight-payment-save", [(2945, 850), (3030, 850)], "main", "Yes", (2985, 830)),
    edge("flight-payment-fail", [(2860, 916), (2860, 972)], "error", "No", (2880, 950)),
    edge("flight-fail-retry", [(2730, 1010), (2590, 1010), (2590, 903)], "error", "Retry", (2655, 990)),
    edge("flight-fail-cancel", [(2990, 1010), (3218, 1010)], "error", "Cancel", (3090, 990)),
    edge("flight-save-db", [(3290, 850), (3400, 850), (3400, 1910), (1210, 1910), (1210, 2055)], "api", "Persist successful flight trip", (2180, 1895)),

    edge("hotel-input-api", [(590, 1270), (645, 1270)]),
    edge("hotel-api-partner", [(875, 1270), (920, 1270), (920, 1190), (945, 1190)], "api"),
    edge("hotel-api-liteapi", [(875, 1270), (945, 1270)], "api"),
    edge("hotel-partner-merge", [(1135, 1190), (1180, 1190), (1180, 1270), (1246, 1270)], "api"),
    edge("hotel-liteapi-merge", [(1135, 1270), (1246, 1270)], "api"),
    edge("hotel-merge-normalize", [(1334, 1270), (1395, 1270)]),
    edge("hotel-normalize-available", [(1625, 1270), (1695, 1270)]),
    edge("hotel-available-review", [(1865, 1270), (1920, 1270)], "main", "Yes", (1890, 1250)),
    edge("hotel-available-empty", [(1780, 1336), (1780, 1412)], "error", "No", (1800, 1380)),
    edge("hotel-empty-retry", [(1780, 1488), (1780, 1520), (330, 1520), (330, 1270), (350, 1270)], "error", "Retry", (1080, 1505)),
    edge("hotel-merge-warning", [(1290, 1314), (1290, 1450), (1365, 1450)], "error", "Provider failure", (1305, 1395)),
    edge("hotel-warning-normalize", [(1500, 1412), (1500, 1323), (1510, 1323)], "error", "Continue with available data", (1515, 1370)),
    edge("hotel-review-room", [(2140, 1270), (2175, 1270)]),
    edge("hotel-room-checkout", [(2425, 1270), (2480, 1270)]),
    edge("hotel-checkout-payment", [(2700, 1270), (2775, 1270)]),
    edge("hotel-payment-save", [(2945, 1270), (3030, 1270)], "main", "Yes", (2985, 1250)),
    edge("hotel-payment-fail", [(2860, 1336), (2860, 1412)], "error", "No", (2880, 1380)),
    edge("hotel-fail-retry", [(2730, 1450), (2590, 1450), (2590, 1323)], "error", "Retry", (2655, 1430)),
    edge("hotel-fail-cancel", [(2990, 1450), (3218, 1450)], "error", "Cancel", (3090, 1430)),
    edge("hotel-save-db", [(3290, 1270), (3450, 1270), (3450, 1930), (1390, 1930), (1390, 2055)], "api", "Persist successful hotel booking", (2180, 1915)),

    edge("places-search-coordinates", [(590, 1645), (695, 1645)]),
    edge("places-known-otm", [(845, 1645), (975, 1645)], "main", "Yes", (900, 1626)),
    edge("places-unknown-geocode", [(770, 1703), (770, 1722)], "api", "No", (790, 1715)),
    edge("places-geocode-otm", [(885, 1760), (950, 1760), (950, 1645), (975, 1645)], "api"),
    edge("places-otm-results", [(1225, 1645), (1315, 1645)], "api"),
    edge("places-results-return", [(1585, 1645), (1695, 1645)]),
    edge("places-otm-error", [(1100, 1689), (1100, 1760), (1315, 1760)], "error", "Provider failure", (1115, 1735)),
    edge("places-error-retry", [(1315, 1760), (1315, 1850), (330, 1850), (330, 1645), (350, 1645)], "error", "Retry", (875, 1838)),
    edge("ai-prompt-api", [(590, 1830), (710, 1830)], "api"),
    edge("ai-api-reply", [(990, 1830), (1090, 1830)], "api"),
    edge("ai-reply-return", [(1370, 1830), (1485, 1830)]),

    edge("trips-open-fetch", [(590, 2110), (665, 2110)]),
    edge("trips-fetch-db", [(935, 2110), (1050, 2110)], "api"),
    edge("trips-db-display", [(1350, 2110), (1440, 2110)]),
    edge("trips-display-cancel", [(1700, 2110), (1815, 2110)]),
    edge("trips-no-cancel-return", [(1985, 2110), (2060, 2110), (2060, 2060), (2120, 2060)], "main", "No", (2035, 2093)),
    edge("trips-return-complete", [(2360, 2060), (2490, 2060), (2490, 2070), (3028, 2070)], "main", "Travel period ends", (2740, 2045)),
    edge("trips-yes-cancel-status", [(1900, 2176), (1900, 2220), (2100, 2220)], "error", "Yes", (1920, 2200)),
    edge("trips-status-end", [(2380, 2220), (2618, 2220)], "error"),
]


def render_node(item: dict) -> str:
    x, y, w, h = item["x"], item["y"], item["w"], item["h"]
    kind, shape = item["kind"], item["shape"]
    fill = COLORS["user-fill"]
    stroke = COLORS["user-stroke"]
    if kind in {"system", "decision"}:
        fill, stroke = COLORS["system-fill"], COLORS["system-stroke"]
    elif kind == "api":
        fill, stroke = COLORS["api-fill"], COLORS["api-stroke"]
    elif kind == "success":
        fill, stroke = COLORS["success-fill"], COLORS["success-stroke"]
    elif kind == "error":
        fill, stroke = COLORS["error-fill"], COLORS["error-stroke"]
    elif kind == "start":
        fill, stroke = COLORS["start-fill"], COLORS["start-stroke"]
    elif kind == "end":
        fill, stroke = COLORS["white"], COLORS["start-stroke"]

    if shape == "start":
        geometry = f'<circle class="node-shape" cx="{x}" cy="{y}" r="{w / 2}" fill="{COLORS["start-fill"]}" stroke="{stroke}"/>'
        geometry += f'<circle cx="{x}" cy="{y}" r="11" fill="{stroke}"/>'
    elif shape == "end":
        geometry = f'<circle class="node-shape" cx="{x}" cy="{y}" r="{w / 2}" fill="{fill}" stroke="{stroke}"/>'
        geometry += f'<circle cx="{x}" cy="{y}" r="{w / 2 - 8}" fill="none" stroke="{stroke}" stroke-width="2"/>'
    elif shape == "diamond":
        points = f"{x},{y - h / 2} {x + w / 2},{y} {x},{y + h / 2} {x - w / 2},{y}"
        geometry = f'<polygon class="node-shape" points="{points}" fill="{fill}" stroke="{stroke}"/>'
    elif shape == "merge":
        geometry = f'<circle class="node-shape" cx="{x}" cy="{y}" r="{w / 2}" fill="{COLORS["white"]}" stroke="{stroke}"/>'
    else:
        geometry = (
            f'<rect class="node-shape" x="{x - w / 2}" y="{y - h / 2}" '
            f'width="{w}" height="{h}" rx="15" fill="{fill}" stroke="{stroke}"/>'
        )

    label = item["label"]
    size = 19 if shape in {"diamond", "merge"} else 21
    line_height = 24
    if shape in {"start", "end"}:
        label_y = y + w / 2 + 25
        lines = "".join(
            f'<text x="{x}" y="{label_y + index * line_height}" text-anchor="middle" '
            f'font-size="17" font-weight="700" fill="{COLORS["ink"]}">{html.escape(line)}</text>'
            for index, line in enumerate(label)
        )
    else:
        start_y = y - (len(label) - 1) * line_height / 2 + 6
        lines = "".join(
            f'<text x="{x}" y="{start_y + index * line_height}" text-anchor="middle" '
            f'font-size="{size}" font-weight="650" fill="{COLORS["ink"]}">{html.escape(line)}</text>'
            for index, line in enumerate(label)
        )
    aria = html.escape(f'{item["id"]}: {" ".join(label)}')
    return (
        f'<g id="{item["id"]}" class="node {kind}" role="img" aria-label="{aria}">'
        f'<title>{html.escape(" ".join(label))}</title>{geometry}{lines}</g>'
    )


def render_edge(item: dict) -> str:
    color = COLORS["line"]
    dash = ""
    if item["kind"] == "api":
        color = COLORS["api-line"]
    elif item["kind"] == "error":
        color, dash = COLORS["error-line"], ' stroke-dasharray="9 7"'
    d = "M " + " L ".join(f"{x} {y}" for x, y in item["points"])
    path = (
        f'<path id="{item["id"]}" d="{d}" fill="none" stroke="{color}" '
        f'stroke-width="3" stroke-linejoin="round" stroke-linecap="square" '
        f'marker-end="url(#arrow-{item["kind"]})"{dash}/>'
    )
    label = ""
    if item["label"] and item["label_at"]:
        lx, ly = item["label_at"]
        label = (
            f'<text x="{lx}" y="{ly}" class="edge-label" text-anchor="middle" '
            f'font-size="17" font-weight="700" fill="{color}">{html.escape(item["label"])}</text>'
        )
    return path + label


def build_svg() -> str:
    lanes = [
        (30, 90, 3440, 600, COLORS["lane-entry"], "ENTRY, VERIFIED ROLE ROUTING & APP SHELL"),
        (30, 710, 3440, 410, COLORS["lane-flight"], "FLIGHTS · PROVIDER SEARCH → SIMULATED CHECKOUT"),
        (30, 1130, 3440, 410, COLORS["lane-hotel"], "HOTELS · PROVIDER SEARCH → SIMULATED BOOKING"),
        (30, 1550, 3440, 340, COLORS["lane-places"], "PLACES & ZEN AI · NON-BOOKING FLOWS"),
        (30, 1960, 3440, 360, COLORS["lane-trips"], "MY TRIPS & SHARED PERSISTENCE"),
    ]
    lane_xml = "".join(
        f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="24" fill="{fill}" stroke="{COLORS["lane-stroke"]}" stroke-width="2"/>'
        f'<text x="{x + 26}" y="{y + 34}" class="lane-title">{html.escape(title)}</text>'
        for x, y, w, h, fill, title in lanes
    )
    edge_xml = "".join(render_edge(item) for item in EDGES)
    node_xml = "".join(render_node(item) for item in NODES)
    footer = (
        '<text x="70" y="2350" class="footer">'
        'Duffel/LiteAPI supply search data only here. Zentrip checkout is simulated; no supplier ticket, hotel reservation, '
        'or card charge is created. Payment attempts store status, not card data.'
        '</text>'
    )
    return f'''<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg" width="{WIDTH}" height="{HEIGHT}" viewBox="0 0 {WIDTH} {HEIGHT}" role="img" aria-labelledby="title desc">
<title id="title">Zentrip current end-to-end activity diagram</title>
<desc id="desc">Connected Zentrip entry, role routing, app navigation, flight and hotel searches, simulated checkout, places and AI paths, and My Trips persistence. Failure branches are dashed and orthogonal.</desc>
<defs>
  <marker id="arrow-main" viewBox="0 0 10 10" refX="8.5" refY="5" markerWidth="9" markerHeight="9" orient="auto"><path d="M0 0 L10 5 L0 10 Z" fill="{COLORS["line"]}"/></marker>
  <marker id="arrow-api" viewBox="0 0 10 10" refX="8.5" refY="5" markerWidth="9" markerHeight="9" orient="auto"><path d="M0 0 L10 5 L0 10 Z" fill="{COLORS["api-line"]}"/></marker>
  <marker id="arrow-error" viewBox="0 0 10 10" refX="8.5" refY="5" markerWidth="9" markerHeight="9" orient="auto"><path d="M0 0 L10 5 L0 10 Z" fill="{COLORS["error-line"]}"/></marker>
  <style>
    text{{font-family:Arial,Helvetica,sans-serif}}
    .heading{{font-size:33px;font-weight:700;fill:{COLORS["ink"]}}}
    .subtitle{{font-size:19px;fill:{COLORS["muted"]}}}
    .lane-title{{font-size:20px;font-weight:700;letter-spacing:.04em;fill:#456258}}
    .edge-label{{paint-order:stroke;stroke:#fff;stroke-width:7px;stroke-linejoin:round}}
    .footer{{font-size:17px;fill:{COLORS["muted"]}}}
    .node-shape{{stroke-width:2.6}}
  </style>
</defs>
<rect width="100%" height="100%" fill="#ffffff"/>
<text x="55" y="44" class="heading">ZenTrip · Current App Activity</text>
<text x="55" y="72" class="subtitle">Connected user paths, provider boundaries, failure recovery, simulated checkout, and saved trips</text>
{lane_xml}
<g id="edges">{edge_xml}</g>
<g id="nodes">{node_xml}</g>
{footer}
</svg>
'''


def build_html(svg: str) -> str:
    return f'''<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>ZenTrip · Current Activity Diagram</title>
<style>
  :root{{font-family:Arial,Helvetica,sans-serif;color:#263a33;background:#f5f8f5}}
  *{{box-sizing:border-box}}body{{margin:0;padding:20px}}
  header{{max-width:1600px;margin:0 auto 14px;display:flex;align-items:center;justify-content:space-between;gap:12px;flex-wrap:wrap}}
  h1{{font-size:clamp(20px,3vw,30px);margin:0}}p{{margin:6px 0;color:#62756d}}
  .controls{{display:flex;gap:8px;align-items:center}}
  button,a{{font:inherit;border:1px solid #c9d8d0;border-radius:9px;background:#fff;color:#263a33;padding:8px 12px;text-decoration:none;cursor:pointer}}
  button:hover,a:hover{{background:#eef4ef}}
  .frame{{height:calc(100vh - 140px);min-height:420px;max-width:1600px;margin:auto;border:1px solid #d9e4dd;border-radius:14px;background:#fff;overflow:hidden;position:relative;touch-action:none;cursor:grab}}
  .frame.dragging{{cursor:grabbing}}
  #diagram{{position:absolute;left:0;top:0;width:{WIDTH}px;height:{HEIGHT}px;transform-origin:0 0;max-width:none;user-select:none;pointer-events:none}}
  .notes{{max-width:1600px;margin:12px auto;font-size:13px}}
</style>
</head>
<body>
<header><div><h1>ZenTrip · Current Activity Diagram</h1><p>Real app flow with cross-phase links, explicit decisions, and orthogonal recovery routes.</p></div>
<nav class="controls" aria-label="Diagram controls"><button id="out" type="button">−</button><button id="in" type="button">+</button><button id="fit" type="button">Fit</button><button id="reset" type="button">Reset</button><a href="zentrip-activity-diagram.svg" download>Download SVG</a></nav></header>
<main class="frame" id="frame" aria-label="Interactive diagram pan and zoom viewport"><div id="diagram">{svg}</div></main>
<p class="notes">Hover over a node for its label; use the mouse wheel, buttons, or drag to inspect the full flow. In Word, the SVG is embedded as a vector picture object; supported Word versions can convert it to editable shapes.</p>
<script>
(() => {{
 const frame=document.getElementById('frame'), image=document.getElementById('diagram');
 let scale=1, x=0, y=0, down=false, sx=0, sy=0;
 function apply(){{image.style.transform=`translate(${{x}}px,${{y}}px) scale(${{scale}})`}}
 function fit(){{const r=frame.getBoundingClientRect();scale=Math.min((r.width-24)/{WIDTH},(r.height-24)/{HEIGHT});x=(r.width-{WIDTH}*scale)/2;y=(r.height-{HEIGHT}*scale)/2;apply()}}
 document.getElementById('in').onclick=()=>{{scale=Math.min(2.5,scale*1.2);apply()}};
 document.getElementById('out').onclick=()=>{{scale=Math.max(.25,scale/1.2);apply()}};
 document.getElementById('fit').onclick=fit;
 document.getElementById('reset').onclick=()=>{{scale=1;x=0;y=0;apply()}};
 frame.addEventListener('wheel',e=>{{e.preventDefault();scale=Math.max(.25,Math.min(2.5,scale*(e.deltaY<0?1.12:1/1.12)));apply()}},{{passive:false}});
 frame.addEventListener('pointerdown',e=>{{down=true;sx=e.clientX-x;sy=e.clientY-y;frame.classList.add('dragging');frame.setPointerCapture(e.pointerId)}});
 frame.addEventListener('pointermove',e=>{{if(!down)return;x=e.clientX-sx;y=e.clientY-sy;apply()}});
 const stop=()=>{{down=false;frame.classList.remove('dragging')}};
 frame.addEventListener('pointerup',stop);frame.addEventListener('pointercancel',stop);
 window.addEventListener('resize',fit);fit();
}})();
</script>
</body></html>'''


def word_run(text: str, size: int = 24, bold: bool = False, color: str | None = None) -> str:
    props = f'<w:rPr><w:sz w:val="{size}"/><w:szCs w:val="{size}"/>'
    if bold:
        props += "<w:b/>"
    if color:
        props += f'<w:color w:val="{color}"/>'
    props += "</w:rPr>"
    return f'<w:r>{props}<w:t xml:space="preserve">{html.escape(text)}</w:t></w:r>'


def word_paragraph(text: str, style: str | None = None, size: int = 22, bold: bool = False) -> str:
    ppr = f'<w:pPr><w:pStyle w:val="{style}"/></w:pPr>' if style else ""
    return f"<w:p>{ppr}{word_run(text, size=size, bold=bold)}</w:p>"


def build_docx(png: bytes | None, svg: bytes) -> None:
    width_in = 14.7
    height_in = width_in * HEIGHT / WIDTH
    cx = round(width_in * 914400)
    cy = round(height_in * 914400)
    if png:
        blip = '''<a:blip r:embed="rId2" cstate="print"><a:extLst>
          <a:ext uri="{96DAC541-7B7A-43D3-8B79-37D633B846F1}">
            <asvg:svgBlip xmlns:asvg="http://schemas.microsoft.com/office/drawing/2016/SVG/main" r:embed="rId3"/>
          </a:ext>
        </a:extLst></a:blip>'''
    else:
        blip = '''<a:blip r:embed="rId2"><a:extLst>
          <a:ext uri="{96DAC541-7B7A-43D3-8B79-37D633B846F1}">
            <asvg:svgBlip xmlns:asvg="http://schemas.microsoft.com/office/drawing/2016/SVG/main" r:embed="rId2"/>
          </a:ext>
        </a:extLst></a:blip>'''

    notes = [
        ("Entry and access", "A saved session is restored when available; otherwise the user signs in or creates an account. A verified role routes customers to the AppShell and staff to their own admin or partner dashboard."),
        ("Flights", "The app searches the airport directory, partner offers, and Duffel offers, then merges and normalizes results. Search is live data; checkout is simulated. A successful flow saves a trip record without issuing a supplier ticket. Failed payment creates no trip and releases the seat hold."),
        ("Hotels", "Partner listings and LiteAPI hotel data are combined for search. LiteAPI is data-only in this flow. Zentrip simulates payment and booking; successful checkout creates a Zentrip booking, not a supplier reservation."),
        ("Places and Zen AI", "Geoapify is used for geocoding when needed and OpenTripMap supplies places. Place viewing only updates the visit counter. Zen AI is a chat request to Requesty; the reply is streamed and chat history is saved locally, not as a booked itinerary."),
        ("My Trips and storage", "My Trips fetches the signed-in user's trips, bookings, and transfers from Supabase. Cancellation is shown as an in-app status path; provider cancellation and refund terms can vary. Trip completion is a lifecycle end state after the travel dates, not a separate booking action. Payment attempts store outcome/status only, never card details."),
    ]
    note_paragraphs = "".join(
        word_paragraph(title, "Heading2", 26, True) + word_paragraph(body, size=21)
        for title, body in notes
    )

    document = f'''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"
 xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"
 xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing"
 xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main"
 xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture"
 xmlns:mc="http://schemas.openxmlformats.org/markup-compatibility/2006">
<w:body>
{word_paragraph("ZenTrip · Current Activity Diagram", "Title", 34, True)}
<w:p><w:pPr><w:jc w:val="center"/><w:spacing w:after="120"/></w:pPr>{word_run("Connected workflow based on the current app: role routing, provider search, simulated checkout, and persistence.", 20, False, "62756D")}</w:p>
<w:p><w:pPr><w:jc w:val="center"/></w:pPr><w:r><w:drawing><wp:inline distT="0" distB="0" distL="0" distR="0">
 <wp:extent cx="{cx}" cy="{cy}"/><wp:effectExtent t="0" r="0" b="0" l="0"/>
 <wp:docPr id="1" name="ZenTrip integrated activity diagram" descr="Vector activity diagram with orthogonal connectors, role branches, provider merges, checkout decisions, error recovery, and shared persistence." title="ZenTrip current app flow"/>
 <wp:cNvGraphicFramePr><a:graphicFrameLocks noChangeAspect="1"/></wp:cNvGraphicFramePr>
 <a:graphic><a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/picture">
  <pic:pic><pic:nvPicPr><pic:cNvPr id="0" name="ZenTrip flow diagram" descr="Editable SVG vector object; convert to shapes in supported Word versions."/><pic:cNvPicPr><a:picLocks noChangeAspect="1"/></pic:cNvPicPr></pic:nvPicPr>
  <pic:blipFill>{blip}<a:srcRect/><a:stretch><a:fillRect/></a:stretch></pic:blipFill>
  <pic:spPr bwMode="auto"><a:xfrm><a:off x="0" y="0"/><a:ext cx="{cx}" cy="{cy}"/></a:xfrm><a:prstGeom prst="rect"><a:avLst/></a:prstGeom></pic:spPr>
  </pic:pic>
 </a:graphicData></a:graphic>
</wp:inline></w:drawing></w:r></w:p>
<w:p><w:r><w:br w:type="page"/></w:r></w:p>
{word_paragraph("Editable flow notes", "Heading1", 30, True)}
{word_paragraph("The diagram is an embedded SVG vector picture object. In Word versions that support SVG shape conversion, use Convert to Shape to edit individual nodes.", size=20)}
{note_paragraphs}
<w:sectPr><w:pgSz w:w="23811" w:h="16838" w:orient="landscape"/><w:pgMar w:top="500" w:right="500" w:bottom="500" w:left="500" w:header="250" w:footer="250" w:gutter="0"/></w:sectPr>
</w:body></w:document>'''

    content_types = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
 <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
 <Default Extension="xml" ContentType="application/xml"/>
 <Default Extension="svg" ContentType="image/svg+xml"/>
 <Default Extension="png" ContentType="image/png"/>
 <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
 <Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>
 <Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/>
 <Override PartName="/docProps/app.xml" ContentType="application/vnd.openxmlformats-officedocument.extended-properties+xml"/>
</Types>'''
    root_rels = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
 <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
 <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="docProps/core.xml"/>
 <Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/extended-properties" Target="docProps/app.xml"/>
</Relationships>'''
    document_rels_with_png = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
 <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" Target="media/diagram.png"/>
 <Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" Target="media/diagram.svg"/>
</Relationships>'''
    document_rels_svg_only = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
 <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" Target="media/diagram.svg"/>
</Relationships>'''
    styles = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
 <w:style w:type="paragraph" w:default="1" w:styleId="Normal"><w:name w:val="Normal"/><w:rPr><w:rFonts w:ascii="Arial" w:hAnsi="Arial"/><w:sz w:val="22"/></w:rPr></w:style>
 <w:style w:type="paragraph" w:styleId="Title"><w:name w:val="Title"/><w:basedOn w:val="Normal"/><w:pPr><w:jc w:val="center"/><w:spacing w:after="90"/></w:pPr><w:rPr><w:rFonts w:ascii="Arial" w:hAnsi="Arial"/><w:color w:val="263A33"/><w:b/><w:sz w:val="34"/></w:rPr></w:style>
 <w:style w:type="paragraph" w:styleId="Heading1"><w:name w:val="heading 1"/><w:basedOn w:val="Normal"/><w:pPr><w:spacing w:before="240" w:after="120"/></w:pPr><w:rPr><w:rFonts w:ascii="Arial" w:hAnsi="Arial"/><w:color w:val="456258"/><w:b/><w:sz w:val="30"/></w:rPr></w:style>
 <w:style w:type="paragraph" w:styleId="Heading2"><w:name w:val="heading 2"/><w:basedOn w:val="Normal"/><w:pPr><w:spacing w:before="180" w:after="60"/></w:pPr><w:rPr><w:rFonts w:ascii="Arial" w:hAnsi="Arial"/><w:color w:val="456258"/><w:b/><w:sz w:val="26"/></w:rPr></w:style>
</w:styles>'''
    core = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:dcterms="http://purl.org/dc/terms/">
 <dc:title>ZenTrip Current Activity Diagram</dc:title><dc:subject>Integrated end-to-end workflow and editable activity notes</dc:subject><dc:creator>ZenTrip</dc:creator>
</cp:coreProperties>'''
    app = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Properties xmlns="http://schemas.openxmlformats.org/officeDocument/2006/extended-properties"><Application>Microsoft Word</Application></Properties>'''

    OUT.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(DOCX_PATH, "w", zipfile.ZIP_DEFLATED) as archive:
        archive.writestr("[Content_Types].xml", content_types)
        archive.writestr("_rels/.rels", root_rels)
        archive.writestr("word/document.xml", document)
        archive.writestr("word/_rels/document.xml.rels", document_rels_with_png if png else document_rels_svg_only)
        archive.writestr("word/styles.xml", styles)
        archive.writestr("docProps/core.xml", core)
        archive.writestr("docProps/app.xml", app)
        archive.writestr("word/media/diagram.svg", svg)
        if png:
            archive.writestr("word/media/diagram.png", png)


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    svg = build_svg()
    SVG_PATH.write_text(svg, encoding="utf-8")
    HTML_PATH.write_text(build_html(svg), encoding="utf-8")

    png_data = None
    magick = shutil.which("magick")
    if magick:
        try:
            subprocess.run(
                [magick, "-background", "white", "-density", "160", str(SVG_PATH), "-resize", f"{WIDTH}x{HEIGHT}!", str(PNG_PATH)],
                check=True,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.PIPE,
                timeout=60,
            )
            png_data = PNG_PATH.read_bytes()
        except (subprocess.CalledProcessError, OSError, subprocess.TimeoutExpired):
            png_data = None

    build_docx(png_data, svg.encode("utf-8"))
    orthogonal_count = len(EDGES)
    print(f"Generated {SVG_PATH.relative_to(ROOT)}")
    print(f"Generated {HTML_PATH.relative_to(ROOT)}")
    print(f"Generated {DOCX_PATH.relative_to(ROOT)}")
    print(f"Edges validated as orthogonal: {orthogonal_count}")
    print(f"Word PNG compatibility fallback: {'included' if png_data else 'not available; SVG only'}")


if __name__ == "__main__":
    main()
