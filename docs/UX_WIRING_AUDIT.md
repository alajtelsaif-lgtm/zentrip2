# Zentrip UX and Wiring Audit

**Audit date:** 2026-11-04  
**Scope:** Current Flutter client, Spring Boot API, provider wiring, navigation, controls, loading/error states, accessibility, and existing tests.  
**Data safety:** No production records were read or changed. No test account, booking, or provider order was created. Secrets were checked only for presence; their values were not accessed or recorded.

## Executive summary

The repository is a Flutter application backed by Spring Boot and PostgreSQL/Supabase, rather than a Flask application. The audit follows the implementation that is actually in the repository.

The running `Start Zentrip` workflow served the Flutter web app successfully. A direct browser preview of `/#/auth` rendered the login screen, and a settled headless browser capture of `/` rendered onboarding. The first root screenshot was taken before Flutter had painted its first frame; it was not evidence of a persistent blank-page failure. Browser logs showed a CPU-only/WebGL fallback warning, but no Flutter runtime exception.

The main booking flows are wired, with the flight simulator and hotel detail states receiving the best test coverage. This was a code-and-test audit, not a signed-in end-to-end acceptance run. No authenticated test account was available in the preview, so live booking, role dashboards, and user-specific records were not exercised in the browser.

Static inventory: 28 named routes, 5 AppShell tabs, 67 classes named as screens/dialogs/sheets/views/pages, and 415 callback definitions across the screen/widget source trees. Callback totals are 164 `onPressed`, 155 `onTap`, 63 `onChanged`, 7 `onSubmitted`, 12 `onSelected`, 1 `onLongPress`, 2 `onPageChanged`, 9 `onRefresh`, and 2 `onDismissed`; these are handler sites, not necessarily unique rendered controls. Repeated list-item controls are grouped by widget type in the inventory below.

### Coverage counts

- **28 named routes inventoried:** 9 route/screen families have direct widget-test coverage, 4 have route/model/controller coverage, and 15 are code-read only.
- **5 main tabs inventoried:** Home has widget coverage; My Trips has controller tests and the Nearby map component has viewport tests, but those two tab screens were not widget-tested. Zen AI and Profile are code-read only.
- **415 callback sites catalogued:** they are mapped by screen/control family below, but were not all manually tapped in a signed-in browser.
- **Known incomplete behavior:** weather and visa have no live provider; currency preference uses fixed sample rates; attraction map is explicitly “coming soon”; several English-only labels remain in Arabic mode.
- **Live/unverified:** external provider responses/permissions and authenticated account-specific browser flows.

## Findings

| ID | Severity | Finding | Evidence and impact | Status |
|---|---|---|---|---|
| UX-01 | Medium | Package destination weather and visa information are sample-only/unavailable outside mock mode. | The package detail screen calls `getDestinationWeather` and `getVisaInfo`. In production mode both client methods return “not configured” failures; no corresponding Spring API routes/providers were found. The UI handles this by showing its localized unavailable/partial message. | Code-read only |
| UX-02 | Medium | The currency preference uses fixed sample exchange rates. | `CurrencyService` always has `useMockMode = true` and fixed USD/EUR/GBP conversion values. A separate live `/exchange-rates` path exists for flight/hotel comparison, so the preference formatter and comparison controllers do not share the same rate source. This can make displayed estimates stale or inconsistent; booking/settlement values are not converted by this service. | Code-read only |
| UX-03 | Medium | Some user-facing English strings are not localized for Arabic. | Examples include the registration phone hint, verification subtitles, seat-selection title/refresh label, optional-extras labels/retry text, attraction clear-search tooltip, and map place-count text. Arabic RTL layout is tested for flight results, but these strings remain English. | Code-read only |
| UX-04 | Low | Invalid arguments could crash two named routes. | `/trip-details` and `/package-detail` previously cast `RouteSettings.arguments` directly to their model types. They now return Home if the expected model is absent or has the wrong type. | Test |
| UX-05 | Low | Attraction detail’s map action is an announced placeholder. | The control reports “Map view is coming soon”; it does not open a map. This is not a silent dead button, but the map action is not implemented. | Code-read only |
| UX-06 | Low | Some route/API code is not called by the current UI. | The `/login-success` route has no call site. The client’s `/hotels/locations` method has no screen caller (hotel search uses destination suggestions instead). The backend also exposes a transfers list endpoint with no dedicated client call; trip history currently reads `trips` and `bookings`. | Code-read only |
| UX-07 | Medium | Provider behavior is not live-verified in this audit. | Duffel, LiteAPI, OpenTripMap, Geoapify, SerpAPI, and Google Gemini have code paths and contract/unit tests, but this audit made no external provider search calls. Thus account permissions, current quotas, and live response quality remain unverified. | Not verified |
| UX-08 | Medium | Full signed-in flows and user-specific dashboards were not browser-tested. | The browser preview was unauthenticated. Creating a production test user or booking was avoided to protect real data. Widget/backend tests were used instead. | Not verified |
| UX-09 | Low | Firebase push delivery is not confirmed. | The token registration client/server route exists, but a live FCM registration/delivery was not attempted in the browser/device audit. | Not verified |
| UX-10 | Low | Icon-button accessibility is not verified globally. | There are tooltips and semantic labels in shared navigation, but no automated accessibility scan or screen-reader/device test was run across every icon action. | Not verified |
| UX-11 | Medium | Confirm OpenTripMap commercial terms before production use. | The running backend warns that the configured OpenTripMap free plan is for non-commercial use and recommends confirming a commercial plan. No live provider request was made in this audit. | Code-read only |

No provider order or real payment path was found in the flight/hotel booking integrations. Duffel supplies flight offers and LiteAPI supplies hotel data; booking/payment proceeds through Zentrip’s simulated checkout and its own saved trip/booking records. The simulator explicitly presents success and failure choices, and Flutter tests cover both flight-payment outcomes.

## Screen, route, and control inventory

Repeated controls inside a builder (for example, every flight card’s select action) are grouped by control type below. The action, destination, and endpoint are identified where present. Every route and screen family was indexed; each item is marked with the strongest verification actually performed.

### Named routes

| Route / screen | Role access in client | Interactive controls and action | Data/API wiring | Verification |
|---|---|---|---|---|
| `/` Splash | Guest; authenticated users are routed onward | Automatic session restore and onboarding check; no manual control | `/auth/me` when a saved session exists; local preferences | Widget-tested: startup tests; browser screenshot settled |
| `/onboarding` | Guest | Skip, swipe between pages, Next/Start | Stores `onboarding_seen`, then opens auth | Code-read only |
| `/auth` Login | Guest | Email/password fields, password visibility, remember-me, forgot-password link, Login, Create account; unconfigured social providers are hidden | `/auth/login`; then `/auth/me`/role redirect | Widget-tested layout; browser-visual verified, not signed in |
| `/register` Create account | Guest | Profile-photo picker, name/email/phone, country-code picker, password/confirmation, submit, back | `/auth/register` multipart form; profile upload endpoint if selected | Widget-tested layout/phone/photo picker; not a live account creation |
| `/forgot-password` | Guest | Email field, send/reset request, back, go to verification | `/auth/forgot-password`; opens `/verify-code` with email | Widget-tested layout; backend tests |
| `/verify-code` OTP/reset | Guest | OTP input, resend, password fields/visibility, submit, back to Login | `/auth/verify-code`, `/auth/reset-password` | Widget-tested compact layout; no live email/OTP |
| `/login-success` | Guest after auth in design; currently no caller | Continue/role destination | No unique API | Code-read only; orphan route |
| `/home` AppShell | User; admin/partner are redirected to their dashboards | Five bottom tabs; Home flight origin/destination swap, dates, passenger count, class, search; Hotels/Cars/Transfers shortcuts; destination/offer cards; refresh | Flights and `/offers`; hotel/car/transfer searches | Widget-tested home actions/layout |
| `/trip-details` | User | Back, trip detail actions and ticket/navigation actions | Loads the supplied `TripModel`; no direct detail-fetch route | Code-read only; invalid arguments currently throw |
| `/search-flights` Trip flight search | User | Search/select existing flight history or open flight search | Flight search route and local selection state | Code-read only |
| `/search-hotels` Trip hotel search | User | Search/select hotel history or open hotel search | Hotel search route | Code-read only |
| `/package-detail` | User | Package actions, flight/hotel/transfer links, review/navigation | Package state; weather/visa client calls currently fail outside mock mode | Code-read only; invalid arguments currently throw |
| `/flight-search` Search flight | User | Origin/destination text fields and airport pickers, swap, round-trip toggle, dates, passengers, class, flexible-date sheet, Search Flights | Airport directory search; flight search route | Widget-tested downstream results and route arguments; form not full E2E |
| `/flight-results` Select flight | User | Date chips, filter/sort controls, retry, flight-card select | Duffel offers merged with partner inventory; results API | Widget-tested loading/error/Arabic RTL; provider call not live |
| `/flight-booking` Flight checkout flow | User | Fare choice → passenger data → seat map/skip → fare rules/promo → simulated payment | Duffel offer details; seats/reservations; local trip/booking confirmation | Widget-tested step wiring and simulated success/failure |
| `/hotel-search` Search hotels | User | Destination input/autocomplete/submit, location action, check-in/out picker, room/guest steppers, Search/Nearby | `/hotels/destinations/suggest`, `/hotels/search`, location/nearby endpoints | Code-read only for full form |
| `/hotel-results` Hotel results | User | Search/filter/sort, retry, hotel-card open | LiteAPI data plus partner results; normalized hotel model | Code-read only for full search |
| `/hotel-detail` Hotel details | User | Gallery paging, detail sections, review/favorite actions when provided, room/booking action, back | LiteAPI detail data or partner listing; simulated booking | Widget-tested success, optional-content, missing/error states |
| `/car-rental` Car search | User | City/date pickers, search and car selection | Car location/nearby/search APIs and local partner inventory | Code-read only |
| `/car-detail` Car detail | User | Back, booking/review action | Selected car data; local simulated booking | Code-read only |
| `/attractions` Places/attractions | User | Search, category/filter selection, clear search, list/map entry, item selection, refresh where shown | OpenTripMap/cached landmark catalog; visit and map endpoints | Controller/model tests; screen not end-to-end |
| `/attraction-detail` Place details | User | Back, favorite/review, visit tracking, map action | OpenTripMap/catalog detail and visit API; map action currently says “coming soon” | Code-read only |
| `/packages-list` Packages/offers | User | Refresh, filter/type selection, package/offer card open | `/offers` or package/partner inventory | Code-read only |
| `/transfers` Transfers | User | Pickup/dropoff, location map picker, date/time, passenger count, vehicle choice, submit/confirm | Transfer availability and Zentrip booking endpoint | Code-read only; no transfer screen test |
| `/terms` | User | Back/scroll | Static legal text | Code-read only |
| `/privacy` | User | Back/scroll | Static privacy text | Code-read only |
| `/admin-dashboard` | Admin only | Dashboard tabs/sections, refresh, navigation to partners/bookings/customers/offers/monuments/popularity, logout | Admin dashboard and management endpoints | Route/model tests; no signed-in browser session |
| `/partner-dashboard` | Partner only | Listings/reservations/customers, refresh, add/edit/activate/delete listing, logout | Partner APIs; ownership enforced by backend/RLS configuration | Route/model tests; no signed-in browser session |

### Route-to-source index

| Route | Screen widget file |
|---|---|
| `/` | `lib/features/splash/presentation/screen/splash_screen.dart` — `SplashScreen` |
| `/onboarding` | `lib/features/onboarding/presentation/screens/onboarding_screen.dart` — `OnboardingScreen` |
| `/auth` | `lib/features/auth/presentation/screens/login_screen.dart` — `LoginScreen` |
| `/register` | `lib/features/auth/presentation/screens/register_screen.dart` — `RegisterScreen` |
| `/forgot-password` | `lib/features/auth/presentation/screens/forgot_password_screen.dart` — `ForgotPasswordScreen` |
| `/verify-code` | `lib/features/auth/presentation/screens/verfiy_screen.dart.dart` — `VerifyScreen` |
| `/login-success` | `lib/features/auth/presentation/screens/login_success_screen.dart` — `LoginSuccessScreen` |
| `/home` | `lib/global_widgets/app_shell.dart` — `AppShell`; `lib/features/home/presentation/screens/home_screen.dart` — `HomeScreen` |
| `/trip-details` | `lib/features/trips/presentation/screens/trip_details_screen.dart` — `TripDetailsScreen` |
| `/search-flights` | `lib/features/trips/presentation/screens/search_flights_screen.dart` — `SearchFlightsScreen` |
| `/search-hotels` | `lib/features/trips/presentation/screens/search_hotels_screen.dart` — `SearchHotelsScreen` |
| `/package-detail` | `lib/features/trips/presentation/screens/package_detail_screen.dart` — `PackageDetailScreen` |
| `/flight-search` | `lib/features/flight_booking/presentation/screens/flight_search_screen.dart` — `FlightSearchScreen` |
| `/flight-results` | `lib/features/flight_booking/presentation/screens/search_flight_screen.dart` — `SearchFlightScreen` |
| `/flight-booking` | `lib/features/flight_booking/presentation/screens/flight_booking_flow_screen.dart` — `FlightBookingFlowScreen` |
| `/hotel-search` | `lib/features/hotel_booking/presentation/screens/hotel_search_screen.dart` — `HotelSearchScreen` |
| `/hotel-results` | `lib/features/hotel_booking/presentation/screens/hotel_results_screen.dart` — `HotelResultsScreen` |
| `/hotel-detail` | `lib/features/hotel_booking/presentation/screens/hotel_detail_screen.dart` — `HotelDetailScreen` |
| `/car-rental` | `lib/features/car_rental/presentation/screens/car_rental_screen.dart` — `CarRentalScreen` |
| `/car-detail` | `lib/features/car_rental/presentation/screens/car_detail_screen.dart` — `CarDetailScreen` |
| `/attractions` | `lib/features/attractions/presentation/screens/attractions_screen.dart` — `AttractionsScreen` |
| `/attraction-detail` | `lib/features/attractions/presentation/screens/attraction_detail_screen.dart` — `AttractionDetailScreen` |
| `/packages-list` | `lib/features/home/presentation/screens/packages_list_screen.dart` — `PackagesListScreen` |
| `/transfers` | `lib/features/transfers/presentation/screens/transfers_screen.dart` — `TransfersScreen` |
| `/terms`, `/privacy` | `lib/features/profile/presentation/screens/terms_screen.dart` — `TermsScreen` |
| `/admin-dashboard` | `lib/features/admin/presentation/screens/admin_dashboard_screen.dart` — `AdminDashboardScreen` |
| `/partner-dashboard` | `lib/features/admin/presentation/screens/partner_dashboard_screen.dart` — `PartnerDashboardScreen` |

The AppShell tab widgets are `HomeScreen`, `NearbyScreen` (`lib/features/nearby/presentation/screens/nearby_screen.dart`), `ChatbotScreen` (`lib/features/chatbot/presentation/screens/chatbot_screen.dart`), `MyTripsScreen` (`lib/features/trips/presentation/screens/my_trips_screen.dart`), and `ProfileScreen` (`lib/features/profile/presentation/screens/profile_screen.dart`). Checkout subpages are `FlightChooseFareScreen`, `FlightPassengersScreen`, `FlightSeatSelectionScreen`, and `FlightReviewPayScreen` under `lib/features/flight_booking/presentation/screens/`.

### AppShell tabs and secondary screens

| Surface | Interactive controls and action | Verification |
|---|---|---|
| Home tab | Flight search form; Hotels/Cars/Transfers shortcuts; offer/destination cards; pull-to-refresh | Widget-tested home navigation/layout |
| Nearby tab | Location permission/retry/settings action; local search; category chips; place cards; map open | Controller/map viewport tests; not live geolocation/API tested |
| Zen AI tab | Suggested prompt chips, message entry/send, cancel in-flight response, conversation history/new conversation | Code-read only; Gemini server contract tested, not live AI |
| My Trips tab | Flight/booking segments, refresh, trip/booking cards, detail/cancel actions | Controller-tested source merge/failure/refresh; browser session not available |
| Profile tab | Profile/edit, favorites, settings, travel preferences, password, notification settings, currency, language, appearance, terms/privacy, logout | Code-read only; route/session behavior not browser-tested |
| Flight choose-fare screen | Fare cards, selected fare, continue/back | Widget-tested as part of flight reference flow |
| Passenger screen | Passenger form fields, date picker, edit passenger, continue/back | Widget-tested as part of flight reference flow |
| Seat-selection screen/map | Cabin/seat selection, deselect, passenger assignment, refresh/retry, skip/continue/back | Widget-tested for selected/taken/available, multiple passengers, retry |
| Review & Pay | Fare-rule checkbox, promo-code expand/input, pay button | Widget-tested through simulator success/failure; pay is disabled until accepted |
| Booking confirmation/ticket/QR | View ticket/QR, return to trips/home | Model/widget tests exist; no signed-in device flow |
| Chat history | Open prior conversation, create new conversation, delete/confirm | Code-read only |
| Favorites | Open saved item, remove saved item, empty state | Code-read only |
| Language/currency/appearance/notification/preferences | Select option, toggle preference, save/back | Code-read only; currency values have the fixed-rate issue above |
| Edit profile/change password | Form inputs, photo picker, save/back | Code-read only except photo picker widget test |
| Places map | Map pan/zoom, marker/cluster selection, open item sheet, close/back | Map viewport tests; device map/geolocation not verified |
| Admin/partner management dialogs | Add/edit forms, dropdowns, date/time pickers, activate/delete/review confirmations | Model tests; dialogs not widget-tested |
| Itinerary screen (`lib/features/trips/presentation/screens/itinerary_screen.dart`) | Refresh, flight/booking list items, detail navigation | Code-read only |
| Payment checkout (`lib/global_widgets/payment_checkout_screen.dart`) | Open/cancel checkout, simulator success/failure choices, back | Flight simulator success/failure widget-tested; no external payment |
| Booking completion/ticket (`lib/global_widgets/booking_confirmation_screen.dart`, `ticket_qr_screen.dart`; `lib/features/flight_booking/presentation/screens/booking_confirmed_screen.dart`) | Return home/trips, open ticket/QR | Widget/model tests; no signed-in browser flow |
| Review sheet (`lib/global_widgets/review_form_sheet.dart`) | Star rating, comment, submit, dismiss | Code-read only |
| Offline/error views (`lib/global_widgets/no_internet_view.dart`, `booking_load_error.dart`, `booking_loading_overlay.dart`) | Retry/back or automatic loading/dismiss | Code-read only |

### Shared dialogs, sheets, and overlays

| Surface | Trigger and controls | Verification |
|---|---|---|
| Confirmation dialog (`lib/global_widgets/confirm_dialog.dart`) | Confirm/cancel for destructive or booking actions | Code-read only |
| Booking loading/error overlay (`lib/global_widgets/booking_loading_overlay.dart`, `booking_load_error.dart`) | Automatic while booking; retry/back on error | Code-read only |
| Country/phone picker sheet (`lib/global_widgets/phone_field.dart`, registration screen) | Registration phone field; search/select country code | Widget-tested |
| Photo-source sheet (`lib/features/auth/presentation/widgets/photo_picker_avatar.dart`) | Registration/profile avatar; camera/gallery choice | Widget-tested selection logic |
| Home airport picker (`lib/features/home/presentation/screens/home_screen.dart`) | Origin/destination fields; query/select airport; close | Code-read only |
| Passenger-count dialog (`lib/features/home/presentation/screens/home_screen.dart`) | Minus/plus, cancel/confirm | Code-read only |
| Seat-class sheet (`lib/features/home/presentation/screens/home_screen.dart`, flight-search screen) | Select class and close | Code-read only |
| Flexible-flight dates sheet (`lib/features/flight_booking/presentation/widgets/flexible_flight_dates_button.dart`) | Period/month/duration selection, apply/cancel | Widget-tested model/selection logic |
| Flight filter/sort sheets (`lib/features/flight_booking/presentation/screens/search_flight_screen.dart`) | Change result filters/sort and apply/close | Code-read only |
| Hotel date-range picker (`lib/features/hotel_booking/presentation/screens/hotel_search_screen.dart`) | Select check-in/out, dismiss | Code-read only |
| Map location picker (`lib/features/transfers/presentation/screens/transfers_screen.dart`) | Select/confirm pickup/dropoff or map destination | Code-read only |
| Review form sheet (`lib/global_widgets/review_form_sheet.dart`) | Rating stars, comment field, submit/close | Code-read only |
| Booking simulator (`lib/global_widgets/payment_checkout_screen.dart`) | Explicit simulated success/failure buttons | Widget-tested, no real charge |
| Partner/admin CRUD dialogs (`lib/features/admin/presentation/screens/admin_partners_management.dart`, `admin_catalog_management.dart`, `partner_dashboard_screen.dart`) | Form controls, save/cancel, confirmation | Code-read/model-tested |

## API and provider usage

“Tested” below means a local unit/controller/widget test or an HTTP contract test with a stub. It does **not** mean the external account was contacted live.

| Provider/data source | Call path and use | Configuration observation | Proof/status |
|---|---|---|---|
| Supabase PostgreSQL | Spring backend persistence for users, sessions, trips/bookings, partner/admin records, attractions, and chat history; Flutter uses the Spring API, not Supabase directly | Existing database connection remains server-side | PostgreSQL integration suite previously passed; no production rows inspected/changed in this audit |
| Duffel Flights | Spring flight search endpoints; returns offers, not provider orders | Access token is configured in server environment | `DuffelFlightServiceTest` and Flutter offer/simulator tests; no live search |
| LiteAPI Hotels | Hotel search/detail data; partner results remain available and Zentrip simulator handles booking | API key is configured; no provider booking flow found | `LiteApiHotelServiceTest` and hotel-detail widget tests; no live search |
| OpenTripMap | Attraction search/details/destination suggestions | API key configured | `OpenTripMapAttractionServiceTest`, attraction controller tests; no live request |
| Geoapify | Airport/geocoding fallback when the local airport directory does not resolve a query | API key configured | Airport directory/controller contract tests; no live request |
| SerpAPI | `/maps/search`, used by Nearby for category/location searches | Key configured | API/controller code path; no live request |
| Google Gemini | AI chat streaming, overload fallback, and cancellation through Spring | `GEMINI_API_KEY` configured; primary and fallback models both returned HTTP 200 in provider smoke requests | Unit/contract tests; authenticated full-screen flow still needs browser confirmation |
| Google Places | Optional partner-listing rating enrichment | `GOOGLE_PLACES_API_KEY` was not configured in the environment | Startup/per-listing sync code checks for key; live enrichment not available or verified |
| Exchange-rate service | `/exchange-rates` used by flight/hotel `PriceComparison` | Server service and endpoint are wired; separate currency preference still uses fixed mock rates | Backend service/controller and Flutter price-comparison tests |
| Weather/visa | Package detail calls client methods, but there are no corresponding server routes/providers in production mode | Sample-only methods return failure when mock mode is off | Code-read only; destination row degrades to unavailable/partial |
| Push notifications | Client registers/removes FCM token through `/users/fcm-token` | Live FCM setup/delivery not confirmed | Code-read only |
| Partner packages/inventory | Zentrip database/partner endpoints; no external package supplier was found | Local partner database | Code-read only and existing model/backend tests |
| Payments/bookings | Zentrip simulator and local persistence; checkout displays explicit test/simulator language | No live Stripe/payment-gateway or Duffel/LiteAPI order creation path found | Flight simulator success/failure widget tests; no real payment/order |

The API client declares 28 application route constants, and Spring controllers expose the auth, profile/preferences, offers, attractions, trips/bookings, flight/seat, hotel, car, transfer, payment-simulator, map, partner, admin, and AI endpoints. The Flutter caller index was checked against controller mappings. Two notable gaps are the unavailable weather/visa data and the unused hotel-location autocomplete method. External APIs were not called to avoid changing provider state or consuming credits.

No active HotelBeds or RapidAPI integration was found in the current source; hotel results use LiteAPI plus partner inventory.

## End-to-end flow audit

| Flow | What is covered | What remains unverified |
|---|---|---|
| Authentication/session/language | Role-based client routing tests; login/register/forgot/OTP screen layout tests; locale/phone tests; hidden unconfigured social sign-in test | Real sign-in, session expiry against a signed-in browser, real email OTP, language persistence after device restart |
| Flight search to My Trips | Flight query/result loading/error/retry/RTL tests; fare/passenger/seat/review navigation; seat reservation states; simulated payment success/failure; trips controller combines flight trips and bookings | Live Duffel search, signed-in browser flow, Android back, rotation, app restart, deep link, and DB row after a live account booking |
| Hotel search to booking | Hotel detail success/empty/error/optional content, LiteAPI model rendering and simulated booking control tested | Full search-to-detail-to-simulator browser flow with a signed-in account; live LiteAPI response |
| Car rental | Search/detail/booking routes read; model/location tests exist | Full UI flow and booking persistence in browser |
| Transfers | Search, map picker, vehicle selection, submit, and API wiring read | No screen-level end-to-end test or signed-in browser run |
| Packages/attractions | Attraction search/map/controller and visit-ranking tests; package navigation read | Package booking and all detail actions in a signed-in browser; live weather/visa |
| Zen AI | Gemini primary/fallback smoke requests and streaming contract tests | Live authenticated prompt/reply/history browser flow in the app |
| Profile/settings | Route and persistence code read | Signed-in browser; restart persistence; notifications/device permission |
| Admin/partner | Role route tests and backend/model tests | CRUD, ownership, and dashboard data in signed-in browser accounts |

## UX, performance, and accessibility checks

| Area | Result |
|---|---|
| Navigation/route transitions | Custom fade/slide routes are defined; AppShell keeps tab state in an indexed stack. No global Hero transitions were found. |
| Dynamic lists | Lazy `ListView.builder`/`ListView.separated` are used in dynamic result/list screens. Plain `ListView` and `SingleChildScrollView` also occur for short/static forms and panels. Code-read only. |
| Loading placeholders | Flight results, seats, and other asynchronous surfaces have loading UI. Hotel detail tests exercise loading/success/empty/error. A single project-wide shimmer pattern is not used consistently. |
| Image caching | `cached_network_image` is used in the home screen; only a small number of plain `Image.network` usages were found. Caching is not universal across screens. |
| Search rate control | Debounce timers and request cancellation exist for hotel destinations, airport selection, and attraction search/map requests. Local Nearby filtering does not send a request per keystroke. |
| OTP | `pinput` is present in `pubspec`, but no `Pinput` usage was found; OTP uses project-specific input widgets. |
| Arabic/RTL | Localization infrastructure is present; a narrow Arabic RTL flight-results widget test exists. The hardcoded English strings in UX-03 remain. |
| Touch targets/contrast/screen reader | No full accessibility audit was run. Shared Material controls provide defaults, but explicit semantic labels/tooltips are not present on every icon-only control. Manual assistive-technology/device verification remains. |
| Offline/slow/session expiry | API error handling and selected screen retry/error states exist. Full offline/slow-network and expired-session browser scenarios were not run. |

## Verification and limits

| Check | Result |
|---|---|
| Replit workflow | `Start Zentrip` was running; HTML and Flutter web artifacts returned HTTP 200. |
| Browser preview | Workflow restarted successfully. Immediate screenshot capture sometimes returned white, but a settled Chromium capture of `/#/auth` rendered the login screen; `/` rendered onboarding after Flutter settled. No signed-in session was used. |
| Browser console | No Flutter runtime exception observed. A CPU-only/WebGL fallback warning was emitted. |
| Flutter analyzer/tests | `flutter analyze`: no issues. `flutter test`: 169 tests passed, including the new invalid-route-argument test. |
| Backend/PostgreSQL tests | `bash scripts/test-postgres.sh`: 224 tests passed, 0 failures/errors/skips; includes all 29 PostgreSQL integration/migration tests. |
| Live external API calls | Not run. Provider contract tests are mocked/stubbed and cannot prove current account permissions, quotas, or response quality. |
| Test data | None created; no test data needed cleanup. |

## Manual acceptance steps

Use a dedicated non-production account before performing these checks. Do not use a real customer account or provider checkout.

1. Open the app on a fresh browser, finish onboarding, register/sign in with a dedicated test account, then sign out/in and confirm the session and selected language.
2. Search a flight with a valid route/date; select an offer, choose fare, enter test passenger details, select/deselect a seat, accept fare rules, run both simulator success and failure, then check confirmation, ticket, and My Trips.
3. Search a hotel with valid dates, open a LiteAPI and a partner result separately, verify image/price/currency, then run the clearly labeled simulator and confirm My Trips.
4. Exercise car and transfer searches, package details, attraction search/detail/map, AI send/cancel/history, profile settings, and account logout.
5. Sign in as a test admin and test dashboard refresh, partner/offer/catalog CRUD; sign in as a test partner and confirm only its own listings/bookings are shown.
6. Repeat flight/hotel search while offline and on a slow connection; test retry, empty results, expiry/login redirect, Android system back, screen rotation, and app restart.
7. On a real Android device, check Arabic RTL, large text, screen-reader labels, and target sizes; also verify notification permission and FCM delivery if push is required.

## Change log

This document recorded the findings before code changes. `lib/routes/app_routes.dart` now safely routes invalid trip/package arguments to Home, with a regression test in `test/app_role_route_guard_test.dart`. No UI styling, database schema, provider configuration, or production data was changed.
