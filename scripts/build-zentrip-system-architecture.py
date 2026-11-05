#!/usr/bin/env python3
"""Build a readable, standalone architecture overview from verified project facts."""

from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "docs" / "zentrip_system_architecture.mmd"
OUTPUT = ROOT / "generated-artifacts"
HTML_PATH = OUTPUT / "ZenTrip-System-Architecture.html"
STALE_SVG_PATH = OUTPUT / "ZenTrip-System-Architecture.svg"
if not SOURCE.is_file():
    raise SystemExit(f"Architecture source is missing: {SOURCE}")

HTML = """<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Zentrip System Architecture</title>
  <style>
    :root {
      color-scheme: light;
      font-family: Inter, "Segoe UI", Arial, sans-serif;
      color: #172b3a;
      background: #f3f6f9;
    }
    * { box-sizing: border-box; }
    body { margin: 0; }
    main { max-width: 1680px; margin: auto; padding: 34px; }
    header { margin-bottom: 22px; }
    h1 { margin: 0 0 8px; font-size: clamp(26px, 3vw, 40px); letter-spacing: -.025em; }
    header p { max-width: 940px; margin: 0; color: #506474; font-size: 16px; line-height: 1.55; }
    .badge { display: inline-block; margin-bottom: 12px; padding: 5px 10px; border-radius: 999px; background: #e4eee9; color: #2e6048; font-size: 12px; font-weight: 700; letter-spacing: .06em; text-transform: uppercase; }
    .diagram { display: grid; grid-template-columns: minmax(250px, 1fr) 76px minmax(340px, 1.25fr) 76px minmax(260px, 1fr); align-items: stretch; gap: 14px; }
    .layer { padding: 20px; border: 1px solid #d4dee7; border-radius: 16px; background: #fff; box-shadow: 0 8px 22px rgb(24 48 68 / 5%); }
    .client { border-top: 5px solid #547aa0; }
    .backend { border-top: 5px solid #665d9a; }
    .providers { border-top: 5px solid #b48b3f; }
    .layer h2 { margin: 2px 0 5px; font-size: 21px; }
    .subtitle { margin: 0 0 16px; color: #627586; font-size: 13px; line-height: 1.45; }
    .eyebrow { color: #64798b; font-size: 11px; font-weight: 800; letter-spacing: .09em; text-transform: uppercase; }
    .stack { display: grid; gap: 10px; }
    .box { padding: 12px 13px; border: 1px solid #dae3eb; border-radius: 11px; background: #f8fafc; line-height: 1.42; }
    .box strong { display: block; margin-bottom: 4px; font-size: 14px; }
    .box p { margin: 0; color: #556a7b; font-size: 12.5px; }
    .box.primary { border-color: #a8bdd4; background: #f0f5fb; }
    .box.security { border-color: #c5c0df; background: #f5f4fa; }
    .box.simulator { border-color: #dfc9aa; background: #fff9f0; }
    .box.local { border-color: #bdd6c7; background: #f2f8f4; }
    .connector { display: flex; flex-direction: column; align-items: center; justify-content: center; gap: 9px; color: #47677b; text-align: center; }
    .connector span { font-size: 11px; line-height: 1.35; }
    .connector b { font-size: 35px; font-weight: 400; line-height: 1; }
    .providers-list { display: grid; gap: 8px; }
    .provider { padding: 10px 11px; border: 1px solid #e8dfc9; border-radius: 10px; background: #fffdf8; }
    .provider strong { display: inline-block; margin-right: 5px; font-size: 13px; }
    .provider p { margin: 3px 0 0; color: #667580; font-size: 12px; line-height: 1.35; }
    .tag { display: inline-block; padding: 2px 6px; border-radius: 999px; background: #f4eddd; color: #725a2e; font-size: 10px; font-weight: 700; }
    .client-tag { background: #eaf0f6; color: #45677f; }
    .database-flow { grid-column: 3; display: flex; flex-direction: column; align-items: center; padding: 0 0 1px; color: #3f7777; text-align: center; }
    .database-flow span { font-size: 12px; font-weight: 650; }
    .database-flow b { margin-top: 3px; font-size: 31px; font-weight: 400; line-height: 1; }
    .database { grid-column: 1 / -1; display: grid; grid-template-columns: 1fr 1fr; gap: 20px; align-items: center; border-top: 5px solid #4f8b89; background: #f7fbfb; }
    .database h2 { margin: 3px 0 8px; }
    .tables { display: flex; flex-wrap: wrap; gap: 7px; }
    .tables span { padding: 6px 9px; border: 1px solid #cde0df; border-radius: 8px; background: #fff; color: #315c5a; font-size: 12px; }
    .boundary { padding: 14px 16px; border: 1px solid #d6e1e8; border-radius: 11px; background: #fff; color: #465c6c; font-size: 13px; line-height: 1.5; }
    .notes { display: grid; grid-template-columns: repeat(3, minmax(0, 1fr)); gap: 12px; margin-top: 16px; }
    .note { padding: 15px 16px; border: 1px solid #d7e0e8; border-radius: 12px; background: #fff; color: #506474; font-size: 13px; line-height: 1.5; }
    .note strong { display: block; margin-bottom: 5px; color: #20394b; }
    .legend { display: flex; flex-wrap: wrap; gap: 10px 20px; margin-top: 16px; color: #627586; font-size: 12px; }
    @media (max-width: 1050px) {
      main { padding: 22px; }
      .diagram { grid-template-columns: minmax(0, 1fr) 54px minmax(0, 1.1fr); }
      .providers { grid-column: 1 / -1; }
      .providers-list { grid-template-columns: repeat(2, minmax(0, 1fr)); }
      .database-flow { grid-column: 2; grid-row: 2; }
      .database { grid-column: 1 / -1; }
      .notes { grid-template-columns: 1fr; }
    }
    @media (max-width: 660px) {
      main { padding: 16px; }
      .diagram { display: flex; flex-direction: column; }
      .connector { min-height: 64px; }
      .connector b { transform: rotate(90deg); }
      .providers-list { grid-template-columns: 1fr; }
      .database-flow { order: 4; }
      .database { display: block; }
      .database .boundary { margin-top: 14px; }
    }
    @media print {
      :root { background: #fff; }
      main { max-width: none; padding: 12px; }
      .layer { box-shadow: none; break-inside: avoid; }
      .diagram { grid-template-columns: minmax(220px, 1fr) 55px minmax(300px, 1.2fr) 55px minmax(230px, 1fr); }
      .providers-list { display: grid; grid-template-columns: 1fr; }
      .notes { grid-template-columns: repeat(3, 1fr); }
    }
  </style>
</head>
<body>
<main>
  <header><span class="badge">Current implementation</span>
    <h1>Zentrip System Architecture</h1>
    <p>Flutter web and mobile clients connect to the Spring Boot API. The backend enforces access, combines partner and provider data, and persists supported records in Supabase PostgreSQL. Provider credentials stay on the server.</p>
  </header>
  <section class="diagram" aria-label="System architecture">
    <article class="layer client">
      <span class="eyebrow">01 · Client</span><h2>Flutter app</h2>
      <p class="subtitle">Web and mobile · English/Arabic · role-specific navigation</p>
      <div class="stack">
        <div class="box"><strong>People and screens</strong><p>Customers: explore, flights, hotels, attractions, cars, transfers, trips, profile, Zen AI. Admins and partners: their own dashboards.</p></div>
        <div class="box"><strong>Feature controllers and models</strong><p>Feature-first modules normalize API results for the UI.</p></div>
        <div class="box primary"><strong>Shared ApiService · Dio</strong><p>Calls the /api contract with a bearer token. AI chat uses a streamed response.</p></div>
        <div class="box local"><strong>Device-local state</strong><p>Saved session and selected preferences; favorites, notifications, and some chat history are local.</p></div>
      </div>
    </article>
    <div class="connector" aria-label="Client to backend"><span>REST / JSON<br>Bearer token<br>AI stream</span><b>→</b></div>
    <article class="layer backend">
      <span class="eyebrow">02 · Application services</span><h2>Spring Boot API</h2>
      <p class="subtitle">Spring Boot 3.5 · Java 25 · central application boundary</p>
      <div class="stack">
        <div class="box primary"><strong>API entry · /api</strong><p>Receives app requests and returns normalized responses.</p></div>
        <div class="box security"><strong>Authentication and authorization</strong><p>Validates the bearer token; loads user role and partner identity from server records. Partner ownership is checked server-side.</p></div>
        <div class="box"><strong>REST controllers</strong><p>Core API · Partner · Admin · AI chat · travel preferences · exchange rates.</p></div>
        <div class="box"><strong>Domain services and adapters</strong><p>Flight/hotel inventory merge · airports/geocoding · attractions/maps · AI · pricing.</p></div>
        <div class="box simulator"><strong>Payment simulator</strong><p>Creates mock checkout sessions; success is not a real payment or supplier reservation.</p></div>
        <div class="box"><strong>Persistence boundary</strong><p>JDBC/JPA transactions, owner-scoped operations, and request-scoped RLS role context.</p></div>
      </div>
    </article>
    <div class="connector" aria-label="Backend to providers"><span>Server-to-server<br>search and data<br>lookups</span><b>⇄</b></div>
    <article class="layer providers">
      <span class="eyebrow">03 · Integrations</span><h2>External services</h2>
      <p class="subtitle">Keys configured as backend environment secrets</p>
      <div class="providers-list">
        <div class="provider"><strong>Duffel</strong><span class="tag">read-only</span><p>Flight offers; no airline order creation.</p></div>
        <div class="provider"><strong>LiteAPI</strong><span class="tag">read-only</span><p>Hotel data and rates; no provider booking.</p></div>
        <div class="provider"><strong>OpenTripMap</strong><p>Tourist place search, suggestions, and details.</p></div>
        <div class="provider"><strong>Geoapify</strong><p>Geocoding and airport lookup fallback.</p></div>
        <div class="provider"><strong>SerpAPI</strong><p>Nearby and map search.</p></div>
        <div class="provider"><strong>Requesty</strong><p>Zen AI response stream.</p></div>
        <div class="provider"><strong>Frankfurter</strong><p>Exchange-rate lookup.</p></div>
        <div class="provider"><strong>Optional jobs</strong><p>Google Places rating sync; OurAirports data import.</p></div>
        <div class="provider"><strong>OpenStreetMap</strong><span class="tag client-tag">client direct</span><p>Map tiles requested by the Flutter map client.</p></div>
      </div>
    </article>
    <div class="database-flow"><span>Spring data access · JDBC/JPA · scoped reads and writes</span><b>↓</b></div>
    <article class="layer database">
      <div><span class="eyebrow">04 · Persistent storage</span><h2>Supabase PostgreSQL</h2>
        <div class="tables"><span>users / api_tokens</span><span>partner inventory</span><span>trips</span><span>bookings</span><span>transfers</span><span>offers</span><span>places</span><span>AI chat messages</span><span>preferences</span></div>
      </div>
      <div class="boundary"><strong>Trust boundary:</strong> the Flutter app does not query Supabase directly. The backend verifies the session and applies role/ownership rules. PostgreSQL row-level security provides an additional database layer.</div>
    </article>
  </section>
  <section class="notes" aria-label="Important architecture boundaries">
    <div class="note"><strong>Search is not supplier booking</strong>Duffel supplies flight offers and LiteAPI supplies hotel data/rates. Zentrip does not create orders with either provider.</div>
    <div class="note"><strong>Checkout is simulated</strong>Payment sessions are mock sessions. Zentrip stores supported trip, booking, and transfer records; it does not process a real card charge.</div>
    <div class="note"><strong>Push delivery is not active</strong>FCM token registration exists, but push delivery still requires Firebase client and server configuration.</div>
  </section>
  <div class="legend" aria-label="Diagram legend"><span>→ app/API and persistence flow</span><span>⇄ provider data request/response</span><span>Amber panels identify external data services</span></div>
</main>
</body>
</html>"""


def main() -> None:
    source = SOURCE.read_text(encoding="utf-8")
    if "Duffel" not in source or "Supabase PostgreSQL" not in source:
        raise SystemExit("Architecture source is missing a required system boundary.")
    OUTPUT.mkdir(parents=True, exist_ok=True)
    STALE_SVG_PATH.unlink(missing_ok=True)
    HTML_PATH.write_text(HTML, encoding="utf-8")
    print(f"Rendered {HTML_PATH.relative_to(ROOT)}")
    print(f"Mermaid source: {SOURCE.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
