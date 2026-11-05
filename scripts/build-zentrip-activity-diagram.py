#!/usr/bin/env python3
"""Generate the verified Zentrip flow diagrams, HTML viewer, and Word document."""

from __future__ import annotations

import html
import json
import shutil
import subprocess
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "generated-artifacts"
WIDTH = 2200
HEIGHT = 1120
WORD_PATH = OUT / "ZenTrip-Activity-Diagram-Integrated.docx"

COLORS = {
    "ink": "#263a33",
    "muted": "#62756d",
    "lane": "#eef4ef",
    "lane2": "#f3f1f9",
    "lane3": "#eef4f9",
    "user_fill": "#f9fcf9",
    "user_stroke": "#8eac99",
    "system_fill": "#fbfaff",
    "system_stroke": "#a89cbe",
    "api_fill": "#f9fcff",
    "api_stroke": "#91acc0",
    "success_fill": "#edf5fa",
    "success_stroke": "#668ba5",
    "error_fill": "#fff9f6",
    "error_stroke": "#d49a88",
    "line": "#839d8e",
    "api_line": "#456984",
    "error_line": "#c17d68",
    "start_fill": "#d9eee3",
    "start_stroke": "#75a48b",
    "white": "#ffffff",
}


def node(ident, x, y, w, h, label, kind="system", shape="box", font=20):
    return {
        "id": ident,
        "x": x,
        "y": y,
        "w": w,
        "h": h,
        "label": label.split("\n"),
        "kind": kind,
        "shape": shape,
        "font": font,
    }


def edge(ident, points, kind="main", label="", label_at=None):
    for (x1, y1), (x2, y2) in zip(points, points[1:]):
        if x1 != x2 and y1 != y2:
            raise ValueError(f"Non-orthogonal connector {ident}: {(x1, y1)} -> {(x2, y2)}")
    return {
        "id": ident,
        "points": points,
        "kind": kind,
        "label": label,
        "label_at": label_at,
    }


def page(ident, title, subtitle, lanes, nodes, edges, note):
    return {
        "id": ident,
        "title": title,
        "subtitle": subtitle,
        "lanes": lanes,
        "nodes": nodes,
        "edges": edges,
        "note": note,
    }


PAGES = [
    page(
        "01-access",
        "1 · Entry, Roles & App Navigation",
        "Roles come from the verified account; customers, admins, and partners enter separate app areas.",
        [
            (32, 125, 2136, 900, "lane", "ENTRY, ROLE ROUTING & CUSTOMER MODULES"),
        ],
        [
            node("start", 100, 320, 68, 68, "Start", "start", "start"),
            node("restore", 335, 320, 230, 88, "Restore saved session\nor continue onboarding", "user"),
            node("session", 620, 320, 160, 126, "Session\navailable?", "decision", "diamond", 18),
            node("signin", 620, 545, 230, 82, "Sign in or\ncreate account", "user"),
            node("role", 915, 320, 170, 136, "Verified\nrole?", "decision", "diamond", 18),
            node("customer", 1190, 225, 230, 90, "Customer AppShell", "user"),
            node("admin", 1190, 520, 250, 90, "Admin dashboard", "system"),
            node("partner", 1190, 790, 250, 90, "Partner dashboard", "system"),
            node(
                "modules",
                1575,
                225,
                370,
                160,
                "Customer modules\nFlights p2–3 · Hotels p4\nPlaces p5 · Cars / transfers\nOffers · Zen AI · My Trips p6–7",
                "user",
                font=18,
            ),
            node(
                "admin-capabilities",
                1575,
                520,
                370,
                145,
                "Stats · partners · reservations\ncustomers · places · offers\nNo separate settings route found",
                "system",
                font=18,
            ),
            node(
                "partner-capabilities",
                1575,
                790,
                370,
                145,
                "Own listings CRUD\nOwn reservations / customers\nPartner-scoped dashboard",
                "system",
                font=18,
            ),
            node("logout", 2070, 520, 84, 84, "Logout", "end", "end"),
        ],
        [
            edge("start-restore", [(134, 320), (220, 320)]),
            edge("restore-session", [(450, 320), (540, 320)]),
            edge("session-yes-role", [(700, 320), (830, 320)], label="Yes", label_at=(765, 300)),
            edge("session-no-login", [(620, 383), (620, 504)], label="No", label_at=(640, 455)),
            edge("login-role", [(735, 545), (800, 545), (800, 320), (830, 320)], label="Signed in", label_at=(820, 520)),
            edge("role-customer", [(1000, 320), (1070, 320), (1070, 225), (1075, 225)], label="Customer", label_at=(1038, 300)),
            edge("role-admin", [(915, 388), (915, 520), (1065, 520)], label="Admin", label_at=(938, 493)),
            edge("role-partner", [(960, 380), (1020, 380), (1020, 790), (1065, 790)], label="Partner", label_at=(1040, 765)),
            edge("customer-modules", [(1305, 225), (1390, 225)]),
            edge("customer-logout", [(1760, 225), (1990, 225), (1990, 520), (2028, 520)], label="Sign out", label_at=(1870, 205)),
            edge("admin-capabilities", [(1315, 520), (1390, 520)]),
            edge("admin-logout", [(1760, 520), (2028, 520)]),
            edge("partner-capabilities", [(1315, 790), (1390, 790)]),
            edge("partner-logout", [(1760, 790), (1900, 790), (1900, 520), (2028, 520)]),
        ],
        "Admin routes cover dashboard, partners, reservations, customers, places, and offers. No app-wide settings endpoint is present in the current controller.",
    ),
    page(
        "02-flight-search",
        "2 · Flight Search & Results",
        "Airport lookup selects the route; the flight search then merges only partner inventory and Duffel offers.",
        [
            (32, 125, 2136, 485, "lane", "AIRPORT SELECTION IS SEPARATE FROM FLIGHT INVENTORY"),
        ],
        [
            node("airport-select", 210, 285, 260, 112, "Select origin and destination\nGET /api/airports/search", "user", font=18),
            node("flight-criteria", 520, 285, 240, 112, "Dates or flexible months\npassengers · cabin", "user", font=18),
            node("flight-search-api", 825, 285, 270, 112, "GET /api/flights/search\nor /search/flexible", "api", font=18),
            node("partner-offers", 1130, 220, 220, 82, "Partner flight listings", "api", font=18),
            node("duffel-offers", 1130, 365, 220, 82, "Duffel flight offers", "api", font=18),
            node("flight-merge", 1390, 290, 86, 86, "M", "system", "merge", 18),
            node("flight-normalize", 1580, 290, 250, 112, "Merge results\nwarnings · sort / filter", "system", font=18),
            node("has-flights", 1870, 290, 160, 126, "Offers\navailable?", "decision", "diamond", 18),
            node("flight-results", 2075, 290, 180, 112, "Review and select\na flight", "user", font=18),
            node("flight-empty", 1870, 500, 270, 84, "Empty or unavailable\nstate; retry search", "error", font=18),
        ],
        [
            edge("airport-criteria", [(340, 341), (400, 341)]),
            edge("criteria-search", [(640, 341), (690, 341)]),
            edge("search-partner", [(960, 285), (1015, 285), (1015, 220), (1020, 220)], "api"),
            edge("search-duffel", [(960, 341), (1015, 341), (1015, 365), (1020, 365)], "api"),
            edge("partner-merge", [(1240, 220), (1310, 220), (1310, 290), (1347, 290)], "api"),
            edge("duffel-merge", [(1240, 365), (1310, 365), (1310, 290), (1347, 290)], "api"),
            edge("merge-normalize", [(1433, 290), (1455, 290)]),
            edge("normalize-available", [(1705, 290), (1790, 290)]),
            edge("available-results", [(1950, 290), (1985, 290)], label="Yes", label_at=(1965, 270)),
            edge("available-empty", [(1870, 353), (1870, 458)], "error", "No", (1890, 410)),
            edge("empty-retry", [(1735, 500), (520, 500), (520, 341)], "error", "Retry", (1130, 480)),
        ],
        "The airport directory helps resolve airport names and codes before search. It does not return bookable flight offers. Provider warnings accompany partial results.",
    ),
    page(
        "03-flight-checkout",
        "3 · Flight Checkout (Provider-Specific)",
        "The checkout is simulated. Partner flights use local seat holds; Duffel results are saved as simulated trips.",
        [
            (32, 125, 2136, 415, "lane", "PARTNER LISTING · LOCAL SEAT HOLD"),
            (32, 555, 2136, 440, "lane3", "DUFFEL OFFER · NO BACKEND SEAT HOLD OR SUPPLIER TICKET"),
        ],
        [
            node("partner-selected", 190, 290, 230, 96, "Selected partner\noffer", "user", font=18),
            node("partner-hold", 485, 290, 240, 96, "Reserve selected seats\n15-minute hold", "system", font=18),
            node("partner-payment", 785, 290, 230, 96, "Simulated\ncheckout", "system", font=18),
            node("partner-paid", 1075, 290, 150, 120, "Payment\nsuccessful?", "decision", "diamond", 18),
            node("partner-confirm", 1350, 290, 260, 96, "POST /api/bookings/confirm\nconfirm seats + save trip", "success", font=17),
            node("partner-mytrips", 1785, 290, 260, 96, "Trip appears in\nMy Trips", "user", font=18),
            node("partner-fail", 1075, 470, 330, 78, "Failure releases hold;\nreturn to seat selection", "error", font=17),
            node("duffel-selected", 190, 735, 230, 96, "Selected Duffel\noffer", "user", font=18),
            node("duffel-no-hold", 485, 735, 240, 96, "No backend\nseat hold", "system", font=18),
            node("duffel-payment", 785, 735, 230, 96, "Simulated\ncheckout", "system", font=18),
            node("duffel-paid", 1075, 735, 150, 120, "Payment\nsuccessful?", "decision", "diamond", 18),
            node("duffel-create-trip", 1350, 735, 260, 96, "POST /api/trips\nis_simulated = true", "success", font=17),
            node("duffel-mytrips", 1785, 735, 260, 96, "Trip appears in My Trips\nno supplier ticket issued", "user", font=17),
            node("duffel-fail", 1075, 930, 330, 78, "No trip saved; no hold\nRetry checkout", "error", font=17),
        ],
        [
            edge("partner-select-hold", [(305, 290), (365, 290)]),
            edge("partner-hold-payment", [(605, 290), (670, 290)]),
            edge("partner-payment-decision", [(900, 290), (1000, 290)]),
            edge("partner-paid-confirm", [(1150, 290), (1220, 290)], "main", "Yes", (1180, 270)),
            edge("partner-confirm-trip", [(1480, 290), (1655, 290)]),
            edge("partner-failed", [(1075, 350), (1075, 431)], "error", "No", (1095, 395)),
            edge("partner-reselect", [(910, 470), (485, 470), (485, 338)], "error", "Reselect", (700, 450)),
            edge("duffel-select-nohold", [(305, 735), (365, 735)]),
            edge("duffel-nohold-payment", [(605, 735), (670, 735)]),
            edge("duffel-payment-decision", [(900, 735), (1000, 735)]),
            edge("duffel-paid-save", [(1150, 735), (1220, 735)], "main", "Yes", (1180, 715)),
            edge("duffel-save-trip", [(1480, 735), (1655, 735)]),
            edge("duffel-payment-failed", [(1075, 795), (1075, 890)], "error", "No", (1095, 845)),
            edge("duffel-retry", [(910, 930), (785, 930), (785, 783)], "error", "Retry", (850, 910)),
        ],
        "Partner payment failure releases its temporary seat hold. Duffel checkout does not use that partner seat-hold endpoint; success stores a Zentrip trip only.",
    ),
    page(
        "04-hotels",
        "4 · Hotel Search & Simulated Booking",
        "LiteAPI contributes hotel data; partner listings are also searched. Zentrip records the simulated booking.",
        [
            (32, 125, 2136, 420, "lane", "SEARCH AND MERGE HOTEL DATA"),
            (32, 565, 2136, 450, "lane2", "BOOKING CHECKOUT AND PERSISTENCE"),
        ],
        [
            node("hotel-search-input", 180, 280, 240, 96, "Destination, dates,\nrooms and guests", "user", font=18),
            node("hotel-search-api", 490, 280, 250, 96, "GET /api/hotels/search", "api", font=18),
            node("hotel-partner", 815, 220, 220, 78, "Partner hotel listings", "api", font=18),
            node("hotel-liteapi", 815, 355, 220, 78, "LiteAPI hotel data", "api", font=18),
            node("hotel-merge", 1080, 285, 82, 82, "M", "system", "merge", 18),
            node("hotel-normalize", 1285, 285, 240, 96, "Merge, filter,\nshow provider warnings", "system", font=18),
            node("hotel-results", 1580, 285, 250, 96, "Review hotel results\nand select a stay", "user", font=18),
            node("hotel-empty", 1285, 470, 280, 72, "Partial / empty results:\nshow warning and retry", "error", font=16),
            node("hotel-selected", 180, 785, 220, 92, "Selected hotel / room", "user", font=18),
            node("hotel-schedule", 465, 785, 270, 92, "GET /api/bookings/availability\ncustomer schedule conflict", "system", font=16),
            node("hotel-payment", 800, 785, 220, 92, "Simulated\ncheckout", "system", font=18),
            node("hotel-paid", 1080, 785, 150, 120, "Payment\nsuccessful?", "decision", "diamond", 18),
            node("hotel-save", 1370, 785, 280, 92, "POST /api/bookings\nZentrip booking record", "success", font=17),
            node("hotel-recorded", 1740, 785, 300, 92, "Partner rooms reserved\nwhen a partner listing applies", "success", font=17),
            node("hotel-failed", 1080, 965, 300, 72, "No booking created;\nretry or leave checkout", "error", font=17),
        ],
        [
            edge("hotel-input-api", [(300, 280), (365, 280)]),
            edge("hotel-api-partner", [(615, 280), (700, 280), (700, 220), (705, 220)], "api"),
            edge("hotel-api-liteapi", [(615, 280), (700, 280), (700, 355), (705, 355)], "api"),
            edge("hotel-partner-merge", [(925, 220), (1000, 220), (1000, 285), (1039, 285)], "api"),
            edge("hotel-liteapi-merge", [(925, 355), (1000, 355), (1000, 285), (1039, 285)], "api"),
            edge("hotel-merge-normalize", [(1121, 285), (1165, 285)]),
            edge("hotel-normalize-results", [(1405, 285), (1455, 285)]),
            edge("hotel-normalize-warning", [(1285, 333), (1285, 434)], "error", "Provider issue", (1305, 390)),
            edge("hotel-warning-retry", [(1145, 470), (490, 470), (490, 328)], "error", "Retry search", (800, 450)),
            edge("hotel-results-selection", [(1705, 333), (1705, 610), (180, 610), (180, 739)]),
            edge("hotel-select-schedule", [(290, 785), (330, 785)]),
            edge("hotel-schedule-payment", [(600, 785), (690, 785)]),
            edge("hotel-payment-decision", [(910, 785), (1005, 785)]),
            edge("hotel-paid-save", [(1155, 785), (1230, 785)], "main", "Yes", (1190, 765)),
            edge("hotel-save-recorded", [(1510, 785), (1590, 785)]),
            edge("hotel-failed", [(1080, 845), (1080, 929)], "error", "No", (1100, 890)),
            edge("hotel-retry-payment", [(930, 965), (800, 965), (800, 831)], "error", "Retry", (870, 945)),
        ],
        "The availability endpoint checks the customer's schedule, not a fresh LiteAPI room quote. LiteAPI is search data only; no supplier reservation is created. Partner inventory is reserved only for linked partner listings.",
    ),
    page(
        "05-attractions",
        "5 · Places & Attraction Booking",
        "Place discovery is OpenTripMap-backed; viewing a place and booking an attraction are separate actions.",
        [
            (32, 125, 2136, 330, "lane", "DISCOVER PLACES"),
            (32, 475, 2136, 555, "lane3", "OPTIONAL ATTRACTION BOOKING"),
        ],
        [
            node("place-query", 180, 285, 240, 96, "Search nearby or\nby destination", "user", font=18),
            node("place-coordinates", 490, 285, 150, 116, "Coordinates\nknown?", "decision", "diamond", 17),
            node("place-geocode", 760, 385, 250, 80, "Geoapify geocoding\nonly when needed", "api", font=17),
            node("place-search", 1050, 285, 260, 96, "GET /api/attractions/search\nOpenTripMap places", "api", font=17),
            node("place-detail", 1390, 285, 220, 96, "View place\ndetails", "user", font=18),
            node("place-visit", 1790, 220, 300, 90, "POST /api/attractions/{id}/visits\ncount deduplicated visit", "system", font=16),
            node("attraction-book", 1790, 470, 300, 84, "Choose Book attraction", "user", font=18),
            node("attraction-schedule", 1790, 600, 300, 84, "GET /api/bookings/availability\nschedule conflict check", "system", font=16),
            node("entry-fee", 1790, 740, 150, 116, "Entry fee\nabove zero?", "decision", "diamond", 17),
            node("attraction-payment", 1430, 900, 260, 80, "Simulated payment\n(paid entry only)", "system", font=17),
            node("attraction-paid", 1740, 900, 150, 116, "Payment\nsuccessful?", "decision", "diamond", 17),
            node("attraction-save", 2050, 760, 260, 90, "POST /api/bookings\n(type = attraction)", "success", font=17),
            node("attraction-fail", 1430, 1030, 280, 70, "No booking saved;\nretry or leave", "error", font=16),
        ],
        [
            edge("place-query-coordinates", [(300, 285), (415, 285)]),
            edge("coordinates-known-search", [(565, 285), (920, 285)], "main", "Yes", (745, 265)),
            edge("coordinates-missing-geocode", [(490, 343), (490, 385), (635, 385)], "api", "No", (512, 365)),
            edge("geocode-search", [(885, 385), (970, 385), (970, 285), (920, 285)], "api"),
            edge("place-search-detail", [(1180, 285), (1280, 285)], "api"),
            edge("detail-view-counter", [(1500, 237), (1610, 237), (1610, 220), (1640, 220)]),
            edge("detail-book", [(1500, 333), (1570, 333), (1570, 470), (1640, 470)]),
            edge("book-schedule", [(1790, 512), (1790, 558)]),
            edge("schedule-fee", [(1790, 642), (1790, 682)]),
            edge("free-save", [(1865, 740), (1890, 740), (1890, 760), (1920, 760)], "main", "No · free", (1880, 720)),
            edge("paid-entry-payment", [(1715, 740), (1560, 740), (1560, 860)], "main", "Yes · paid", (1595, 720)),
            edge("payment-success-decision", [(1560, 900), (1665, 900)]),
            edge("payment-success-save", [(1815, 900), (1915, 900), (1915, 805), (1920, 805)], "main", "Yes", (1850, 880)),
            edge("payment-fail", [(1740, 958), (1740, 1030), (1570, 1030)], "error", "No", (1760, 995)),
            edge("payment-retry", [(1430, 995), (1430, 940)], "error", "Retry", (1450, 980)),
        ],
        "A free attraction skips payment. Paid-entry attractions use the simulated checkout and then create a Zentrip booking; place viewing alone only records a privacy-preserving visit count.",
    ),
    page(
        "06-other-bookings",
        "6 · Packages, Cars & Transfers",
        "These customer-facing services use the existing booking storage paths; transfers are stored separately.",
        [
            (32, 125, 2136, 255, "lane", "PACKAGES / OFFERS"),
            (32, 405, 2136, 255, "lane2", "CAR RENTAL"),
            (32, 685, 2136, 330, "lane3", "TRANSFERS"),
        ],
        [
            node("packages-search", 190, 250, 230, 90, "GET /api/offers", "api", font=18),
            node("packages-detail", 490, 250, 220, 90, "Select package", "user", font=18),
            node("packages-schedule", 790, 250, 240, 90, "Check schedule\nconflicts", "system", font=18),
            node("packages-payment", 1110, 250, 220, 90, "Simulated\npayment", "system", font=18),
            node("packages-save", 1400, 250, 300, 90, "POST /api/bookings\n(type = package)", "success", font=17),
            node("packages-trips", 1810, 250, 260, 90, "Display in\nMy Trips", "user", font=18),
            node("cars-search", 190, 530, 230, 90, "GET /api/cars/nearby", "api", font=18),
            node("cars-detail", 490, 530, 220, 90, "Select vehicle", "user", font=18),
            node("cars-schedule", 790, 530, 240, 90, "Check schedule\nconflicts", "system", font=18),
            node("cars-payment", 1110, 530, 220, 90, "Simulated\npayment", "system", font=18),
            node("cars-save", 1400, 530, 300, 90, "POST /api/bookings\n(type = car)", "success", font=17),
            node("cars-trips", 1810, 530, 260, 90, "Partner vehicle reserved\nwhen linked · shown in My Trips", "success", font=16),
            node("transfer-search", 190, 830, 230, 90, "Search / select transfer\nroute and pickup time", "user", font=17),
            node("transfer-schedule", 490, 830, 260, 90, "GET /api/transfers/availability\nschedule conflict check", "system", font=16),
            node("transfer-payment", 820, 830, 220, 90, "Simulated\npayment", "system", font=18),
            node("transfer-save", 1110, 830, 260, 90, "POST /api/transfers", "success", font=18),
            node("transfer-trips", 1480, 830, 260, 90, "Stored in transfers;\nshown in My Trips", "user", font=17),
        ],
        [
            edge("packages-flow-1", [(305, 250), (380, 250)], "api"),
            edge("packages-flow-2", [(600, 250), (670, 250)]),
            edge("packages-flow-3", [(910, 250), (1000, 250)]),
            edge("packages-flow-4", [(1220, 250), (1250, 250)]),
            edge("packages-flow-5", [(1550, 250), (1680, 250)]),
            edge("cars-flow-1", [(305, 530), (380, 530)], "api"),
            edge("cars-flow-2", [(600, 530), (670, 530)]),
            edge("cars-flow-3", [(910, 530), (1000, 530)]),
            edge("cars-flow-4", [(1220, 530), (1250, 530)]),
            edge("cars-flow-5", [(1550, 530), (1680, 530)]),
            edge("transfer-flow-1", [(305, 830), (360, 830)]),
            edge("transfer-flow-2", [(620, 830), (710, 830)]),
            edge("transfer-flow-3", [(930, 830), (1000, 830)]),
            edge("transfer-flow-4", [(1210, 830), (1350, 830)]),
        ],
        "The current backend has transfer create/list endpoints but no DELETE /api/transfers/{id} cancellation route. Transfer cancellation is therefore not shown as a working server flow.",
    ),
    page(
        "07-ai-trips",
        "7 · Zen AI, My Trips & Persistence",
        "Chat history is saved locally and server-side; completed status is derived from travel dates.",
        [
            (32, 125, 2136, 335, "lane", "ZEN AI · CHAT, NOT A BOOKED ITINERARY"),
            (32, 480, 2136, 535, "lane3", "MY TRIPS · CURRENT-USER RECORDS AND CANCELLATION"),
        ],
        [
            node("ai-prompt", 180, 260, 230, 88, "Enter chat prompt", "user", font=18),
            node("ai-endpoint", 490, 260, 260, 88, "POST /api/ai/chat\nstreaming response", "api", font=17),
            node("ai-provider", 830, 260, 220, 88, "Requesty provider", "api", font=18),
            node("ai-reply", 1120, 260, 230, 88, "Read streamed reply", "system", font=18),
            node("ai-local", 1510, 205, 280, 88, "Flutter SharedPreferences\nlocal chat history", "success", font=17),
            node("ai-server", 1510, 345, 280, 88, "Supabase ai_chat_messages\nserver-side history", "success", font=17),
            node("trips-open", 180, 690, 230, 90, "Open My Trips", "user", font=18),
            node("trips-fetch", 490, 690, 290, 90, "GET /api/trips\nGET /api/bookings\nGET /api/transfers", "api", font=16),
            node("trips-data", 860, 690, 280, 90, "Supabase records\nfiltered to current user", "success", font=17),
            node("trips-display", 1220, 690, 230, 90, "Display items\nand statuses", "user", font=18),
            node("cancel-kind", 1530, 690, 170, 128, "Cancel item\ntype?", "decision", "diamond", 17),
            node("cancel-flight", 1820, 590, 300, 90, "DELETE /api/trips/{id}\nstatus cancelled", "system", font=17),
            node("cancel-booking", 1820, 800, 300, 90, "DELETE /api/bookings/{id}\nstatus cancelled", "system", font=17),
            node("date-status", 500, 900, 340, 70, "Completed status is derived\nwhen travel end date passes", "system", font=17),
            node("refund-status", 1190, 900, 360, 70, "Flight cancellation records\nrefund pending airline review", "error", font=17),
            node("transfer-cancel-gap", 1660, 970, 450, 70, "No server-side transfer cancellation\nendpoint currently found", "error", font=16),
        ],
        [
            edge("ai-prompt-api", [(295, 260), (360, 260)]),
            edge("ai-api-provider", [(620, 260), (720, 260)], "api"),
            edge("ai-provider-reply", [(940, 260), (1005, 260)], "api"),
            edge("ai-reply-local", [(1235, 260), (1300, 260), (1300, 205), (1370, 205)]),
            edge("ai-reply-server", [(1235, 260), (1330, 260), (1330, 345), (1370, 345)], "api"),
            edge("trips-open-fetch", [(295, 690), (345, 690)]),
            edge("trips-fetch-data", [(635, 690), (720, 690)], "api"),
            edge("trips-data-display", [(1000, 690), (1105, 690)]),
            edge("trips-display-cancel", [(1335, 690), (1445, 690)]),
            edge("trips-status-date", [(1220, 735), (1220, 840), (670, 840), (670, 900)], "main", "Date status", (930, 820)),
            edge("cancel-flight-path", [(1615, 690), (1700, 690), (1700, 590), (1670, 590)], "main", "Flight", (1655, 670)),
            edge("cancel-booking-path", [(1530, 754), (1530, 800), (1670, 800)], "main", "Other booking", (1600, 780)),
            edge("cancel-transfer-gap", [(1530, 626), (1400, 626), (1400, 970), (1435, 970)], "error", "Transfer", (1435, 610)),
            edge("flight-refund-note", [(1820, 635), (1500, 635), (1500, 900), (1370, 900)], "error"),
        ],
        "The current Trips screen derives completed status from dates. Flight cancellation and other booking cancellation use separate endpoints. The flight refund state is pending review; the app does not call an airline to issue a refund.",
    ),
]


def validate_pages():
    for p in PAGES:
        ids = [n["id"] for n in p["nodes"]]
        if len(ids) != len(set(ids)):
            raise ValueError(f"{p['id']}: duplicate node id")
        for n in p["nodes"]:
            half_w = n["w"] / 2
            half_h = n["h"] / 2
            if n["x"] - half_w < 0 or n["x"] + half_w > WIDTH:
                raise ValueError(f"{p['id']}: node {n['id']} exceeds diagram width")
            if n["y"] - half_h < 90 or n["y"] + half_h > HEIGHT - 45:
                raise ValueError(f"{p['id']}: node {n['id']} exceeds diagram height")
        for i, a in enumerate(p["nodes"]):
            for b in p["nodes"][i+1:]:
                gap = 2
                if (
                    abs(a["x"] - b["x"]) < (a["w"] + b["w"]) / 2 - gap
                    and abs(a["y"] - b["y"]) < (a["h"] + b["h"]) / 2 - gap
                ):
                    raise ValueError(f"{p['id']}: nodes {a['id']} and {b['id']} overlap")
        for e in p["edges"]:
            if any(x < 0 or x > WIDTH or y < 0 or y > HEIGHT for x, y in e["points"]):
                raise ValueError(f"{p['id']}: connector {e['id']} exceeds canvas bounds")


def render_node(item):
    x, y, w, h = item["x"], item["y"], item["w"], item["h"]
    kind, shape = item["kind"], item["shape"]
    fill, stroke = COLORS["user_fill"], COLORS["user_stroke"]
    if kind in {"system", "decision"}:
        fill, stroke = COLORS["system_fill"], COLORS["system_stroke"]
    elif kind == "api":
        fill, stroke = COLORS["api_fill"], COLORS["api_stroke"]
    elif kind == "success":
        fill, stroke = COLORS["success_fill"], COLORS["success_stroke"]
    elif kind == "error":
        fill, stroke = COLORS["error_fill"], COLORS["error_stroke"]
    elif kind == "start":
        fill, stroke = COLORS["start_fill"], COLORS["start_stroke"]
    elif kind == "end":
        fill, stroke = COLORS["white"], COLORS["start_stroke"]

    if shape == "start":
        geometry = (
            f'<circle cx="{x}" cy="{y}" r="{w / 2}" fill="{fill}" stroke="{stroke}"/>'
            f'<circle cx="{x}" cy="{y}" r="10" fill="{stroke}"/>'
        )
    elif shape == "end":
        geometry = (
            f'<circle cx="{x}" cy="{y}" r="{w / 2}" fill="{fill}" stroke="{stroke}"/>'
            f'<circle cx="{x}" cy="{y}" r="{w / 2 - 8}" fill="none" stroke="{stroke}" stroke-width="2"/>'
        )
    elif shape == "diamond":
        points = f"{x},{y-h/2} {x+w/2},{y} {x},{y+h/2} {x-w/2},{y}"
        geometry = f'<polygon points="{points}" fill="{fill}" stroke="{stroke}"/>'
    elif shape == "merge":
        geometry = f'<circle cx="{x}" cy="{y}" r="{w/2}" fill="#fff" stroke="{stroke}"/>'
    else:
        geometry = (
            f'<rect x="{x-w/2}" y="{y-h/2}" width="{w}" height="{h}" rx="14" '
            f'fill="{fill}" stroke="{stroke}"/>'
        )

    labels = item["label"]
    size = item["font"]
    line_height = size + 4
    if shape in {"start", "end"}:
        text = "".join(
            f'<text x="{x}" y="{y+w/2+22+i*line_height}" text-anchor="middle" '
            f'font-size="16" font-weight="700" fill="{COLORS["ink"]}">{html.escape(line)}</text>'
            for i, line in enumerate(labels)
        )
    else:
        start_y = y - (len(labels)-1)*line_height/2 + size/3
        text = "".join(
            f'<text x="{x}" y="{start_y+i*line_height}" text-anchor="middle" '
            f'font-size="{size}" font-weight="650" fill="{COLORS["ink"]}">{html.escape(line)}</text>'
            for i, line in enumerate(labels)
        )
    aria = html.escape(f'{item["id"]}: {" ".join(labels)}')
    return f'<g id="{item["id"]}" role="img" aria-label="{aria}"><title>{aria}</title>{geometry}{text}</g>'


def render_edge(item):
    color = COLORS["line"]
    dash = ""
    if item["kind"] == "api":
        color = COLORS["api_line"]
    elif item["kind"] == "error":
        color, dash = COLORS["error_line"], ' stroke-dasharray="8 7"'
    d = "M " + " L ".join(f"{x} {y}" for x, y in item["points"])
    path = (
        f'<path id="{item["id"]}" d="{d}" fill="none" stroke="{color}" stroke-width="3" '
        f'stroke-linejoin="round" stroke-linecap="square" marker-end="url(#arrow-{item["kind"]})"{dash}/>'
    )
    label = ""
    if item["label"] and item["label_at"]:
        lx, ly = item["label_at"]
        label = (
            f'<text x="{lx}" y="{ly}" text-anchor="middle" font-size="16" font-weight="700" '
            f'fill="{color}" paint-order="stroke" stroke="#fff" stroke-width="6">'
            f'{html.escape(item["label"])}</text>'
        )
    return path + label


def build_svg(p):
    lane_markup = "".join(
        f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="22" fill="{COLORS[fill]}" stroke="#d9e4dd" stroke-width="2"/>'
        f'<text x="{x+20}" y="{y+30}" class="lane">{html.escape(title)}</text>'
        for x, y, w, h, fill, title in p["lanes"]
    )
    edge_markup = "".join(render_edge(e) for e in p["edges"])
    node_markup = "".join(render_node(n) for n in p["nodes"])
    return f'''<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg" width="{WIDTH}" height="{HEIGHT}" viewBox="0 0 {WIDTH} {HEIGHT}" role="img" aria-labelledby="title desc">
<title id="title">{html.escape(p["title"])}</title>
<desc id="desc">{html.escape(p["subtitle"])} {html.escape(p["note"])}</desc>
<defs>
 <marker id="arrow-main" viewBox="0 0 10 10" refX="8.5" refY="5" markerWidth="9" markerHeight="9" orient="auto"><path d="M0 0 L10 5 L0 10Z" fill="{COLORS["line"]}"/></marker>
 <marker id="arrow-api" viewBox="0 0 10 10" refX="8.5" refY="5" markerWidth="9" markerHeight="9" orient="auto"><path d="M0 0 L10 5 L0 10Z" fill="{COLORS["api_line"]}"/></marker>
 <marker id="arrow-error" viewBox="0 0 10 10" refX="8.5" refY="5" markerWidth="9" markerHeight="9" orient="auto"><path d="M0 0 L10 5 L0 10Z" fill="{COLORS["error_line"]}"/></marker>
 <style>text{{font-family:Arial,Helvetica,sans-serif}}.title{{font-size:30px;font-weight:700;fill:{COLORS["ink"]}}}.subtitle{{font-size:18px;fill:{COLORS["muted"]}}}.lane{{font-size:17px;font-weight:700;letter-spacing:.04em;fill:#456258}}.note{{font-size:16px;fill:{COLORS["muted"]}}}</style>
</defs>
<rect width="100%" height="100%" fill="#fff"/>
<text x="42" y="44" class="title">{html.escape(p["title"])}</text>
<text x="42" y="77" class="subtitle">{html.escape(p["subtitle"])}</text>
{lane_markup}
<g id="edges">{edge_markup}</g>
<g id="nodes">{node_markup}</g>
<text x="48" y="1085" class="note">{html.escape(p["note"])}</text>
</svg>'''


def mermaid_source(p):
    nodes = p["nodes"]
    by_id = {item["id"]: item for item in nodes}

    def nearest(point):
        px, py = point
        def distance(item):
            dx = max(abs(px-item["x"]) - item["w"]/2, 0)
            dy = max(abs(py-item["y"]) - item["h"]/2, 0)
            return dx*dx + dy*dy
        return min(nodes, key=distance)["id"]

    linked = []
    incoming = {item["id"]: 0 for item in nodes}
    outgoing = {item["id"]: 0 for item in nodes}
    for item in p["edges"]:
        source, target = nearest(item["points"][0]), nearest(item["points"][-1])
        linked.append((source, target, item))
        outgoing[source] += 1
        incoming[target] += 1

    existing_start = [item["id"] for item in nodes if item["shape"] == "start"]
    existing_end = [item["id"] for item in nodes if item["shape"] == "end"]
    roots = existing_start or [ident for ident, count in incoming.items() if count == 0]
    sinks = existing_end or [ident for ident, count in outgoing.items() if count == 0]

    # The date-status and transfer-cancellation boxes are findings, not entry
    # actions. Keep them on the My Trips path rather than treating them as roots.
    if p["id"] == "07-ai-trips":
        roots = ["ai-prompt", "trips-open"]
        sinks = ["ai-local", "ai-server", "cancel-booking", "date-status", "refund-status", "transfer-cancel-gap"]

    root_titles = {
        "partner-selected": "Partner flight",
        "duffel-selected": "Duffel flight",
        "packages-search": "Packages",
        "cars-search": "Cars",
        "transfer-search": "Transfers",
        "ai-prompt": "Zen AI",
        "trips-open": "My Trips",
    }
    synthetic = []
    if not existing_start:
        synthetic.append(("flowStart", "User", "start", "Start"))
        if len(roots) > 1:
            synthetic.append(("flowChoice", "User", "decision", "Choose a flow"))
    if not existing_end:
        synthetic.append(("flowEnd", "ZenTrip App / System", "end", "End"))

    def lane_for(item):
        ident, kind = item["id"], item["kind"]
        if ident == "flowEnd":
            return "ZenTrip App / System"
        if ident == "admin" or ident.startswith("admin-"):
            return "Admin"
        if ident == "partner" or ident == "partner-capabilities":
            return "Partner"
        if kind == "user" or item["shape"] in {"start", "end"}:
            return "User"
        if "payment" in ident or ident.endswith("-paid"):
            return "Payment Gateway"
        if ident in {
            "partner-offers", "duffel-offers", "hotel-partner", "hotel-liteapi",
            "place-geocode", "place-search", "ai-provider",
        }:
            return "Travel Providers"
        return "ZenTrip App / System"

    def label_text(lines):
        return "<br/>".join(html.escape(line, quote=False).replace('"', "&quot;") for line in lines)

    def declaration(ident, shape, label):
        safe = label.replace('"', "&quot;")
        if shape == "start":
            return f'{ident}(({safe}))'
        if shape == "end":
            return f'{ident}((({safe})))'
        if shape == "diamond":
            return f'{ident}{{"{safe}"}}'
        if shape == "merge":
            return f'{ident}(("{safe}"))'
        return f'{ident}["{safe}"]'

    all_items = list(nodes)
    for ident, lane, shape, label in synthetic:
        all_items.append({
            "id": ident,
            "kind": "user" if lane == "User" else "system",
            "shape": shape,
            "label": [label],
        })
    groups = {}
    for item in all_items:
        groups.setdefault(lane_for(item), []).append(item)

    lane_ids = {
        "User": "userLane",
        "ZenTrip App / System": "systemLane",
        "Payment Gateway": "paymentLane",
        "Travel Providers": "providerLane",
        "Admin": "adminLane",
        "Partner": "partnerLane",
    }
    lines = ["flowchart LR", f'%% {p["title"]}']
    for lane in ("User", "ZenTrip App / System", "Payment Gateway", "Travel Providers", "Admin", "Partner"):
        if lane not in groups:
            continue
        lines.append(f'  subgraph {lane_ids[lane]}["{lane}"]')
        for item in groups[lane]:
            lines.append(f'    {declaration(item["id"], item["shape"], label_text(item["label"]))}')
        lines.append("  end")

    if not existing_start:
        if len(roots) > 1:
            lines.append("  flowStart --> flowChoice")
            for root in roots:
                lines.append(f'  flowChoice -->|{root_titles.get(root, root)}| {root}')
        elif roots:
            lines.append(f"  flowStart --> {roots[0]}")

    for source, target, item in linked:
        label = item["label"]
        if item["kind"] == "error":
            connector = f"{source} -.->|{label or 'Error'}| {target}"
        elif item["kind"] == "api":
            connector = f"{source} ==>|{label}| {target}" if label else f"{source} ==> {target}"
        else:
            connector = f"{source} -->|{label}| {target}" if label else f"{source} --> {target}"
        lines.append(f"  {connector}")

    if not existing_end:
        for sink in sinks:
            if sink != "flowEnd":
                lines.append(f"  {sink} --> flowEnd")
    lines += [
        "  classDef user fill:#f9fcf9,stroke:#8eac99,color:#263a33,stroke-width:2px",
        "  classDef system fill:#fbfaff,stroke:#a89cbe,color:#263a33,stroke-width:2px",
        "  classDef api fill:#f9fcff,stroke:#91acc0,color:#263a33,stroke-width:2px",
        "  classDef success fill:#edf5fa,stroke:#668ba5,color:#263a33,stroke-width:2px",
        "  classDef error fill:#fff9f6,stroke:#d49a88,color:#263a33,stroke-width:2px",
        "  classDef start fill:#d9eee3,stroke:#75a48b,color:#263a33,stroke-width:3px",
        "  classDef finish fill:#ffffff,stroke:#75a48b,color:#263a33,stroke-width:4px",
    ]
    class_groups = {"user": [], "system": [], "api": [], "success": [], "error": [], "start": [], "finish": []}
    for item in all_items:
        shape, kind, ident = item["shape"], item["kind"], item["id"]
        if shape == "start":
            group = "start"
        elif shape == "end":
            group = "finish"
        elif kind in class_groups:
            group = kind
        elif kind == "decision":
            group = "system"
        else:
            group = "system"
        class_groups[group].append(ident)
    for group, ids in class_groups.items():
        if ids:
            lines.append(f"  class {','.join(ids)} {group}")
    return "\n".join(lines)


def build_html(pages):
    page_payload = json.dumps([
        {
            "title": p["title"],
            "subtitle": p["subtitle"],
            "note": p["note"],
            "source": mermaid_source(p),
            "fallback": f"zentrip-activity-{p['id']}.svg",
        }
        for p in pages
    ]).replace("</", "<\\/")
    page_buttons = "".join(
        f'<button type="button" data-page="{i}" aria-label="Open diagram page {i+1}">{i+1}. {html.escape(p["title"].split("·",1)[-1].strip())}</button>'
        for i, p in enumerate(pages)
    )
    return """<!doctype html>
<html lang="en"><head>
<meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>ZenTrip – Activity Diagram</title>
<style>
:root{color-scheme:light;--ink:#263a33;--muted:#62756d;--line:#d9e4dd;--surface:#fff;--page:#f5f8f5;--accent:#e4eee7}
*{box-sizing:border-box}body{margin:0;padding:18px;background:var(--page);font-family:Arial,Helvetica,sans-serif;color:var(--ink)}
header,.pages,.frame,.notes,.source-panel{max-width:1500px;margin-left:auto;margin-right:auto}
header{display:flex;justify-content:space-between;gap:16px;align-items:center;flex-wrap:wrap}
h1{font-size:25px;margin:0}p{color:var(--muted)}.lede{margin:6px 0}
.pages{display:flex;gap:7px;overflow-x:auto;padding:10px 0}
button,a{font:inherit;background:#fff;color:var(--ink);border:1px solid #c9d8d0;border-radius:8px;padding:8px 10px;cursor:pointer;white-space:nowrap;text-decoration:none}
button:hover,a:hover{background:var(--accent)}button.active{background:var(--accent);border-color:#8eac99}
.controls{display:flex;gap:7px;flex-wrap:wrap}
.frame{height:calc(100vh - 325px);min-height:360px;max-height:850px;overflow:hidden;position:relative;background:var(--surface);border:1px solid var(--line);border-radius:14px;touch-action:none;cursor:grab}
.frame.dragging{cursor:grabbing}#diagram{position:absolute;left:0;top:0;transform-origin:0 0;user-select:none}
#diagram svg{display:block;max-width:none}#status{font-size:13px;min-height:20px;color:var(--muted)}
.source-panel,.notes{background:#fff;border:1px solid var(--line);border-radius:12px;padding:12px;margin-top:12px}
summary{font-weight:700;cursor:pointer}.source-layout{display:grid;grid-template-columns:minmax(0,1fr) auto;gap:12px;margin-top:10px}
textarea{width:100%;min-height:250px;resize:vertical;font:13px/1.5 ui-monospace,SFMono-Regular,Consolas,monospace;padding:12px;border:1px solid #c9d8d0;border-radius:8px;color:var(--ink)}
.notes h2{font-size:18px;margin:4px 0}.notes ol,.notes ul{line-height:1.55}.legend{display:flex;gap:10px;flex-wrap:wrap}.legend span{background:#f7faf7;padding:6px 9px;border-radius:6px}
@media(max-width:700px){body{padding:10px}.frame{height:54vh;min-height:320px}.source-layout{grid-template-columns:1fr}header{align-items:flex-start}.controls{width:100%}}
@media print{.controls,.pages,.source-panel{display:none}.frame{height:auto;max-height:none;border:0}.notes{break-before:page}}
</style>
<script src="https://cdn.jsdelivr.net/npm/mermaid@12.3.0/dist/mermaid.min.js"></script>
</head><body>
<header><div><h1>ZenTrip – Activity Diagram</h1><p class="lede">Verified against the Flutter app and Spring Boot backend. Select a page, zoom or drag to inspect it.</p></div>
<div class="controls">
<button id="zoom-out" type="button" aria-label="Zoom out">−</button><button id="zoom-in" type="button" aria-label="Zoom in">+</button><button id="fit" type="button">Fit</button>
<button id="download-svg" type="button">Download SVG</button><button id="download-png" type="button">Download PNG</button>
<a id="download-docx" href="ZenTrip-Activity-Diagram-Integrated.docx" download>Download as Word (.docx)</a>
</div></header>
<nav class="pages" aria-label="Diagram pages">__PAGE_BUTTONS__</nav>
<main class="frame" id="frame" aria-label="Activity diagram preview"><div id="diagram"></div></main>
<p id="status" role="status" aria-live="polite"></p>
<details class="source-panel"><summary>Editable Mermaid source</summary>
<div class="source-layout"><textarea id="source" spellcheck="false" aria-label="Editable Mermaid diagram source"></textarea><div><button id="render" type="button">Render changes</button><p>Edits update the current preview as you type.</p></div></div>
</details>
<section class="notes"><h2>Verification checklist</h2><ol>
<li>Session restore / sign-in / account creation and verified role routing.</li>
<li>Search travel products and resolve airport or destination input.</li>
<li>Fetch and normalize provider data; handle warnings, empty results, and retries.</li>
<li>Select a flight, hotel, attraction, car, transfer, or package.</li>
<li>Check schedule conflicts; partner flights additionally reserve seats.</li>
<li>Run simulated checkout where the product has a fee; free attractions skip payment.</li>
<li>Persist success through the existing trip, booking, or transfer endpoints.</li>
<li>Show current-user items in My Trips; cancellation and completion follow existing rules.</li>
</ol><div class="legend"><span>● Start</span><span>◎ End</span><span>Rounded box: action</span><span>◇ Decision</span><span>○ M: merge</span><span>Solid arrow: normal flow</span><span>Dashed arrow: failure or limitation</span></div></section>
<section class="notes"><h2>Deviations / assumptions</h2><ul>
<li>The actual project is Flutter + Spring Boot, not Node/Express; this is a separate diagram viewer and does not replace the app stack.</li>
<li>Flight, hotel, car, and attraction checkout uses Zentrip's simulated payment. The diagram does not claim supplier ticketing or payment.</li>
<li>HotelLiteAPI is data-only. The hotel schedule check is not a provider room-availability recheck.</li>
<li>Flight, hotel, car, attraction, and package records use existing endpoints. Transfers are stored separately.</li>
<li>The code does not implement a multi-item itinerary with parallel flight/hotel/activity booking, booking email/notification, or a server-side transfer-cancellation endpoint.</li>
<li>No separate app-wide admin settings endpoint was found. Admin controls shown are the routes present in the current backend.</li>
</ul><p id="page-note"></p></section>
<script>
const pages=__PAGE_DATA__;
const frame=document.getElementById('frame'),diagram=document.getElementById('diagram'),editor=document.getElementById('source');
const statusEl=document.getElementById('status');let active=0,scale=1,x=0,y=0,drag=false,sx=0,sy=0,renderId=0,debounce;
if(typeof mermaid!=='undefined')mermaid.initialize({startOnLoad:false,securityLevel:'strict',theme:'base',themeVariables:{fontFamily:'Arial, sans-serif',primaryColor:'#f9fcf9',primaryTextColor:'#263a33',primaryBorderColor:'#8eac99',lineColor:'#839d8e',secondaryColor:'#fbfaff',tertiaryColor:'#eef4f9'}});
function apply(){diagram.style.transform=`translate(${x}px,${y}px) scale(${scale})`}
function fit(){const svg=diagram.querySelector('svg');if(!svg)return;const vb=svg.viewBox.baseVal;const r=frame.getBoundingClientRect();scale=Math.min((r.width-24)/vb.width,(r.height-24)/vb.height);x=(r.width-vb.width*scale)/2;y=(r.height-vb.height*scale)/2;apply()}
async function renderSource(){statusEl.textContent='Rendering diagram…';try{if(typeof mermaid==='undefined')throw new Error('Mermaid could not load. Connect to the internet and reload.');const id=`zentrip-flow-${++renderId}`;const result=await mermaid.render(id,editor.value);diagram.innerHTML=result.svg;if(result.bindFunctions)result.bindFunctions(diagram);statusEl.textContent='Diagram rendered.';fit()}catch(error){statusEl.textContent=`Diagram error: ${error.message}`}}
function showPage(i){active=i;editor.value=pages[i].source;document.getElementById('page-note').textContent=pages[i].subtitle+' '+pages[i].note;document.querySelectorAll('[data-page]').forEach(b=>b.classList.toggle('active',Number(b.dataset.page)===i));clearTimeout(debounce);renderSource()}
document.querySelectorAll('[data-page]').forEach(b=>b.onclick=()=>showPage(Number(b.dataset.page)));
editor.addEventListener('input',()=>{clearTimeout(debounce);debounce=setTimeout(renderSource,450)});
document.getElementById('render').onclick=renderSource;
document.getElementById('zoom-in').onclick=()=>{scale=Math.min(3,scale*1.2);apply()};
document.getElementById('zoom-out').onclick=()=>{scale=Math.max(.25,scale/1.2);apply()};
document.getElementById('fit').onclick=fit;window.addEventListener('resize',fit);
frame.addEventListener('wheel',e=>{e.preventDefault();scale=Math.max(.25,Math.min(3,scale*(e.deltaY<0?1.1:1/1.1)));apply()},{passive:false});
frame.addEventListener('pointerdown',e=>{drag=true;sx=e.clientX-x;sy=e.clientY-y;frame.classList.add('dragging');frame.setPointerCapture(e.pointerId)});
frame.addEventListener('pointermove',e=>{if(drag){x=e.clientX-sx;y=e.clientY-sy;apply()}});
const stop=()=>{drag=false;frame.classList.remove('dragging')};frame.addEventListener('pointerup',stop);frame.addEventListener('pointercancel',stop);
function currentSvg(){return diagram.querySelector('svg')}
document.getElementById('download-svg').onclick=()=>{const svg=currentSvg();if(!svg)return;const blob=new Blob([new XMLSerializer().serializeToString(svg)],{type:'image/svg+xml'});const a=document.createElement('a');a.href=URL.createObjectURL(blob);a.download=`zentrip-${pages[active].title.toLowerCase().replace(/[^a-z0-9]+/g,'-')}.svg`;a.click();URL.revokeObjectURL(a.href)};
document.getElementById('download-png').onclick=()=>{const svg=currentSvg();if(!svg)return;const clone=svg.cloneNode(true),vb=svg.viewBox.baseVal,w=Math.ceil(vb.width*3),h=Math.ceil(vb.height*3);clone.setAttribute('width',w);clone.setAttribute('height',h);const blob=new Blob([new XMLSerializer().serializeToString(clone)],{type:'image/svg+xml'}),url=URL.createObjectURL(blob),img=new Image();img.onload=()=>{const canvas=document.createElement('canvas');canvas.width=w;canvas.height=h;canvas.getContext('2d').drawImage(img,0,0,w,h);canvas.toBlob(png=>{const a=document.createElement('a');a.href=URL.createObjectURL(png);a.download=`zentrip-page-${active+1}.png`;a.click();URL.revokeObjectURL(a.href);URL.revokeObjectURL(url)},'image/png')};img.onerror=()=>{statusEl.textContent='PNG export failed for this diagram.';URL.revokeObjectURL(url)};img.src=url};
showPage(0);
</script></body></html>"""
    return (
        template
        .replace("__PAGE_BUTTONS__", page_buttons)
        .replace("__PAGE_DATA__", page_payload)
    )


def word_run(text, size=22, bold=False, color=None):
    props = f'<w:rPr><w:sz w:val="{size}"/><w:szCs w:val="{size}"/>'
    if bold:
        props += "<w:b/>"
    if color:
        props += f'<w:color w:val="{color}"/>'
    props += "</w:rPr>"
    return f'<w:r>{props}<w:t xml:space="preserve">{html.escape(text)}</w:t></w:r>'


def word_p(text, style=None, size=22, bold=False, color=None):
    ppr = f'<w:pPr><w:pStyle w:val="{style}"/></w:pPr>' if style else ""
    return f"<w:p>{ppr}{word_run(text, size, bold, color)}</w:p>"


def build_docx_legacy(pages, svgs, pngs):
    image_width_in = 15.3
    image_height_in = image_width_in * HEIGHT / WIDTH
    cx, cy = round(image_width_in * 914400), round(image_height_in * 914400)
    relationships = []
    content = []
    for i, (p, svg, png) in enumerate(zip(pages, svgs, pngs)):
        png_id = f"rIdP{i+1}"
        svg_id = f"rIdS{i+1}"
        relationships += [
            f'<Relationship Id="{png_id}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" Target="media/diagram-{i+1}.png"/>',
            f'<Relationship Id="{svg_id}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" Target="media/diagram-{i+1}.svg"/>',
        ]
        content.append(word_p(p["title"], "Title", 32, True))
        content.append(word_p(p["subtitle"], size=20, color="62756D"))
        content.append(f'''<w:p><w:pPr><w:jc w:val="center"/></w:pPr><w:r><w:drawing><wp:inline distT="0" distB="0" distL="0" distR="0">
<wp:extent cx="{cx}" cy="{cy}"/><wp:effectExtent t="0" r="0" b="0" l="0"/>
<wp:docPr id="{i+1}" name="{html.escape(p["title"])}" descr="SVG vector activity diagram."/>
<wp:cNvGraphicFramePr><a:graphicFrameLocks noChangeAspect="1"/></wp:cNvGraphicFramePr>
<a:graphic><a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/picture"><pic:pic>
<pic:nvPicPr><pic:cNvPr id="0" name="{html.escape(p["id"])}"/><pic:cNvPicPr><a:picLocks noChangeAspect="1"/></pic:cNvPicPr></pic:nvPicPr>
<pic:blipFill><a:blip r:embed="{png_id}"><a:extLst><a:ext uri="{{96DAC541-7B7A-43D3-8B79-37D633B846F1}}"><asvg:svgBlip xmlns:asvg="http://schemas.microsoft.com/office/drawing/2016/SVG/main" r:embed="{svg_id}"/></a:ext></a:extLst></a:blip><a:srcRect/><a:stretch><a:fillRect/></a:stretch></pic:blipFill>
<pic:spPr bwMode="auto"><a:xfrm><a:off x="0" y="0"/><a:ext cx="{cx}" cy="{cy}"/></a:xfrm><a:prstGeom prst="rect"><a:avLst/></a:prstGeom></pic:spPr>
</pic:pic></a:graphicData></a:graphic></wp:inline></w:drawing></w:r></w:p>''')
        content.append(word_p(p["note"], size=18, color="62756D"))
        if i < len(pages)-1:
            content.append('<w:p><w:r><w:br w:type="page"/></w:r></w:p>')

    document = f'''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing" xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture" xmlns:mc="http://schemas.openxmlformats.org/markup-compatibility/2006"><w:body>
{"".join(content)}
<w:sectPr><w:pgSz w:w="23811" w:h="16838" w:orient="landscape"/><w:pgMar w:top="400" w:right="400" w:bottom="400" w:left="400" w:header="200" w:footer="200" w:gutter="0"/></w:sectPr>
</w:body></w:document>'''
    ctype_defaults = '''<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Default Extension="svg" ContentType="image/svg+xml"/><Default Extension="png" ContentType="image/png"/>'''
    types = f'''<?xml version="1.0" encoding="UTF-8"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">{ctype_defaults}<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/><Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/><Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/><Override PartName="/docProps/app.xml" ContentType="application/vnd.openxmlformats-officedocument.extended-properties+xml"/></Types>'''
    root_rels = '''<?xml version="1.0" encoding="UTF-8"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/><Relationship Id="rId2" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="docProps/core.xml"/><Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/extended-properties" Target="docProps/app.xml"/></Relationships>'''
    rels = f'''<?xml version="1.0" encoding="UTF-8"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">{"".join(relationships)}</Relationships>'''
    styles = '''<?xml version="1.0" encoding="UTF-8"?><w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:style w:type="paragraph" w:default="1" w:styleId="Normal"><w:name w:val="Normal"/><w:rPr><w:rFonts w:ascii="Arial" w:hAnsi="Arial"/><w:sz w:val="22"/></w:rPr></w:style><w:style w:type="paragraph" w:styleId="Title"><w:name w:val="Title"/><w:basedOn w:val="Normal"/><w:pPr><w:jc w:val="center"/><w:spacing w:after="90"/></w:pPr><w:rPr><w:rFonts w:ascii="Arial" w:hAnsi="Arial"/><w:color w:val="263A33"/><w:b/><w:sz w:val="32"/></w:rPr></w:style></w:styles>'''
    core = '''<?xml version="1.0" encoding="UTF-8"?><cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:title>ZenTrip Verified Activity Flows</dc:title><dc:subject>Role routing, travel bookings, AI, and persistence</dc:subject><dc:creator>ZenTrip</dc:creator></cp:coreProperties>'''
    app = '''<?xml version="1.0" encoding="UTF-8"?><Properties xmlns="http://schemas.openxmlformats.org/officeDocument/2006/extended-properties"><Application>Microsoft Word</Application></Properties>'''
    OUT.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(WORD_PATH, "w", zipfile.ZIP_DEFLATED) as zf:
        zf.writestr("[Content_Types].xml", types)
        zf.writestr("_rels/.rels", root_rels)
        zf.writestr("word/document.xml", document)
        zf.writestr("word/_rels/document.xml.rels", rels)
        zf.writestr("word/styles.xml", styles)
        zf.writestr("docProps/core.xml", core)
        zf.writestr("docProps/app.xml", app)
        for i, (svg, png) in enumerate(zip(svgs, pngs), 1):
            zf.writestr(f"word/media/diagram-{i}.svg", svg.encode("utf-8"))
            zf.writestr(f"word/media/diagram-{i}.png", png)


def main():
    validate_pages()
    OUT.mkdir(parents=True, exist_ok=True)
    magick = shutil.which("magick")
    if not magick:
        raise RuntimeError("ImageMagick is required to render the diagram PNG exports.")
    for p in PAGES:
        svg = build_svg(p)
        svg_path = OUT / f"zentrip-activity-{p['id']}.svg"
        png_path = OUT / f"zentrip-activity-{p['id']}.png"
        word_png_path = OUT / f"zentrip-activity-{p['id']}-word.png"
        svg_path.write_text(svg, encoding="utf-8")
        subprocess.run(
            [magick, "-background", "white", "-density", "120", str(svg_path),
             "-resize", f"{WIDTH}x{HEIGHT}!", str(png_path)],
            check=True,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.PIPE,
            timeout=90,
        )
        subprocess.run(
            [magick, "-background", "white", "-density", "240", str(svg_path),
             "-resize", f"{WIDTH*2}x{HEIGHT*2}!", str(word_png_path)],
            check=True,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.PIPE,
            timeout=120,
        )
        print(f"Generated {svg_path.relative_to(ROOT)}")
    html_path = OUT / "zentrip-activity-diagram.html"
    html_path.write_text(build_html(PAGES), encoding="utf-8")
    subprocess.run(
        ["node", str(ROOT / "scripts" / "build-zentrip-activity-docx.cjs")],
        cwd=ROOT,
        check=True,
    )
    print(f"Generated {html_path.relative_to(ROOT)}")
    print(f"Generated {WORD_PATH.relative_to(ROOT)}")
    print(f"Pages: {len(PAGES)}; orthogonal connectors: {sum(len(p['edges']) for p in PAGES)}")


if __name__ == "__main__":
    main()
