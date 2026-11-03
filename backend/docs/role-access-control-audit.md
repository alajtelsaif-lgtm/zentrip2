# Zentrip role and access-control audit

## Assumptions and implementation mapping

The checked-in application is Flutter + Spring Boot + JDBC against Supabase
PostgreSQL, not Flask. The database's `customer` role is the requested `user`
role. Authentication remains the existing opaque bearer token: its hash is
looked up in `api_tokens`, then the role and partner ID are loaded from
`users`. No role or partner ID supplied in a request body is trusted.

## API route access matrix

`Public` means available without a token and therefore also reachable by any
signed-in role. `User` means database role `customer`. All `/api/**` endpoints
not listed here are denied by default.

| Endpoint | Allowed roles |
|---|---|
| `POST /api/auth/register` | Public |
| `POST /api/auth/login` | Public |
| `POST /api/auth/forgot-password` | Public |
| `POST /api/auth/verify-code` | Public |
| `POST /api/auth/reset-password` | Public |
| `GET /api/auth/me` | Admin, Partner, User |
| `POST /api/auth/logout` | Admin, Partner, User |
| `POST /api/profile` | User |
| `PUT /api/profile/password` | User |
| `GET /api/reviews` | Public |
| `POST /api/reviews` | User |
| `GET /api/offers` | Public |
| `GET /api/attractions/search` | Public |
| `POST /api/attractions/{id}/visits` | User |
| `GET /api/trips` | User |
| `POST /api/trips` | User |
| `GET /api/trips/availability` | User |
| `DELETE /api/trips/{id}` | User |
| `GET /api/flights/{flightId}/seats` | User |
| `POST /api/flights/{flightId}/seats/reserve` | User |
| `DELETE /api/flights/{flightId}/seats/reserve` | User |
| `POST /api/bookings/confirm` | User |
| `GET /api/bookings` | User |
| `GET /api/bookings/availability` | User |
| `POST /api/bookings` | User |
| `DELETE /api/bookings/{id}` | User |
| `GET /api/transfers` | User |
| `GET /api/transfers/availability` | User |
| `POST /api/transfers` | User |
| `POST /api/payments/checkout` | User |
| `GET /api/payments/verify/{sessionId}` | User |
| `GET /api/maps/search` | User |
| `POST /api/ai/chat` | User |
| `POST /api/ai/chat/cancel` | User |
| `GET /api/preferences/travel` | User |
| `PUT /api/preferences/travel` | User |
| `GET /api/exchange-rates` | Public |
| `GET /api/inventory/{type}` | Public |
| `GET /api/airports/search` | Public |
| `GET /api/flights/search/flexible` | Public |
| `GET /api/flights/search` | Public |
| `GET /api/hotels/locations` | Public |
| `GET /api/hotels/search` | Public |
| `GET /api/hotels/nearby` | Public |
| `GET /api/cars/locations` | Public |
| `GET /api/cars/nearby` | Public |
| `POST /api/partner/hotel-images` | Partner |
| `GET /api/partner/dashboard` | Partner |
| `GET /api/partner/listings` | Partner |
| `POST /api/partner/listings` | Partner |
| `PUT /api/partner/listings/{id}` | Partner; listing must belong to the current partner |
| `DELETE /api/partner/listings/{id}` | Partner; listing must belong to the current partner |
| `GET /api/partner/reservations` | Partner; reservation must reference one of its listings |
| `GET /api/partner/customers` | Partner; result is limited to customers with bookings on its listings |
| `GET /api/admin/dashboard` | Admin |
| `GET /api/admin/attractions/popularity` | Admin |
| `GET /api/admin/partners` | Admin |
| `GET /api/admin/partners/legacy-attractions` | Admin |
| `POST /api/admin/partners/{id}/attraction-review` | Admin |
| `POST /api/admin/partners` | Admin |
| `DELETE /api/admin/partners/{id}` | Admin |
| `POST /api/admin/partners/{id}/activate` | Admin |
| `GET /api/admin/reservations` | Admin; all users' reservations |
| `GET /api/admin/customers` | Admin |
| `GET /api/admin/monuments` | Admin |
| `POST /api/admin/monuments` | Admin |
| `PUT /api/admin/monuments/{id}` | Admin |
| `DELETE /api/admin/monuments/{id}` | Admin |
| `GET /api/admin/offers` | Admin |
| `POST /api/admin/offers` | Admin |
| `PUT /api/admin/offers/{id}` | Admin |
| `DELETE /api/admin/offers/{id}` | Admin |

## Frontend routes and menu entries

The dashboard routes are guarded by role in `AppRoutes`; the API independently
enforces the role. Admins are redirected to the admin dashboard, partners to
the partner dashboard, customers who open either dashboard are sent to home,
and signed-out dashboard requests return to login.

| Route/page | Allowed roles |
|---|---|
| `/` splash | Public; redirects according to restored session |
| `/onboarding` | Public |
| `/auth` login | Public |
| `/register` | Public |
| `/forgot-password` | Public |
| `/verify-code` | Public |
| `/login-success` | Guest or User; Admin/Partner redirected to their dashboard |
| `/home` app shell | Guest or User; Admin/Partner redirected to their dashboard |
| `/trip-details` | Guest or User; Admin/Partner redirected to their dashboard |
| `/search-flights` | Guest or User; Admin/Partner redirected to their dashboard |
| `/search-hotels` | Guest or User; Admin/Partner redirected to their dashboard |
| `/package-detail` | Guest or User; Admin/Partner redirected to their dashboard |
| `/flight-search` | Guest or User; Admin/Partner redirected to their dashboard |
| `/flight-results` | Guest or User; Admin/Partner redirected to their dashboard |
| `/flight-booking` | Guest or User; Admin/Partner redirected to their dashboard |
| `/hotel-search` | Guest or User; Admin/Partner redirected to their dashboard |
| `/hotel-results` | Guest or User; Admin/Partner redirected to their dashboard |
| `/hotel-detail` | Guest or User; Admin/Partner redirected to their dashboard |
| `/car-rental` | Guest or User; Admin/Partner redirected to their dashboard |
| `/car-detail` | Guest or User; Admin/Partner redirected to their dashboard |
| `/attractions` | Guest or User; Admin/Partner redirected to their dashboard |
| `/attraction-detail` | Guest or User; Admin/Partner redirected to their dashboard |
| `/packages-list` | Guest or User; Admin/Partner redirected to their dashboard |
| `/transfers` | Guest or User; Admin/Partner redirected to their dashboard |
| `/terms` | Public |
| `/privacy` | Public |
| `/admin-dashboard` | Admin |
| `/partner-dashboard` | Partner |

The user app-shell menu contains Explore, Nearby, Zen AI, My Trips, and Profile.
The admin dashboard contains Overview, Popularity, Partners, Offers,
Reservations, and Customers. The partner dashboard contains Overview,
Listings, Reservations, and Customers. The user shell has no admin or partner
menu entries.

Non-privileged routes are not blocked at the Flutter route layer for guests;
their sensitive operations remain protected by the API. Admin and Partner
accounts are redirected away from every non-dashboard route while signed in,
including login and legal screens; signing out clears that role guard.

The requested system-settings capability is not implemented in the current
application: there is no admin settings page, API route, or settings table. The
existing admin sections are Overview, Popularity, Partners, Offers,
Reservations, and Customers. This audit records the gap rather than inventing
settings or adding an unspecified persistence model.

## Database enforcement

`20261101_role_access_rls.sql` adds a non-login, non-`BYPASSRLS` application
role and row policies for users, partner-owned listings, booking history,
profiles, and other RLS-enabled application tables. `RlsContextFilter` starts a
transaction for API requests, switches to that role with `SET LOCAL ROLE`, and
sets role/user/partner context only from the verified token lookup. This is
transaction-scoped to work with the configured Supabase transaction pooler.
Password reset and registration endpoints retain their existing server-side
verification flow and do not receive client-controlled row context.

The migration changes database roles, grants, functions, and policies only; it
does not rename columns, change route contracts, or alter booking/listing data.

## Changelog

| File | Change | Why |
|---|---|---|
| `RlsContextFilter.java` | Sets transaction-local database role and identity context | Enforce PostgreSQL RLS even through the existing JDBC API |
| `SecurityConfig.java` | Adds the RLS filter and JDBC transaction manager fallback; protects hotel rate lookup and default-denies unknown API paths | Keep database context transaction-scoped and avoid implicit API access |
| `AiChatController.java` | Persists the asynchronous AI response inside an owner-scoped RLS transaction | Preserve chat history while streaming outside the request thread |
| `20261101_role_access_rls.sql` | Adds the runtime role and owner/admin/partner RLS policies | Add database enforcement beneath HTTP authorization |
| `AiChatControllerTest.java`, `SecurityConfigIntegrationTest.java`, `RlsContextFilterTest.java` | Verify asynchronous writes, cross-role API denials, and trusted identity context | Prevent regressions in server-side role enforcement |
| `role-access-control-audit.md` | Lists every API route and frontend route/menu role, plus manual verification steps | Make the access contract auditable |

## Verification results

- Backend suite: 182 passed, 0 failed, 21 PostgreSQL integration tests skipped.
- Flutter suite: 130 passed; `flutter analyze` reported no issues.
- Supabase policy checks ran in a rolled-back transaction under the
  `zentrip_api_runtime` role: that role is not a bypass role, partners could not
  read another partner's listings or unlinked bookings, partner cross-listing
  updates affected zero rows, customers saw only their own bookings, and admins
  saw the full booking count.
- The migration was applied to the existing Supabase database. It changed
  policies, helper functions, grants, and the non-login runtime role only; no
  application rows were inserted, updated, or deleted.

## Manual test steps

1. Sign in as a customer and open `/admin-dashboard` and `/partner-dashboard`;
   each should redirect to `/home`. Repeat while signed out; both should return
   to `/auth`.
2. Sign in as a partner and open `/admin-dashboard` and `/home`; both should
   redirect to `/partner-dashboard`.
3. Sign in as an admin and open `/partner-dashboard` and `/home`; both should
   redirect to `/admin-dashboard`.
4. With a partner bearer token, call `PUT /api/partner/listings/{another
   partner's listing id}` and `DELETE` the same listing. Both should return 403
   without changing the listing.
5. Create bookings linked to listings from two partners. Each partner should
   see only rows linked to its own listing in dashboard totals, reservations,
   and customer summaries. An admin should see both in `/api/admin/reservations`.
6. Call a protected customer route with a partner token and an admin route with
   a customer token; each should return 403. Call protected routes without a
   token; each should return 401.
7. Exercise public inventory searches and partner listing create/edit/delete
   after the RLS migration to confirm public active listings remain visible and
   each partner can modify only its own rows.
