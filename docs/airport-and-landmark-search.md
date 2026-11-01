# Global airport and landmark search

## Data sources and coverage

- **Airport directory:** OurAirports public-domain CSV data. The import accepts only airports marked for scheduled service with a valid three-letter IATA code, four-letter ICAO code, municipality, country, and coordinates. `large_airport` is marked major; medium and small airports are marked minor. The source is updated nightly and explicitly carries no accuracy guarantee.
- **Place geocoding and POIs:** Geoapify Places, backed by OpenStreetMap. Place results include Geoapify/OpenStreetMap attribution.
- **Images and deep metadata:** Wikidata/Wikipedia enrichment. Image links are returned only when a Wikidata or English Wikipedia image property points to Wikimedia Commons. A landmark without a verifiable image remains without a photo; the app must not substitute a fabricated image.

The directory is intentionally strict about fields required by the booking picker. The import excludes records that lack an IATA/ICAO code, coordinates, city, or country rather than inventing those values. A source snapshot checked on 2026-11-01 contained 3,858 qualifying airports across 233 countries. Counts change as OurAirports data changes.

OurAirports lists airport locations; it does not provide schedules, fares, or bookable inventory. Zentrip's flight results still come from partner listings. Actual global flight offers and ticketing require a separate airline/GDS provider such as Amadeus and its own credentials, commercial terms, and booking workflow.

## Refreshing Supabase

`python3 scripts/sync-airports.py` downloads the current source files and validates the number of rows without changing the database. After reviewing the dry-run output, `python3 scripts/sync-airports.py --apply` applies the additive airport columns/indexes and upserts rows by IATA code. It never deletes existing rows. It uses the configured Supabase connection from Replit Secrets; credentials are not accepted on the command line or printed.

The API retains a legacy-column fallback if the additive migration has not been applied. The live import does not replace existing application tables or perform a full schema initialization.

## Search endpoint

`GET /api/airports/search?query={text}` returns a structured response:

```json
{
  "query": "London",
  "query_type": "city",
  "airports": [
    {
      "code": "LHR",
      "icao_code": "EGLL",
      "city": "London",
      "airport_name": "Heathrow Airport",
      "country": "United Kingdom",
      "iso_country": "GB",
      "latitude": 51.47,
      "longitude": -0.4543,
      "airport_type": "large_airport",
      "is_major": true,
      "priority": "major",
      "scheduled_service": true,
      "distance_km": null
    }
  ],
  "landmarks": [],
  "total": 1,
  "has_more": false,
  "airport_attribution": "OurAirports public-domain airport data",
  "landmark_attribution": "Geoapify · © OpenStreetMap contributors"
}
```

### JSON Schema (normalized objects)

Airport objects use this normalized shape; `distance_km` appears when the airport is suggested for a geocoded place:

```json
{
  "type": "object",
  "required": [
    "code", "icao_code", "city", "airport_name", "country",
    "latitude", "longitude", "airport_type", "is_major", "scheduled_service"
  ],
  "properties": {
    "code": { "type": "string", "pattern": "^[A-Z]{3}$" },
    "icao_code": { "type": "string", "pattern": "^[A-Z0-9]{4}$" },
    "city": { "type": "string" },
    "airport_name": { "type": "string" },
    "country": { "type": "string" },
    "iso_country": { "type": "string", "minLength": 2, "maxLength": 2 },
    "region": { "type": "string" },
    "latitude": { "type": "number", "minimum": -90, "maximum": 90 },
    "longitude": { "type": "number", "minimum": -180, "maximum": 180 },
    "airport_type": {
      "type": "string",
      "enum": ["large_airport", "medium_airport", "small_airport"]
    },
    "is_major": { "type": "boolean" },
    "priority": { "type": "string", "enum": ["major", "minor"] },
    "scheduled_service": { "type": "boolean" },
    "keywords": { "type": "string" },
    "wikipedia_link": { "type": ["string", "null"], "format": "uri" },
    "source_provider": { "type": "string" },
    "distance_km": { "type": ["number", "null"], "minimum": 0 }
  }
}
```

Landmark suggestion objects use:

```json
{
  "type": "object",
  "required": ["name", "latitude", "longitude", "highlight_category"],
  "properties": {
    "name": { "type": "string" },
    "city": { "type": "string" },
    "country": { "type": "string" },
    "latitude": { "type": "number" },
    "longitude": { "type": "number" },
    "category": { "type": "string" },
    "highlight_category": {
      "type": "string",
      "enum": ["Historical", "Nature", "Shopping", "Architecture", "Family & Culture"]
    },
    "image_url": { "type": ["string", "null"], "format": "uri" },
    "image_source": { "type": ["string", "null"] },
    "wikipedia_url": { "type": ["string", "null"], "format": "uri" },
    "source_attribution": { "type": "string" },
    "nearest_airport": { "type": ["object", "null"] }
  }
}
```

## Matching behavior

1. Exact IATA or ICAO code returns that airport first.
2. Exact country name or ISO country code returns that country's scheduled-service airports, major hubs first.
3. Exact city (optionally `City, Country`) returns all matching airports, major hubs first, plus photo-backed landmark suggestions when available.
4. Airport names, city names, country names, and source keywords are searched as text.
5. If there is no airport-directory match, Geoapify geocodes the text. The API calculates the nearest scheduled-service airports with the Haversine distance formula and includes a matching photo-backed landmark when one is verified.
6. Category queries use `Historical in Cairo, Egypt`, `Nature in Bali, Indonesia`, `Shopping in London`, `Architecture in Paris`, or `Family & Culture in Rome`. A category without a place asks the user to add a city/place.

Search results are suggestions only. Selecting an airport does not imply that a partner flight or airline schedule exists for it.

## Provider requests

Geoapify airport/place lookup uses the configured server-side key. Do not expose it in Flutter code:

```http
GET https://api.geoapify.com/v1/geocode/search?text=Eiffel%20Tower&format=json&apiKey={server-side-key}
GET https://api.geoapify.com/v2/places?categories=tourism.sights,tourism.attraction&filter=circle:2.2945,48.8584,5000&limit=20&apiKey={server-side-key}
```

Wikidata image and bilingual metadata are optional enrichments. A failed or empty Wikidata response does not invalidate airport search; image fields stay null rather than being guessed.
