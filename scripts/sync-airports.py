#!/usr/bin/env python3
"""Import scheduled-service airports from the public-domain OurAirports data."""

from __future__ import annotations

import argparse
import csv
import io
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path
from urllib.parse import parse_qs, unquote, urlsplit
from urllib.request import Request, urlopen

DATA_ROOT = "https://ourairports.com/data"
AIRPORT_TYPES = {"large_airport", "medium_airport", "small_airport"}
IATA_CODE = re.compile(r"^[A-Z]{3}$")
ICAO_CODE = re.compile(r"^[A-Z]{4}$")
CSV_FIELDS = [
    "source_id",
    "code",
    "icao_code",
    "city",
    "airport_name",
    "country",
    "region",
    "latitude",
    "longitude",
    "airport_type",
    "is_major",
    "iso_country",
    "keywords",
    "wikipedia_link",
]

SCHEMA_AND_COPY = """
BEGIN;
ALTER TABLE public.airports ADD COLUMN IF NOT EXISTS icao_code CHAR(4);
ALTER TABLE public.airports ADD COLUMN IF NOT EXISTS latitude DOUBLE PRECISION;
ALTER TABLE public.airports ADD COLUMN IF NOT EXISTS longitude DOUBLE PRECISION;
ALTER TABLE public.airports ADD COLUMN IF NOT EXISTS airport_type VARCHAR(32) NOT NULL DEFAULT 'medium_airport';
ALTER TABLE public.airports ADD COLUMN IF NOT EXISTS is_major BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE public.airports ADD COLUMN IF NOT EXISTS scheduled_service BOOLEAN NOT NULL DEFAULT TRUE;
ALTER TABLE public.airports ADD COLUMN IF NOT EXISTS iso_country CHAR(2);
ALTER TABLE public.airports ADD COLUMN IF NOT EXISTS keywords TEXT NOT NULL DEFAULT '';
ALTER TABLE public.airports ADD COLUMN IF NOT EXISTS wikipedia_link VARCHAR(2048);
ALTER TABLE public.airports ADD COLUMN IF NOT EXISTS source_id BIGINT;
ALTER TABLE public.airports ADD COLUMN IF NOT EXISTS source_provider VARCHAR(32) NOT NULL DEFAULT 'legacy';
ALTER TABLE public.airports ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW();
CREATE INDEX IF NOT EXISTS airports_icao_code_index ON public.airports (icao_code);
CREATE INDEX IF NOT EXISTS airports_country_city_index ON public.airports (iso_country, city);
CREATE INDEX IF NOT EXISTS airports_city_search_index ON public.airports (LOWER(city));
CREATE INDEX IF NOT EXISTS airports_country_search_index ON public.airports (LOWER(country));
CREATE INDEX IF NOT EXISTS airports_name_search_index ON public.airports (LOWER(airport_name));
CREATE INDEX IF NOT EXISTS airports_coordinates_index ON public.airports (latitude, longitude)
    WHERE latitude IS NOT NULL AND longitude IS NOT NULL;
CREATE TEMP TABLE airport_import_stage (
    source_id BIGINT NOT NULL,
    code CHAR(3) NOT NULL,
    icao_code CHAR(4) NOT NULL,
    city TEXT NOT NULL,
    airport_name TEXT NOT NULL,
    country TEXT NOT NULL,
    region TEXT NOT NULL,
    latitude DOUBLE PRECISION NOT NULL,
    longitude DOUBLE PRECISION NOT NULL,
    airport_type TEXT NOT NULL,
    is_major BOOLEAN NOT NULL,
    iso_country CHAR(2) NOT NULL,
    keywords TEXT NOT NULL,
    wikipedia_link TEXT
) ON COMMIT DROP;
\\copy airport_import_stage ({copy_fields}) FROM '{csv_path}' WITH (FORMAT csv, HEADER true)
INSERT INTO public.airports (
    code, icao_code, city, airport_name, country, region, latitude, longitude,
    airport_type, is_major, scheduled_service, iso_country, keywords,
    wikipedia_link, source_id, source_provider, updated_at
)
SELECT
    code, icao_code, city, airport_name, country, region, latitude, longitude,
    airport_type, is_major, TRUE, iso_country, keywords, wikipedia_link,
    source_id, 'OurAirports', NOW()
FROM airport_import_stage
ON CONFLICT (code) DO UPDATE SET
    icao_code = EXCLUDED.icao_code,
    city = EXCLUDED.city,
    airport_name = EXCLUDED.airport_name,
    country = EXCLUDED.country,
    region = EXCLUDED.region,
    latitude = EXCLUDED.latitude,
    longitude = EXCLUDED.longitude,
    airport_type = EXCLUDED.airport_type,
    is_major = EXCLUDED.is_major,
    scheduled_service = EXCLUDED.scheduled_service,
    iso_country = EXCLUDED.iso_country,
    keywords = EXCLUDED.keywords,
    wikipedia_link = EXCLUDED.wikipedia_link,
    source_id = EXCLUDED.source_id,
    source_provider = EXCLUDED.source_provider,
    updated_at = NOW();
SELECT 'airport_rows_upserted=' || COUNT(*) FROM airport_import_stage;
COMMIT;
"""


def download_csv(filename: str) -> list[dict[str, str]]:
    request = Request(
        f"{DATA_ROOT}/{filename}",
        headers={"User-Agent": "Zentrip-airport-directory-sync/1.0"},
    )
    with urlopen(request, timeout=60) as response:
        reader = csv.DictReader(
            io.TextIOWrapper(response, encoding="utf-8-sig", newline="")
        )
        return list(reader)


def build_airports() -> list[dict[str, str]]:
    countries = {row["code"].upper(): row["name"] for row in download_csv("countries.csv")}
    regions = {row["code"].upper(): row["name"] for row in download_csv("regions.csv")}
    selected: dict[str, dict[str, str]] = {}
    priority = {"small_airport": 1, "medium_airport": 2, "large_airport": 3}

    for row in download_csv("airports.csv"):
        airport_type = (row.get("type") or "").strip().lower()
        if row.get("scheduled_service", "").strip().lower() != "yes":
            continue
        if airport_type not in AIRPORT_TYPES:
            continue

        code = (row.get("iata_code") or "").strip().upper()
        icao_code = (row.get("icao_code") or "").strip().upper()
        iso_country = (row.get("iso_country") or "").strip().upper()
        city = (row.get("municipality") or "").strip()
        name = (row.get("name") or "").strip()
        country = countries.get(iso_country, "")
        try:
            latitude = float(row["latitude_deg"])
            longitude = float(row["longitude_deg"])
            source_id = int(row["id"])
        except (KeyError, TypeError, ValueError):
            continue

        if not IATA_CODE.fullmatch(code) or not ICAO_CODE.fullmatch(icao_code):
            continue
        if not city or not name or not country or len(iso_country) != 2:
            continue
        if not (-90 <= latitude <= 90 and -180 <= longitude <= 180):
            continue

        region_code = (row.get("iso_region") or "").strip().upper()
        airport = {
            "source_id": str(source_id),
            "code": code,
            "icao_code": icao_code,
            "city": city,
            "airport_name": name,
            "country": country,
            "region": regions.get(region_code, region_code),
            "latitude": str(latitude),
            "longitude": str(longitude),
            "airport_type": airport_type,
            "is_major": "true" if airport_type == "large_airport" else "false",
            "iso_country": iso_country,
            "keywords": (row.get("keywords") or "").strip(),
            "wikipedia_link": (row.get("wikipedia_link") or "").strip(),
        }
        existing = selected.get(code)
        if existing is None or priority[airport_type] > priority[existing["airport_type"]]:
            selected[code] = airport

    return sorted(
        selected.values(),
        key=lambda airport: (airport["country"], airport["city"], airport["code"]),
    )


def pg_environment() -> dict[str, str]:
    raw_url = os.environ.get("SUPABASE_DB_URL", "").strip()
    if not raw_url:
        raise RuntimeError("SUPABASE_DB_URL is not configured.")
    if raw_url.startswith("jdbc:"):
        raw_url = raw_url[5:]

    parsed = urlsplit(raw_url)
    if parsed.scheme not in {"postgres", "postgresql"} or not parsed.hostname:
        raise RuntimeError("SUPABASE_DB_URL must be a PostgreSQL URI or JDBC URI.")

    environment = os.environ.copy()
    environment["PGHOST"] = parsed.hostname
    environment["PGPORT"] = str(parsed.port or 5432)
    environment["PGUSER"] = (
        environment.get("SUPABASE_DB_USER")
        or unquote(parsed.username or "")
        or "postgres"
    )
    password = unquote(parsed.password or "") or environment.get("SUPABASE_DB_PASSWORD", "")
    if password:
        environment["PGPASSWORD"] = password
    environment["PGDATABASE"] = unquote(parsed.path.lstrip("/")) or "postgres"
    parameters = parse_qs(parsed.query)
    environment["PGSSLMODE"] = parameters.get("sslmode", ["require"])[0]
    environment["PGAPPNAME"] = "zentrip-airport-directory-sync"
    return environment


def apply_import(airports: list[dict[str, str]]) -> None:
    psql = shutil.which("psql")
    if not psql:
        raise RuntimeError("psql is required to apply the airport directory.")

    with tempfile.TemporaryDirectory(prefix="zentrip-airports-") as temporary:
        csv_path = Path(temporary) / "airports.csv"
        with csv_path.open("w", encoding="utf-8", newline="") as output:
            writer = csv.DictWriter(output, fieldnames=CSV_FIELDS)
            writer.writeheader()
            writer.writerows(airports)

        sql = SCHEMA_AND_COPY.format(
            copy_fields=", ".join(CSV_FIELDS),
            csv_path=str(csv_path).replace("\\", "\\\\").replace("'", "''"),
        )
        result = subprocess.run(
            [psql, "-X", "-v", "ON_ERROR_STOP=1", "-q", "-f", "-"],
            input=sql,
            text=True,
            capture_output=True,
            env=pg_environment(),
            check=False,
        )
        if result.returncode != 0:
            error = result.stderr.lower()
            if "password authentication failed" in error:
                reason = "database authentication was rejected"
            elif "no password supplied" in error:
                reason = "database password is unavailable to the process"
            elif "could not translate host name" in error or "name or service not known" in error:
                reason = "database hostname could not be resolved"
            elif "connection timed out" in error or "timeout expired" in error:
                reason = "database connection timed out"
            elif "connection refused" in error:
                reason = "database connection was refused"
            elif "does not exist" in error and "database" in error:
                reason = "database name was not found"
            elif "permission denied" in error:
                reason = "database role lacks permission for the additive import"
            else:
                reason = "PostgreSQL rejected the import; sensitive diagnostics were suppressed"
            raise RuntimeError(
                f"The PostgreSQL airport import failed: {reason}."
            )
        if result.stdout.strip():
            print(result.stdout.strip())


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--apply",
        action="store_true",
        help="apply the additive schema and upsert the downloaded directory",
    )
    args = parser.parse_args()

    airports = build_airports()
    if not airports:
        raise RuntimeError("The source returned no complete scheduled-service airports.")
    countries = len({airport["iso_country"] for airport in airports})
    print(
        f"Prepared {len(airports)} airports across {countries} countries "
        "with verified IATA, ICAO, city, and coordinate fields."
    )
    if not args.apply:
        print("Dry run only. Re-run with --apply to upsert the directory.")
        return 0

    apply_import(airports)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as error:
        print(f"Airport directory sync failed: {error}", file=sys.stderr)
        raise SystemExit(1)
