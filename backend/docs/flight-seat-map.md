# Flight seat-map contract

`GET /api/flights/{flightId}/seats` requires the existing customer authentication.
It reads a consistent, read-only inventory snapshot; it does not reserve seats.
The existing reservation and booking-confirmation endpoints are unchanged.

The response retains `occupied_seats`, `seat_layout`, and `row_count` for existing
clients and adds:

- `seat_letters`: ordered aircraft letters, currently four or six.
- `extra_legroom_rows`: row numbers used by both the interface and confirmation.
- `fares`: available priced classes with `id`, `label`, `price`,
  `available_seats`, and `shared_inventory`.
- `cabins`: `id`, `name`, actual `rows`, `total_seats`, and `available_seats`.
- `pricing`: extra-legroom fee, tax rate, booking fee, and optional-extra prices.

The Flutter screen refreshes inventory every 30 seconds, on resume, and manually.
Failed refreshes block checkout. Reservations still enforce availability under
the listing lock, so a selection does not guarantee a seat until it is held.

## Optional listing configuration

Existing flight listing attributes can include cabin ranges and legroom rows:

```json
{
  "seat_layout": "2-2",
  "seat_rows": 16,
  "cabins": [
    {"id": "front", "name": "Forward cabin", "row_start": 1, "row_end": 8},
    {"id": "rear", "name": "Rear cabin", "row_start": 9, "row_end": 16}
  ],
  "extra_legroom_rows": [1, 7, 8]
}
```

A cabin may alternatively specify an explicit `rows` array. Cabins must cover
every aircraft row exactly once and have unique IDs. Invalid configuration
returns an explicit conflict response; it is not silently replaced.

Without configured cabins, the API returns one full-aircraft cabin. Without
configured legroom rows, it uses the existing aircraft rules. Only positive,
actually configured fare prices are shown. Existing inventory is shared across
fare classes and is labeled accordingly. Active holds reduce available stock;
expired holds do not. Cabin availability is capped by the remaining shared
inventory, so counts from different cabins must not be added together.

No live listings or database schema were changed to introduce this contract.
