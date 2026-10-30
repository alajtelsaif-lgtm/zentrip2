package com.zentrip.api;

import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;
import jakarta.servlet.http.HttpServletRequest;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.server.ResponseStatusException;
import org.springframework.web.multipart.MultipartFile;
import org.springframework.web.servlet.support.ServletUriComponentsBuilder;

import java.math.BigDecimal;
import java.net.URI;
import java.util.LinkedHashMap;
import java.util.Comparator;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import java.sql.PreparedStatement;
import java.sql.Statement;
import java.time.LocalDate;
import java.time.format.DateTimeParseException;
import org.springframework.jdbc.support.GeneratedKeyHolder;
import org.springframework.jdbc.support.KeyHolder;

@RestController
@RequestMapping("/api")
public class PartnerController {
    private static final Logger LOG = LoggerFactory.getLogger(PartnerController.class);
    private static final ObjectMapper JSON = new ObjectMapper();
    private static final List<String> LISTING_TYPES =
            List.of("flight", "hotel", "car", "attraction", "transfer", "package");
    private static final Map<String, LocationMetadata> LOCATIONS = Map.ofEntries(
            Map.entry("Tripoli", new LocationMetadata("MJI", "Libya", "Western Libya")),
            Map.entry("Misrata", new LocationMetadata("MRA", "Libya", "Central Libya")),
            Map.entry("Benghazi", new LocationMetadata("BEN", "Libya", "Eastern Libya")),
            Map.entry("Sebha", new LocationMetadata("SEB", "Libya", "Southern Libya")),
            Map.entry("Cairo", new LocationMetadata("CAI", "Egypt", "North Africa")),
            Map.entry("Tunis", new LocationMetadata("TUN", "Tunisia", "North Africa")),
            Map.entry("Istanbul", new LocationMetadata("IST", "Turkiye", "Europe")),
            Map.entry("Jeddah", new LocationMetadata("JED", "Saudi Arabia", "Middle East")),
            Map.entry("Dubai", new LocationMetadata(
                    "DXB", "United Arab Emirates", "Middle East")),
            Map.entry("Bali", new LocationMetadata("DPS", "Indonesia", "Southeast Asia")),
            Map.entry("Jakarta", new LocationMetadata("CGK", "Indonesia", "Southeast Asia")));
    private final JdbcTemplate jdbc;
    private final ProfilePhotoStorage imageStorage;
    private final GooglePlacesRatingSync googlePlacesRatingSync;

    public PartnerController(
            JdbcTemplate jdbc,
            ProfilePhotoStorage imageStorage,
            GooglePlacesRatingSync googlePlacesRatingSync) {
        this.jdbc = jdbc;
        this.imageStorage = imageStorage;
        this.googlePlacesRatingSync = googlePlacesRatingSync;
    }

    @PostMapping("/partner/hotel-images")
    public Map<String, String> uploadHotelImage(
            @RequestParam("image") MultipartFile image,
            HttpServletRequest request) {
        PartnerIdentity partner = requirePartner(request);
        ensurePartnerCanManageType(partner, "hotel");
        String storedPath = imageStorage.store(image);
        if (storedPath == null) {
            throw new ResponseStatusException(
                    HttpStatus.BAD_REQUEST, "A hotel image is required");
        }
        return Map.of(
                "image_url",
                ServletUriComponentsBuilder.fromCurrentContextPath()
                        .path(storedPath)
                        .toUriString());
    }

    private static LocationMetadata validateListingData(
            String type,
            String city,
            Map<String, Object> attributes) {
        LocationMetadata baseLocation;
        if ("flight".equals(type)) {
            LocationMetadata origin = validateAirport(
                    attributes, "origin_city", "origin_code");
            LocationMetadata destination = validateAirport(
                    attributes, "destination_city", "destination_code");
            validateKnownLocation(origin.city(), null);
            attributes.put("origin_country", origin.country());
            attributes.put("origin_region", origin.region());
            attributes.put("destination_country", destination.country());
            attributes.put("destination_region", destination.region());
            attributes.put("location_code", origin.code());
            attributes.put("location_region", origin.region());
            if (!city.trim().equalsIgnoreCase(
                    origin.city())) {
                throw new ResponseStatusException(
                        HttpStatus.BAD_REQUEST, "Listing city must match the flight origin");
            }
            normalizeFlightAircraft(attributes);
            baseLocation = origin;
        } else if ("transfer".equals(type)) {
            LocationMetadata pickup = validateKnownLocation(
                    text(attributes.get("pickup_location")), null);
            LocationMetadata dropoff = validateKnownLocation(
                    text(attributes.get("dropoff_location")), null);
            baseLocation = pickup;
            attributes.put("pickup_location", pickup.city());
            attributes.put("pickup_code", pickup.code());
            attributes.put("pickup_country", pickup.country());
            attributes.put("pickup_region", pickup.region());
            attributes.put("dropoff_location", dropoff.city());
            attributes.put("dropoff_code", dropoff.code());
            attributes.put("dropoff_country", dropoff.country());
            attributes.put("dropoff_region", dropoff.region());
            attributes.put("location_code", pickup.code());
            attributes.put("location_region", pickup.region());
            if (!city.trim().equalsIgnoreCase(
                    pickup.city())) {
                throw new ResponseStatusException(
                        HttpStatus.BAD_REQUEST, "Listing city must match the transfer pickup");
            }
        } else {
            LocationMetadata location = validateKnownLocation(city, null);
            baseLocation = location;
            attributes.put("location_code", location.code());
            attributes.put("location_region", location.region());
            if ("car".equals(type)) {
                attributes.put("pickup_location", location.city());
            }
        }
        Map<String, Set<String>> listFields = Map.of(
                "hotel", Set.of("amenities"),
                "car", Set.of("features"),
                "attraction", Set.of("tags"),
                "transfer", Set.of("included_services"),
                "package", Set.of("highlights"));
        for (String field : listFields.getOrDefault(type, Set.of())) {
            Object value = attributes.get(field);
            if (value != null && !(value instanceof List<?>)) {
                throw new ResponseStatusException(
                        HttpStatus.BAD_REQUEST, field + " must be an array");
            }
        }
        return baseLocation;
    }

    private static void normalizeFlightAircraft(Map<String, Object> attributes) {
        String rawModel = text(attributes.get("aircraft_model"))
                .trim().toLowerCase(Locale.ROOT)
                .replaceAll("[^a-z0-9]", "");
        String rawLayout = text(attributes.get("seat_layout"))
                .trim().toLowerCase(Locale.ROOT)
                .replace('×', '-')
                .replace('x', '-')
                .replace('+', '-')
                .replace(" ", "");
        boolean atr = switch (rawModel) {
            case "atr72" -> true;
            case "airbusa320" -> false;
            case "" -> rawLayout.startsWith("2-");
            default -> throw new ResponseStatusException(
                    HttpStatus.BAD_REQUEST, "Unsupported aircraft_model");
        };
        String model = atr ? "atr72" : "airbus_a320";
        String name = atr ? "ATR 72" : "Airbus A320";
        String layout = atr ? "2-2" : "3-3";
        int rows = atr ? 16 : 30;
        int capacity = atr ? 64 : 180;

        if (!rawLayout.isEmpty() && !layout.equals(rawLayout)) {
            throw new ResponseStatusException(
                    HttpStatus.BAD_REQUEST, "seat_layout does not match aircraft_model");
        }
        int configuredRows = aircraftInteger(
                attributes.get("seat_rows"),
                aircraftInteger(attributes.get("row_count"), rows, "row_count"),
                "seat_rows");
        int configuredCapacity = aircraftInteger(
                attributes.get("seat_capacity"), capacity, "seat_capacity");
        int availableSeats = aircraftInteger(
                attributes.get("seats_available"), capacity, "seats_available");
        if (configuredRows != rows || configuredCapacity != capacity
                || availableSeats > capacity) {
            throw new ResponseStatusException(
                    HttpStatus.BAD_REQUEST, "Flight seat inventory does not match aircraft capacity");
        }
        attributes.put("aircraft_model", model);
        attributes.put("aircraft_name", name);
        attributes.put("seat_layout", layout);
        attributes.put("seat_rows", rows);
        attributes.put("row_count", rows);
        attributes.put("seat_capacity", capacity);
        attributes.put("seats_available", availableSeats);
    }

    private static int aircraftInteger(Object value, int fallback, String field) {
        try {
            int parsed = value == null
                    ? fallback
                    : new BigDecimal(text(value)).intValueExact();
            if (parsed < 0) throw new ArithmeticException();
            return parsed;
        } catch (NumberFormatException | ArithmeticException exception) {
            throw new ResponseStatusException(
                    HttpStatus.BAD_REQUEST, field + " must be a non-negative integer");
        }
    }

    private static LocationMetadata validateAirport(
            Map<String, Object> attributes,
            String cityField,
            String codeField) {
        String city = text(attributes.get(cityField)).trim();
        String code = text(attributes.get(codeField)).trim().toUpperCase(Locale.ROOT);
        LocationMetadata location = findLocation(city);
        if (location == null || !location.code().equals(code)) {
            throw new ResponseStatusException(
                    HttpStatus.BAD_REQUEST,
                    cityField + " and " + codeField + " must match a supported airport");
        }
        attributes.put(cityField, location.city());
        attributes.put(codeField, code);
        return location;
    }

    private static LocationMetadata validateKnownLocation(String city, String country) {
        LocationMetadata location = findLocation(city);
        if (location == null) {
            throw new ResponseStatusException(
                    HttpStatus.BAD_REQUEST,
                    "Location must be selected from the supported registry");
        }
        if (country != null && !location.country().equalsIgnoreCase(country.trim())) {
            throw new ResponseStatusException(
                    HttpStatus.BAD_REQUEST, "Country must match the selected location");
        }
        return location;
    }

    private static LocationMetadata findLocation(String city) {
        for (Map.Entry<String, LocationMetadata> entry : LOCATIONS.entrySet()) {
            if (entry.getKey().equalsIgnoreCase(city.trim())) {
                return new LocationMetadata(
                        entry.getValue().code(),
                        entry.getValue().country(),
                        entry.getValue().region(),
                        entry.getKey());
            }
        }
        return null;
    }

    private static Map<String, Object> requestAttributes(Object value) {
        if (value == null) return new LinkedHashMap<>();
        if (!(value instanceof Map<?, ?>)) {
            throw new ResponseStatusException(
                    HttpStatus.BAD_REQUEST, "attributes must be a JSON object");
        }
        return attributes(value);
    }

    static void normalizeHotelLocation(Map<String, Object> attributes) {
        attributes.remove("rating");
        attributes.remove("review_count");
        attributes.remove("google_rating");
        attributes.remove("google_review_count");

        String locationInput = text(attributes.get("google_maps_url")).trim();
        if (locationInput.isEmpty()) {
            locationInput = text(attributes.get("location_input")).trim();
        }
        Double latitude = coordinate(attributes.get("latitude"));
        Double longitude = coordinate(attributes.get("longitude"));
        String placeId = text(attributes.get("place_id")).trim();
        if (placeId.isEmpty()) {
            placeId = text(attributes.get("google_place_id")).trim();
        }
        if (!locationInput.isEmpty()) {
            String decoded = locationInput.replace("%2C", ",").replace("%2c", ",");
            Matcher atCoordinates = Pattern.compile(
                    "@(-?\\d+(?:\\.\\d+)?),\\s*(-?\\d+(?:\\.\\d+)?)")
                    .matcher(decoded);
            Matcher mapCoordinates = Pattern.compile(
                    "!3d(-?\\d+(?:\\.\\d+)?)!4d(-?\\d+(?:\\.\\d+)?)")
                    .matcher(decoded);
            Matcher plainCoordinates = Pattern.compile(
                    "^\\s*(-?\\d+(?:\\.\\d+)?)\\s*,\\s*(-?\\d+(?:\\.\\d+)?)\\s*$")
                    .matcher(decoded);
            Matcher queryCoordinates = Pattern.compile(
                    "[?&](?:q|query|center)=(-?\\d+(?:\\.\\d+)?),\\s*(-?\\d+(?:\\.\\d+)?)",
                    Pattern.CASE_INSENSITIVE)
                    .matcher(decoded);
            Matcher placeQuery = Pattern.compile(
                    "(?:place_id|query_place_id)=([^&]+)", Pattern.CASE_INSENSITIVE)
                    .matcher(decoded);
            Matcher placePath = Pattern.compile("!1s(ChIJ[A-Za-z0-9_-]+)")
                    .matcher(decoded);
            boolean isPlaceIdInput = decoded.startsWith("ChIJ")
                    || decoded.regionMatches(true, 0, "place_id:", 0, 9)
                    || decoded.matches("[A-Za-z0-9_-]{10,255}");
            if (atCoordinates.find()) {
                latitude = Double.parseDouble(atCoordinates.group(1));
                longitude = Double.parseDouble(atCoordinates.group(2));
            } else if (mapCoordinates.find()) {
                latitude = Double.parseDouble(mapCoordinates.group(1));
                longitude = Double.parseDouble(mapCoordinates.group(2));
            } else if (plainCoordinates.matches()) {
                latitude = Double.parseDouble(plainCoordinates.group(1));
                longitude = Double.parseDouble(plainCoordinates.group(2));
            } else if (queryCoordinates.find()) {
                latitude = Double.parseDouble(queryCoordinates.group(1));
                longitude = Double.parseDouble(queryCoordinates.group(2));
            } else if (isPlaceIdInput) {
                latitude = null;
                longitude = null;
            }
            if (placeQuery.find()) {
                placeId = placeQuery.group(1).trim();
            } else if (placePath.find()) {
                placeId = placePath.group(1);
            } else if (decoded.startsWith("ChIJ")) {
                placeId = decoded;
            } else if (decoded.regionMatches(true, 0, "place_id:", 0, 9)) {
                placeId = decoded.substring(9).trim();
            } else if (decoded.matches("[A-Za-z0-9_-]{10,255}")) {
                placeId = decoded;
            }
        }

        boolean hasLatitude = latitude != null;
        boolean hasLongitude = longitude != null;
        if (hasLatitude != hasLongitude
                || (hasLatitude && (latitude == null || longitude == null
                        || !validCoordinate(latitude, -90, 90)
                        || !validCoordinate(longitude, -180, 180)))) {
            throw new ResponseStatusException(
                    HttpStatus.BAD_REQUEST, "Hotel location coordinates are invalid");
        }
        if (!hasLatitude && placeId.isBlank()
                && !isGoogleMapsUrl(locationInput)
                && !isPlusCodeLocation(locationInput)) {
            throw new ResponseStatusException(
                    HttpStatus.BAD_REQUEST,
                    "Hotel location must contain coordinates, a Google Place ID, "
                            + "a Google Maps URL, or a Plus Code");
        }
        if (locationInput.length() > 2048 || placeId.length() > 255) {
            throw new ResponseStatusException(
                    HttpStatus.BAD_REQUEST, "Hotel location value is too long");
        }
        if (hasLatitude) {
            attributes.put("latitude", latitude);
            attributes.put("longitude", longitude);
        } else {
            attributes.remove("latitude");
            attributes.remove("longitude");
        }
        if (placeId.isBlank()) {
            attributes.remove("google_place_id");
            attributes.remove("place_id");
        } else {
            attributes.put("google_place_id", placeId);
            attributes.put("place_id", placeId);
        }
        if (!locationInput.isEmpty()) {
            attributes.put("location_input", locationInput);
        }
    }

    static void normalizeHotelListing(
            Map<String, Object> body,
            Map<String, Object> attributes,
            String city,
            String hotelName) {
        copyHotelValue(body, attributes, "location_name");
        copyHotelValue(body, attributes, "google_maps_url");
        copyHotelValue(body, attributes, "place_id");
        copyHotelValue(body, attributes, "amenities");
        copyHotelValue(body, attributes, "tax_and_fees_percentage");
        copyHotelValue(body, attributes, "available_rooms");
        if (text(attributes.get("google_maps_url")).isBlank()) {
            attributes.put(
                    "google_maps_url", text(attributes.get("location_input")));
        }
        if (text(attributes.get("place_id")).isBlank()) {
            attributes.put("place_id", text(attributes.get("google_place_id")));
        }

        String locationName = text(attributes.get("location_name")).trim();
        if (locationName.isEmpty()) {
            locationName = text(attributes.get("address")).trim();
        }
        if (locationName.isEmpty()) {
            locationName = city.trim();
        }
        if (locationName.isEmpty() || locationName.length() > 512) {
            throw new ResponseStatusException(
                    HttpStatus.BAD_REQUEST, "Hotel location name is required");
        }
        attributes.put("location_name", locationName);
        attributes.put("name", hotelName);
        attributes.put(
                "available_rooms", nonNegativeInteger(attributes.get("available_rooms")));

        Object rawAmenities = attributes.get("amenities");
        if (!(rawAmenities instanceof List<?> amenities)
                || amenities.stream().anyMatch(value ->
                        !(value instanceof String text)
                                || text.isBlank() || text.length() > 100)) {
            throw new ResponseStatusException(
                    HttpStatus.BAD_REQUEST, "Hotel amenities must be an array of strings");
        }
        Object rawTax = attributes.get("tax_and_fees_percentage");
        BigDecimal tax = rawTax == null ? BigDecimal.valueOf(12) : decimal(rawTax);
        if (tax.compareTo(BigDecimal.valueOf(100)) > 0) {
            throw new ResponseStatusException(
                    HttpStatus.BAD_REQUEST, "Hotel tax and fees percentage must be at most 100");
        }
        attributes.put("tax_and_fees_percentage", tax);
        attributes.remove("google_rating");
        attributes.remove("google_review_count");
        attributes.remove("rating");
        attributes.remove("review_count");
    }

    private static void copyHotelValue(
            Map<String, Object> body,
            Map<String, Object> attributes,
            String key) {
        if (body.containsKey(key)) {
            attributes.put(key, body.get(key));
        }
    }

    private static int nonNegativeInteger(Object value) {
        try {
            int rooms = value == null
                    ? 0
                    : new BigDecimal(text(value)).intValueExact();
            if (rooms < 0) throw new ArithmeticException();
            return rooms;
        } catch (NumberFormatException | ArithmeticException exception) {
            throw new ResponseStatusException(
                    HttpStatus.BAD_REQUEST,
                    "Hotel available_rooms must be a non-negative integer");
        }
    }

    private static boolean isGoogleMapsUrl(String value) {
        if (value.isBlank()) return false;
        try {
            URI uri = URI.create(value);
            String scheme = uri.getScheme();
            String host = uri.getHost();
            if (scheme == null || host == null
                    || !(scheme.equalsIgnoreCase("http")
                            || scheme.equalsIgnoreCase("https"))
                    || uri.getRawUserInfo() != null
                    || uri.getPort() != -1) {
                return false;
            }
            String normalizedHost = host.toLowerCase(Locale.ROOT);
            String path = uri.getPath();
            return normalizedHost.equals("maps.app.goo.gl")
                    || normalizedHost.equals("maps.google.com")
                    || ((normalizedHost.equals("google.com")
                            || normalizedHost.equals("www.google.com"))
                            && path != null && path.startsWith("/maps"));
        } catch (IllegalArgumentException exception) {
            return false;
        }
    }

    private static boolean isPlusCodeLocation(String value) {
        return Pattern.compile(
                "(?i)^(?:[23456789CFGHJMPQRVWX]{2}|"
                        + "[23456789CFGHJMPQRVWX]{4}|"
                        + "[23456789CFGHJMPQRVWX]{6}|"
                        + "[23456789CFGHJMPQRVWX]{8})"
                        + "\\+[23456789CFGHJMPQRVWX]{2,3}"
                        + "(?:\\s*,\\s*.+)?$")
                .matcher(value.trim())
                .matches();
    }

    private static Double coordinate(Object value) {
        if (value == null || text(value).isBlank()) return null;
        try {
            return Double.valueOf(text(value));
        } catch (NumberFormatException exception) {
            throw new ResponseStatusException(
                    HttpStatus.BAD_REQUEST, "Hotel location coordinates are invalid");
        }
    }

    private static boolean validCoordinate(double value, double minimum, double maximum) {
        return Double.isFinite(value) && value >= minimum && value <= maximum;
    }

    static void applyGeneratedAttributes(
            Map<String, Object> attributes,
            String type,
            long listingId,
            PartnerIdentity partner,
            boolean active) {
        String providerCode = switch (partner.slug().toLowerCase(Locale.ROOT)
                .replaceAll("[^a-z0-9]", "")) {
            case "libyanairlines" -> "LN";
            case "afriqiyahairlines", "afriqiyahairways" -> "8U";
            case "buraqair", "buraqairways" -> "UZ";
            case "libyanwings" -> "YL";
            default -> {
                String normalized = partner.slug()
                        .replaceAll("[^A-Za-z0-9]", "")
                        .toUpperCase(Locale.ROOT);
                yield normalized.length() < 2
                        ? normalized
                        : normalized.substring(0, 2);
            }
        };
        if (providerCode.isBlank()) providerCode = "P" + partner.id();
        String prefix = switch (type) {
            case "flight" -> "FL-" + providerCode;
            case "hotel" -> "HTL";
            case "car" -> "CAR";
            case "attraction" -> "ACT";
            case "transfer" -> "TRF";
            case "package" -> "PKG";
            default -> throw new IllegalStateException("Unsupported listing type.");
        };
        String sequence = String.format(Locale.ROOT, "%06d", listingId);
        attributes.put("listing_code", prefix + "-" + sequence);
        if ("flight".equals(type)) {
            attributes.put("airline_code", providerCode);
            attributes.put("flight_number", providerCode + "-" + listingId);
        }
        attributes.put("status", active ? "published" : "paused");
        attributes.put("is_active", active);
    }

    @GetMapping("/inventory/{type}")
    public Map<String, Object> publicInventory(
            @PathVariable String type,
            @RequestParam(required = false) String city) {
        String normalizedType = normalizeListingType(type);
        String hotelReviewJoin = "hotel".equals(normalizedType) ? """
                LEFT JOIN (
                    SELECT item_id, AVG(rating) AS aggregated_rating,
                           COUNT(*) AS aggregated_review_count
                    FROM user_reviews
                    WHERE item_type = 'hotel'
                    GROUP BY item_id
                ) review_summary ON review_summary.item_id = CONCAT('partner-', l.id)
                """ : "";
        String hotelReviewColumns = "hotel".equals(normalizedType)
                ? ", COALESCE(review_summary.aggregated_rating, 0) AS aggregated_rating, "
                        + "COALESCE(review_summary.aggregated_review_count, 0) AS aggregated_review_count"
                : "";
        String sql = """
                SELECT l.*, p.name AS partner_name, p.slug AS partner_slug
                """ + hotelReviewColumns + """
                FROM partner_listings l
                JOIN partners p ON p.id = l.partner_id AND p.status = 'active'
                """ + hotelReviewJoin + """
                WHERE l.type = ? AND l.active = TRUE
                """ + (city == null || city.isBlank()
                        ? " ORDER BY l.updated_at DESC"
                        : " AND (LOWER(l.city) = LOWER(?) OR l.city = '')"
                                + " ORDER BY l.updated_at DESC");
        List<Map<String, Object>> rows = city == null || city.isBlank()
                ? jdbc.queryForList(sql, normalizedType)
                : jdbc.queryForList(sql, normalizedType, city.trim());
        return Map.of("items", rows.stream()
                .map(row -> publicListing(row, normalizedType))
                .toList());
    }

    @GetMapping("/airports/search")
    public Map<String, Object> searchAirports(
            @RequestParam(defaultValue = "") String query) {
        String normalizedQuery = query.trim().toLowerCase(Locale.ROOT);
        String pattern = "%" + normalizedQuery + "%";
        List<Map<String, Object>> airports = jdbc.queryForList("""
                SELECT code, city, airport_name, country, region
                FROM airports
                WHERE ? = '' OR LOWER(code) LIKE ? OR LOWER(city) LIKE ?
                      OR LOWER(airport_name) LIKE ? OR LOWER(country) LIKE ?
                      OR LOWER(region) LIKE ?
                ORDER BY city, code
                LIMIT 50
                """, normalizedQuery, pattern, pattern, pattern, pattern, pattern);
        return Map.of("airports", airports);
    }

    @GetMapping("/flights/search")
    public Map<String, Object> searchFlights(
            @RequestParam String origin,
            @RequestParam String destination,
            @RequestParam(name = "departure_date") String departureDate,
            @RequestParam(name = "return_date", required = false) String returnDate,
            @RequestParam(defaultValue = "1") int adults,
            @RequestParam(name = "seat_class", defaultValue = "economy") String seatClass) {
        String originCode = origin.trim().toUpperCase(Locale.ROOT);
        String destinationCode = destination.trim().toUpperCase(Locale.ROOT);
        if (!originCode.matches("[A-Z0-9]{3}")
                || !destinationCode.matches("[A-Z0-9]{3}")
                || originCode.equals(destinationCode)
                || adults < 1 || adults > 9) {
            throw new ResponseStatusException(
                    HttpStatus.BAD_REQUEST, "Invalid flight search parameters");
        }
        LocalDate requestedDeparture = parseFlightDate(departureDate, "departure_date");
        if (returnDate != null && !returnDate.isBlank()
                && parseFlightDate(returnDate, "return_date").isBefore(requestedDeparture)) {
            throw new ResponseStatusException(
                    HttpStatus.BAD_REQUEST, "return_date must not precede departure_date");
        }
        String normalizedClass = seatClass.trim().toLowerCase(Locale.ROOT);
        if (!Set.of("economy", "business", "first").contains(normalizedClass)) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "Unsupported seat_class");
        }
        List<Map<String, Object>> rows = jdbc.queryForList("""
                SELECT l.*, p.name AS partner_name, p.slug AS partner_slug
                FROM partner_listings l
                JOIN partners p ON p.id = l.partner_id AND p.status = 'active'
                WHERE l.type = 'flight' AND l.active = TRUE
                ORDER BY l.updated_at DESC
                """);
        List<Map<String, Object>> flights = new java.util.ArrayList<>();
        for (Map<String, Object> row : rows) {
            Map<String, Object> details = attributes(row.get("attributes"));
            if (!originCode.equalsIgnoreCase(text(details.get("origin_code")))
                    || !destinationCode.equalsIgnoreCase(
                            text(details.get("destination_code")))) {
                continue;
            }
            String departureTime = text(details.get("departure_time"));
            if (departureTime.length() < 10
                    || !requestedDeparture.equals(
                            parseFlightDate(departureTime.substring(0, 10), "departure_time"))) {
                continue;
            }
            Object rawSeats = details.get("seats_available");
            if (rawSeats != null && intValue(rawSeats) < adults) continue;
            String priceKey = switch (normalizedClass) {
                case "business" -> "business_price";
                case "first" -> "first_price";
                default -> null;
            };
            if (priceKey != null && details.get(priceKey) == null) continue;
            Map<String, Object> flight = publicListing(row, "flight");
            if (priceKey != null) flight.put("economy_price", details.get(priceKey));
            flights.add(flight);
        }
        return Map.of("flights", flights);
    }

    private static LocalDate parseFlightDate(String value, String field) {
        try {
            return LocalDate.parse(value.trim());
        } catch (DateTimeParseException exception) {
            throw new ResponseStatusException(
                    HttpStatus.BAD_REQUEST, field + " must use YYYY-MM-DD format");
        }
    }

    private static int intValue(Object value) {
        if (value instanceof Number number) return number.intValue();
        try {
            return Integer.parseInt(text(value));
        } catch (NumberFormatException exception) {
            return 0;
        }
    }

    @GetMapping("/hotels/locations")
    public Map<String, Object> hotelLocations(
            @RequestParam String query) {
        String normalizedQuery = query.trim().toLowerCase(Locale.ROOT);
        if (normalizedQuery.length() < 2) return Map.of("suggestions", List.of());
        String pattern = "%" + normalizedQuery + "%";
        List<Map<String, Object>> rows = jdbc.queryForList("""
                SELECT l.city, l.title, l.attributes
                FROM partner_listings l
                JOIN partners p ON p.id = l.partner_id AND p.status = 'active'
                WHERE l.type = 'hotel' AND l.active = TRUE
                  AND (LOWER(l.city) LIKE ? OR LOWER(l.title) LIKE ?
                       OR LOWER(JSON_UNQUOTE(JSON_EXTRACT(l.attributes, '$.address'))) LIKE ?
                       OR LOWER(JSON_UNQUOTE(JSON_EXTRACT(l.attributes, '$.district'))) LIKE ?
                       OR LOWER(JSON_UNQUOTE(JSON_EXTRACT(l.attributes, '$.neighborhood'))) LIKE ?
                       OR LOWER(JSON_UNQUOTE(JSON_EXTRACT(l.attributes, '$.landmark'))) LIKE ?)
                ORDER BY l.city, l.title
                LIMIT 50
                """, pattern, pattern, pattern, pattern, pattern, pattern);
        Set<String> suggestions = new java.util.LinkedHashSet<>();
        for (Map<String, Object> row : rows) {
            String city = text(row.get("city")).trim();
            Map<String, Object> listingAttributes = attributes(row.get("attributes"));
            addLocationSuggestion(suggestions, city, normalizedQuery);
            for (String key : List.of("district", "neighborhood", "landmark", "address")) {
                addLocationSuggestion(
                        suggestions, text(listingAttributes.get(key)), normalizedQuery);
            }
            addLocationSuggestion(suggestions, text(row.get("title")), normalizedQuery);
        }
        return Map.of("suggestions", suggestions.stream().limit(12).toList());
    }

    @GetMapping("/hotels/search")
    public Map<String, Object> searchHotels(
            @RequestParam(defaultValue = "") String city) {
        List<Map<String, Object>> rows = hotelSearchRows(city.trim());
        return Map.of("hotels", rows.stream()
                .map(row -> publicListing(row, "hotel"))
                .toList());
    }

    @GetMapping("/hotels/nearby")
    public Map<String, Object> nearbyHotels(
            @RequestParam double lat,
            @RequestParam double lng,
            @RequestParam(defaultValue = "50000") double radius) {
        if (!validCoordinate(lat, -90, 90) || !validCoordinate(lng, -180, 180)
                || !Double.isFinite(radius) || radius <= 0 || radius > 100_000) {
            throw new ResponseStatusException(
                    HttpStatus.BAD_REQUEST, "Invalid coordinates or search radius");
        }
        List<Map<String, Object>> rows = jdbc.queryForList("""
                SELECT l.*, p.name AS partner_name, p.slug AS partner_slug,
                       COALESCE(review_summary.aggregated_rating, 0) AS aggregated_rating,
                       COALESCE(review_summary.aggregated_review_count, 0)
                           AS aggregated_review_count
                FROM partner_listings l
                JOIN partners p ON p.id = l.partner_id AND p.status = 'active'
                LEFT JOIN (
                    SELECT item_id, AVG(rating) AS aggregated_rating,
                           COUNT(*) AS aggregated_review_count
                    FROM user_reviews
                    WHERE item_type = 'hotel'
                    GROUP BY item_id
                ) review_summary ON review_summary.item_id = CONCAT('partner-', l.id)
                WHERE l.type = 'hotel' AND l.active = TRUE
                ORDER BY aggregated_rating DESC, l.updated_at DESC
                """);
        List<Map<String, Object>> nearbyRows = new java.util.ArrayList<>();
        for (Map<String, Object> row : rows) {
            Map<String, Object> normalized = new LinkedHashMap<>(row);
            Map<String, Object> listingAttributes = attributes(row.get("attributes"));
            HotelCoordinates coordinates = hotelCoordinates(listingAttributes);
            if (coordinates == null) {
                LOG.warn("Skipping hotel listing {} in nearby search: "
                                + "no valid latitude/longitude was found",
                        row.get("id"));
                continue;
            }
            double distance = distanceMeters(
                    lat, lng, coordinates.latitude(), coordinates.longitude());
            if (distance > radius) continue;
            listingAttributes.put("latitude", coordinates.latitude());
            listingAttributes.put("longitude", coordinates.longitude());
            normalized.put("attributes", listingAttributes);
            normalized.put("distance_meters", distance);
            nearbyRows.add(normalized);
        }
        nearbyRows.sort((first, second) -> {
            int distanceComparison = Double.compare(
                    doubleValue(first.get("distance_meters")),
                    doubleValue(second.get("distance_meters")));
            return distanceComparison != 0
                    ? distanceComparison
                    : Double.compare(
                            doubleValue(second.get("aggregated_rating")),
                            doubleValue(first.get("aggregated_rating")));
        });
        return Map.of("hotels", nearbyRows.stream()
                .map(row -> publicListing(row, "hotel"))
                .toList());
    }

    @GetMapping("/cars/locations")
    public Map<String, Object> carLocations(@RequestParam String query) {
        String normalizedQuery = query.trim().toLowerCase(Locale.ROOT);
        if (normalizedQuery.length() < 2) return Map.of("suggestions", List.of());
        String pattern = "%" + normalizedQuery + "%";
        List<Map<String, Object>> rows = jdbc.queryForList("""
                SELECT l.city, l.title, l.attributes
                FROM partner_listings l
                JOIN partners p ON p.id = l.partner_id AND p.status = 'active'
                WHERE l.type = 'car' AND l.active = TRUE
                  AND (LOWER(l.city) LIKE ? OR LOWER(l.title) LIKE ?
                       OR LOWER(JSON_UNQUOTE(JSON_EXTRACT(
                           l.attributes, '$.pickup_location'))) LIKE ?
                       OR LOWER(JSON_UNQUOTE(JSON_EXTRACT(
                           l.attributes, '$.district'))) LIKE ?
                       OR LOWER(JSON_UNQUOTE(JSON_EXTRACT(
                           l.attributes, '$.neighborhood'))) LIKE ?
                       OR LOWER(JSON_UNQUOTE(JSON_EXTRACT(
                           l.attributes, '$.landmark'))) LIKE ?)
                ORDER BY l.city, l.title
                LIMIT 50
                """, pattern, pattern, pattern, pattern, pattern, pattern);
        Set<String> suggestions = new java.util.LinkedHashSet<>();
        for (Map<String, Object> row : rows) {
            String city = text(row.get("city")).trim();
            Map<String, Object> listingAttributes = attributes(row.get("attributes"));
            addLocationSuggestion(suggestions, city, normalizedQuery);
            for (String key : List.of(
                    "pickup_location", "district", "neighborhood", "landmark")) {
                addLocationSuggestion(
                        suggestions, text(listingAttributes.get(key)), normalizedQuery);
            }
            addLocationSuggestion(suggestions, text(row.get("title")), normalizedQuery);
        }
        return Map.of("suggestions", suggestions.stream().limit(12).toList());
    }

    @GetMapping("/cars/nearby")
    public Map<String, Object> nearbyCars(
            @RequestParam double lat,
            @RequestParam double lng,
            @RequestParam(defaultValue = "50000") double radius,
            @RequestParam(defaultValue = "all") String carType) {
        if (!validCoordinate(lat, -90, 90) || !validCoordinate(lng, -180, 180)
                || !Double.isFinite(radius) || radius <= 0 || radius > 100_000) {
            throw new ResponseStatusException(
                    HttpStatus.BAD_REQUEST, "Invalid coordinates or search radius");
        }
        List<Map<String, Object>> rows = jdbc.queryForList("""
                SELECT l.*, p.name AS partner_name, p.slug AS partner_slug
                FROM partner_listings l
                JOIN partners p ON p.id = l.partner_id AND p.status = 'active'
                WHERE l.type = 'car' AND l.active = TRUE
                ORDER BY l.updated_at DESC
                """);
        List<Map<String, Object>> nearbyRows = new java.util.ArrayList<>();
        for (Map<String, Object> row : rows) {
            Map<String, Object> listingAttributes = attributes(row.get("attributes"));
            if (!"all".equalsIgnoreCase(carType)
                    && !carType.equalsIgnoreCase(
                            text(listingAttributes.get("category")))) {
                continue;
            }
            Double latitude = tryCoordinate(listingAttributes.get("latitude"));
            Double longitude = tryCoordinate(listingAttributes.get("longitude"));
            if (!validCoordinatePair(latitude, longitude)) {
                LOG.warn("Skipping car listing {} in nearby search: "
                                + "no valid pickup latitude/longitude was found",
                        row.get("id"));
                continue;
            }
            double distance = distanceMeters(lat, lng, latitude, longitude);
            if (distance > radius) continue;
            Map<String, Object> nearby = new LinkedHashMap<>(row);
            listingAttributes.put("latitude", latitude);
            listingAttributes.put("longitude", longitude);
            nearby.put("attributes", listingAttributes);
            nearby.put("distance_meters", distance);
            nearbyRows.add(nearby);
        }
        nearbyRows.sort(Comparator.comparingDouble(
                row -> doubleValue(row.get("distance_meters"))));
        return Map.of("cars", nearbyRows.stream()
                .map(row -> publicListing(row, "car"))
                .toList());
    }

    private static HotelCoordinates hotelCoordinates(Map<String, Object> attributes) {
        Double latitude = tryCoordinate(attributes.get("latitude"));
        Double longitude = tryCoordinate(attributes.get("longitude"));
        if (validCoordinatePair(latitude, longitude)) {
            return new HotelCoordinates(latitude, longitude);
        }

        String input = text(attributes.get("location_input"))
                .replace("%2C", ",")
                .replace("%2c", ",");
        Pattern pattern = Pattern.compile(
                "!3d(-?\\d{1,2}(?:\\.\\d+)?)!4d(-?\\d{1,3}(?:\\.\\d+)?)"
                        + "|@(-?\\d{1,2}(?:\\.\\d+)?),\\s*(-?\\d{1,3}(?:\\.\\d+)?)"
                        + "|[?&](?:q|query|center)=(-?\\d{1,2}(?:\\.\\d+)?),"
                        + "\\s*(-?\\d{1,3}(?:\\.\\d+)?)"
                        + "|^\\s*(-?\\d{1,2}(?:\\.\\d+)?)\\s*,\\s*"
                        + "(-?\\d{1,3}(?:\\.\\d+)?)\\s*$",
                Pattern.CASE_INSENSITIVE);
        Matcher matcher = pattern.matcher(input);
        if (!matcher.find()) return null;
        latitude = tryCoordinate(firstGroup(matcher, 1, 3, 5, 7));
        longitude = tryCoordinate(firstGroup(matcher, 2, 4, 6, 8));
        return validCoordinatePair(latitude, longitude)
                ? new HotelCoordinates(latitude, longitude)
                : null;
    }

    private static String firstGroup(Matcher matcher, int... groups) {
        for (int group : groups) {
            String value = matcher.group(group);
            if (value != null) return value;
        }
        return "";
    }

    private static Double tryCoordinate(Object value) {
        if (value == null) return null;
        try {
            return Double.valueOf(text(value));
        } catch (NumberFormatException exception) {
            return null;
        }
    }

    private static boolean validCoordinatePair(Double latitude, Double longitude) {
        return latitude != null && longitude != null
                && validCoordinate(latitude, -90, 90)
                && validCoordinate(longitude, -180, 180)
                && !(latitude == 0 && longitude == 0);
    }

    private static double distanceMeters(
            double fromLatitude,
            double fromLongitude,
            double toLatitude,
            double toLongitude) {
        double latitudeDelta = Math.toRadians(toLatitude - fromLatitude);
        double longitudeDelta = Math.toRadians(toLongitude - fromLongitude);
        double a = Math.pow(Math.sin(latitudeDelta / 2), 2)
                + Math.cos(Math.toRadians(fromLatitude))
                        * Math.cos(Math.toRadians(toLatitude))
                        * Math.pow(Math.sin(longitudeDelta / 2), 2);
        double bounded = Math.min(1, Math.max(0, a));
        return 6_371_000 * 2
                * Math.atan2(Math.sqrt(bounded), Math.sqrt(1 - bounded));
    }

    private record HotelCoordinates(double latitude, double longitude) {}

    private List<Map<String, Object>> hotelSearchRows(String query) {
        String pattern = "%" + query.toLowerCase(Locale.ROOT) + "%";
        return jdbc.queryForList("""
                SELECT l.*, p.name AS partner_name, p.slug AS partner_slug,
                       COALESCE(review_summary.aggregated_rating, 0) AS aggregated_rating,
                       COALESCE(review_summary.aggregated_review_count, 0)
                           AS aggregated_review_count
                FROM partner_listings l
                JOIN partners p ON p.id = l.partner_id AND p.status = 'active'
                LEFT JOIN (
                    SELECT item_id, AVG(rating) AS aggregated_rating,
                           COUNT(*) AS aggregated_review_count
                    FROM user_reviews
                    WHERE item_type = 'hotel'
                    GROUP BY item_id
                ) review_summary ON review_summary.item_id = CONCAT('partner-', l.id)
                WHERE l.type = 'hotel' AND l.active = TRUE
                  AND (? = '' OR LOWER(l.city) LIKE ? OR LOWER(l.title) LIKE ?
                       OR LOWER(JSON_UNQUOTE(JSON_EXTRACT(l.attributes, '$.address'))) LIKE ?
                       OR LOWER(JSON_UNQUOTE(JSON_EXTRACT(l.attributes, '$.district'))) LIKE ?
                       OR LOWER(JSON_UNQUOTE(JSON_EXTRACT(l.attributes, '$.neighborhood'))) LIKE ?
                       OR LOWER(JSON_UNQUOTE(JSON_EXTRACT(l.attributes, '$.landmark'))) LIKE ?)
                ORDER BY aggregated_rating DESC, l.updated_at DESC
                """, query, pattern, pattern, pattern, pattern, pattern, pattern);
    }

    private static void addLocationSuggestion(
            Set<String> suggestions, String value, String query) {
        String normalized = value.trim();
        if (!normalized.isEmpty()
                && normalized.toLowerCase(Locale.ROOT).contains(query)) {
            suggestions.add(normalized);
        }
    }

    @GetMapping("/partner/dashboard")
    public Map<String, Object> dashboard(HttpServletRequest request) {
        PartnerIdentity partner = requirePartner(request);
        Map<String, Object> summary = jdbc.queryForMap("""
                SELECT
                    (SELECT COUNT(*) FROM partner_listings
                        WHERE partner_id = ?) AS listing_count,
                    (SELECT COUNT(*) FROM partner_listings
                        WHERE partner_id = ? AND active = TRUE) AS active_listing_count,
                    (SELECT COUNT(*) FROM trips
                        WHERE partner_id = ? AND LOWER(status) <> 'cancelled')
                      + (SELECT COUNT(*) FROM bookings
                        WHERE partner_id = ? AND LOWER(status) <> 'cancelled')
                      + (SELECT COUNT(*) FROM transfers
                        WHERE partner_id = ? AND LOWER(status) <> 'cancelled')
                        AS reservation_count,
                    (SELECT COUNT(*) FROM users u
                        WHERE u.role = 'customer' AND EXISTS (
                            SELECT 1 FROM trips t
                            WHERE t.partner_id = ? AND t.user_id = u.id
                            UNION ALL
                            SELECT 1 FROM bookings b
                            WHERE b.partner_id = ? AND b.user_id = u.id
                            UNION ALL
                            SELECT 1 FROM transfers x
                            WHERE x.partner_id = ? AND x.user_id = u.id
                        )) AS customer_count,
                    COALESCE((SELECT SUM(total_amount) FROM bookings
                        WHERE partner_id = ? AND LOWER(status) <> 'cancelled'), 0)
                      + COALESCE((SELECT SUM(price) FROM trips
                        WHERE partner_id = ? AND LOWER(status) <> 'cancelled'), 0)
                      + COALESCE((SELECT SUM(price) FROM transfers
                        WHERE partner_id = ? AND LOWER(status) <> 'cancelled'), 0)
                        AS booked_value
                """, partner.id(), partner.id(), partner.id(), partner.id(), partner.id(),
                partner.id(), partner.id(), partner.id(), partner.id(), partner.id(),
                partner.id());
        return Map.of(
                "company", Map.of(
                        "id", partner.id(),
                        "name", partner.name(),
                        "service_type", partner.serviceType()),
                "summary", summary,
                "recent_reservations", reservations(partner.id(), 8));
    }

    @GetMapping("/partner/listings")
    public Map<String, Object> listings(HttpServletRequest request) {
        PartnerIdentity partner = requirePartner(request);
        List<Map<String, Object>> listings = jdbc.queryForList("""
                SELECT id, type, title, city, country, description, image_url,
                       price, active, attributes, location_name, google_maps_url,
                       place_id, google_rating, google_review_count, amenities,
                       tax_and_fees_percentage, available_rooms, created_at, updated_at,
                       COALESCE(review_summary.aggregated_rating, 0) AS aggregated_rating,
                       COALESCE(review_summary.aggregated_review_count, 0)
                           AS aggregated_review_count
                FROM partner_listings l
                LEFT JOIN (
                    SELECT item_id, AVG(rating) AS aggregated_rating,
                           COUNT(*) AS aggregated_review_count
                    FROM user_reviews
                    WHERE item_type = 'hotel'
                    GROUP BY item_id
                ) review_summary ON review_summary.item_id = CONCAT('partner-', l.id)
                WHERE partner_id = ?
                ORDER BY updated_at DESC
                """, partner.id()).stream()
                .map(row -> {
                    Map<String, Object> mutableRow = new LinkedHashMap<>();
                    mutableRow.putAll(row);
                    return mutableRow;
                })
                .toList();
        for (Map<String, Object> listing : listings) {
            Map<String, Object> listingAttributes =
                    attributes(listing.get("attributes"));
            if ("hotel".equals(text(listing.get("type")))) {
                listingAttributes.put("location_name", listing.get("location_name"));
                listingAttributes.put("google_maps_url", listing.get("google_maps_url"));
                listingAttributes.put("place_id", listing.get("place_id"));
                Object googleRating = listing.get("google_rating");
                Object googleReviewCount = listing.get("google_review_count");
                listingAttributes.put(
                        "google_rating", googleRating == null ? 0.0 : googleRating);
                listingAttributes.put(
                        "google_review_count",
                        googleReviewCount == null ? 0 : googleReviewCount);
                listingAttributes.put("amenities", stringArray(listing.get("amenities")));
                listingAttributes.put(
                        "tax_and_fees_percentage",
                        listing.get("tax_and_fees_percentage"));
                listingAttributes.put("available_rooms", listing.get("available_rooms"));
                listing.put(
                        "google_rating", googleRating == null ? 0.0 : googleRating);
                listing.put("google_review_count",
                        googleReviewCount == null ? 0 : googleReviewCount);
                listing.put("amenities", stringArray(listing.get("amenities")));
                listing.put("rating", googleRating == null ? 0.0 : googleRating);
                listing.put("review_count",
                        googleReviewCount == null ? 0 : googleReviewCount);
                listingAttributes.put(
                        "user_rating", doubleValue(listing.get("aggregated_rating")));
                listingAttributes.put(
                        "user_review_count",
                        ((Number) listing.get("aggregated_review_count")).intValue());
            } else {
                listingAttributes.remove("rating");
                listingAttributes.remove("review_count");
            }
            applyGeneratedAttributes(
                    listingAttributes,
                    text(listing.get("type")),
                    ((Number) listing.get("id")).longValue(),
                    partner,
                    bool(listing.get("active"), false));
            listing.put("attributes", listingAttributes);
        }
        return Map.of("listings", listings);
    }

    @PostMapping("/partner/listings")
    @Transactional
    public Map<String, Object> createListing(
            @RequestBody Map<String, Object> body,
            HttpServletRequest request) {
        PartnerIdentity partner = requirePartner(request);
        String type = normalizeListingType(text(body.get("type")));
        ensurePartnerCanManageType(partner, type);
        String title = required(body, "title");
        String imageUrl = listingImage(type, body.get("image_url"));
        Map<String, Object> listingAttributes =
                requestAttributes(body.get("attributes"));
        if ("hotel".equals(type)) {
            normalizeHotelListing(
                    body, listingAttributes, text(body.get("city")), title);
            normalizeHotelLocation(listingAttributes);
        }
        boolean active = bool(body.get("active"), true);
        LocationMetadata location = validateListingData(
                type,
                text(body.get("city")),
                listingAttributes);
        String country = listingCountry(type, body.get("country"), location);
        long id = insert("""
                INSERT INTO partner_listings
                    (partner_id, type, title, city, country, description, image_url,
                     price, active, attributes, location_name, google_maps_url,
                     place_id, google_rating, google_review_count, amenities,
                     tax_and_fees_percentage, available_rooms, created_at, updated_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, CAST(? AS JSON), ?, ?, ?, 0,
                        0, CAST(? AS JSON), ?, ?, NOW(), NOW())
                """, partner.id(), type, title,
                location.city(), country,
                "flight".equals(type) ? null : nullableText(body.get("description")),
                imageUrl,
                decimal(body.get("price")), active, "{}",
                "hotel".equals(type) ? nullableText(listingAttributes.get("location_name")) : null,
                "hotel".equals(type) ? nullableText(listingAttributes.get("google_maps_url")) : null,
                "hotel".equals(type) ? nullableText(listingAttributes.get("place_id")) : null,
                "hotel".equals(type)
                        ? serializeJson(listingAttributes.get("amenities"))
                        : "[]",
                "hotel".equals(type)
                        ? decimal(listingAttributes.get("tax_and_fees_percentage"))
                        : BigDecimal.valueOf(12),
                "hotel".equals(type)
                        ? listingAttributes.get("available_rooms")
                        : 0);
        applyGeneratedAttributes(listingAttributes, type, id, partner, active);
        jdbc.update("""
                UPDATE partner_listings
                SET attributes = JSON_SET(
                    CAST(? AS JSON),
                    '$.location_name', COALESCE(location_name, ''),
                    '$.google_maps_url', COALESCE(google_maps_url, ''),
                    '$.place_id', COALESCE(place_id, ''),
                    '$.google_rating', google_rating,
                    '$.google_review_count', google_review_count,
                    '$.tax_and_fees_percentage', tax_and_fees_percentage
                )
                WHERE id = ? AND partner_id = ?
                """, serializeAttributes(listingAttributes), id, partner.id());
        googlePlacesRatingSync.refreshAsync(
                id,
                title,
                text(listingAttributes.get("location_name")),
                text(listingAttributes.get("google_maps_url")),
                text(listingAttributes.get("place_id")));
        LOG.info(
                "Saved hotel listing {} and queued Google Places rating sync "
                        + "(mapsUrlPresent={}, placeIdPresent={})",
                id,
                !text(listingAttributes.get("google_maps_url")).isBlank(),
                !text(listingAttributes.get("place_id")).isBlank());
        return Map.of("listing", findListing(partner.id(), id));
    }

    @PutMapping("/partner/listings/{id}")
    @Transactional
    public Map<String, Object> updateListing(
            @PathVariable long id,
            @RequestBody Map<String, Object> body,
            HttpServletRequest request) {
        PartnerIdentity partner = requirePartner(request);
        Map<String, Object> existing = findListing(partner.id(), id);
        String type = value(body, "type", text(existing.get("type")));
        type = normalizeListingType(type);
        ensurePartnerCanManageType(partner, type);
        String imageUrl = body.containsKey("image_url")
                ? safeImageUrl(body.get("image_url"))
                : text(existing.get("image_url"));
        imageUrl = listingImage(type, imageUrl);
        Map<String, Object> listingAttributes = body.containsKey("attributes")
                ? requestAttributes(body.get("attributes"))
                : attributes(existing.get("attributes"));
        if ("hotel".equals(type)) {
            normalizeHotelListing(
                    body,
                    listingAttributes,
                    value(body, "city", text(existing.get("city"))),
                    value(body, "title", text(existing.get("title"))));
            normalizeHotelLocation(listingAttributes);
        }
        boolean active = body.containsKey("active")
                ? bool(body.get("active"), false)
                : bool(existing.get("active"), false);
        LocationMetadata location = validateListingData(
                type,
                value(body, "city", text(existing.get("city"))),
                listingAttributes);
        if ("flight".equals(type)) {
            Map<String, Object> existingAttributes =
                    attributes(existing.get("attributes"));
            String previousLayout = text(existingAttributes.get("seat_layout"));
            if (previousLayout.isBlank()) previousLayout = "3-3";
            int previousRows = aircraftInteger(
                    existingAttributes.get("seat_rows"),
                    aircraftInteger(existingAttributes.get("row_count"), 30, "row_count"),
                    "seat_rows");
            boolean aircraftLayoutChanged =
                    !previousLayout.equals(text(listingAttributes.get("seat_layout")))
                            || previousRows != intValue(listingAttributes.get("seat_rows"));
            if (aircraftLayoutChanged) {
                Integer occupiedSeats = jdbc.queryForObject("""
                        SELECT COUNT(*) FROM flight_seat_holds
                        WHERE flight_listing_id = ?
                          AND (status = 'confirmed'
                               OR (status = 'reserved' AND expires_at > NOW()))
                        """, Integer.class, id);
                if (occupiedSeats != null && occupiedSeats > 0) {
                    throw new ResponseStatusException(
                            HttpStatus.CONFLICT,
                            "Aircraft cannot be changed while seats are reserved or booked");
                }
            }
        }
        String country = listingCountry(
                type,
                body.containsKey("country") ? body.get("country") : existing.get("country"),
                location);
        applyGeneratedAttributes(listingAttributes, type, id, partner, active);
        boolean refreshGoogleRating = "hotel".equals(type)
                && (!text(existing.get("google_maps_url"))
                                .equals(text(listingAttributes.get("google_maps_url"))
                                        .trim())
                        || !text(existing.get("place_id"))
                                .equals(text(listingAttributes.get("place_id")).trim()));
        int updated = jdbc.update("""
                UPDATE partner_listings
                SET type = ?, title = ?, city = ?, country = ?, description = ?,
                    image_url = ?, price = ?, active = ?, attributes = CAST(? AS JSON),
                    location_name = ?, google_maps_url = ?, place_id = ?,
                    google_rating = IF(? = 1, 0.0, google_rating),
                    google_review_count = IF(? = 1, 0, google_review_count),
                    amenities = CAST(? AS JSON), tax_and_fees_percentage = ?,
                    available_rooms = ?,
                    updated_at = NOW()
                WHERE id = ? AND partner_id = ?
                """,
                normalizeListingType(type),
                value(body, "title", text(existing.get("title"))),
                location.city(),
                country,
                "flight".equals(type)
                        ? null
                        : body.containsKey("description")
                        ? nullableText(body.get("description"))
                        : existing.get("description"),
                imageUrl,
                body.containsKey("price") ? decimal(body.get("price"))
                        : decimal(existing.get("price")),
                active, serializeAttributes(listingAttributes),
                "hotel".equals(type) ? nullableText(listingAttributes.get("location_name")) : null,
                "hotel".equals(type) ? nullableText(listingAttributes.get("google_maps_url")) : null,
                "hotel".equals(type) ? nullableText(listingAttributes.get("place_id")) : null,
                refreshGoogleRating ? 1 : 0,
                refreshGoogleRating ? 1 : 0,
                "hotel".equals(type)
                        ? serializeJson(listingAttributes.get("amenities"))
                        : "[]",
                "hotel".equals(type)
                        ? decimal(listingAttributes.get("tax_and_fees_percentage"))
                        : BigDecimal.valueOf(12),
                "hotel".equals(type)
                        ? listingAttributes.get("available_rooms")
                        : 0,
                id, partner.id());
        if (updated != 1) {
            throw new ResponseStatusException(HttpStatus.NOT_FOUND, "Listing not found");
        }
        if (refreshGoogleRating) {
            googlePlacesRatingSync.refreshAsync(
                    id,
                    value(body, "title", text(existing.get("title"))),
                    text(listingAttributes.get("location_name")),
                    text(listingAttributes.get("google_maps_url")),
                    text(listingAttributes.get("place_id")));
            LOG.info(
                    "Updated hotel listing {} location and queued Google Places "
                            + "rating sync (mapsUrlPresent={}, placeIdPresent={})",
                    id,
                    !text(listingAttributes.get("google_maps_url")).isBlank(),
                    !text(listingAttributes.get("place_id")).isBlank());
        }
        return Map.of("listing", findListing(partner.id(), id));
    }

    @DeleteMapping("/partner/listings/{id}")
    @Transactional
    public Map<String, Object> deactivateListing(
            @PathVariable long id,
            HttpServletRequest request) {
        PartnerIdentity partner = requirePartner(request);
        int updated = jdbc.update("""
                UPDATE partner_listings SET active = FALSE, updated_at = NOW()
                WHERE id = ? AND partner_id = ?
                """, id, partner.id());
        if (updated != 1) {
            throw new ResponseStatusException(HttpStatus.NOT_FOUND, "Listing not found");
        }
        return Map.of("status", "inactive");
    }

    @GetMapping("/partner/reservations")
    public Map<String, Object> partnerReservations(
            @RequestParam(defaultValue = "50") int limit,
            HttpServletRequest request) {
        PartnerIdentity partner = requirePartner(request);
        validateLimit(limit);
        return Map.of("reservations", reservations(partner.id(), limit));
    }

    @GetMapping("/partner/customers")
    public Map<String, Object> customers(
            @RequestParam(defaultValue = "50") int limit,
            HttpServletRequest request) {
        PartnerIdentity partner = requirePartner(request);
        validateLimit(limit);
        List<Map<String, Object>> rows = jdbc.queryForList("""
                SELECT u.id, u.name, u.email, u.phone, u.created_at,
                    COUNT(reservations.id) AS reservation_count
                FROM (
                    SELECT user_id, id FROM trips WHERE partner_id = ?
                    UNION ALL
                    SELECT user_id, id FROM bookings WHERE partner_id = ?
                    UNION ALL
                    SELECT user_id, id FROM transfers WHERE partner_id = ?
                ) reservations
                JOIN users u ON u.id = reservations.user_id
                WHERE u.role = 'customer'
                GROUP BY u.id, u.name, u.email, u.phone, u.created_at
                ORDER BY MAX(reservations.id) DESC
                LIMIT ?
                """, partner.id(), partner.id(), partner.id(), limit);
        return Map.of("customers", rows);
    }

    private List<Map<String, Object>> reservations(long partnerId, int limit) {
        return jdbc.queryForList("""
                SELECT *
                FROM (
                    SELECT CONCAT('flight-', t.id) AS id, t.id AS reservation_id,
                        t.partner_listing_id, 'flight' AS type, t.title,
                        u.id AS customer_id, u.name AS customer_name,
                        u.email AS customer_email, u.phone AS customer_phone,
                        COALESCE(t.departure_date, t.created_at) AS reservation_date,
                        COALESCE(t.price, 0) AS amount, t.status, t.created_at
                    FROM trips t JOIN users u ON u.id = t.user_id
                    WHERE t.partner_id = ?
                    UNION ALL
                    SELECT CONCAT('booking-', b.id) AS id, b.id AS reservation_id,
                        b.partner_listing_id, b.type,
                        COALESCE(b.title, b.subtitle, 'Booking') AS title,
                        u.id AS customer_id, u.name AS customer_name,
                        u.email AS customer_email, u.phone AS customer_phone,
                        COALESCE(b.date, b.created_at) AS reservation_date,
                        COALESCE(b.total_amount, b.price, 0) AS amount,
                        b.status, b.created_at
                    FROM bookings b JOIN users u ON u.id = b.user_id
                    WHERE b.partner_id = ?
                    UNION ALL
                    SELECT CONCAT('transfer-', x.id) AS id, x.id AS reservation_id,
                        x.partner_listing_id, 'transfer' AS type,
                        CONCAT(x.pickup_location, ' to ', x.dropoff_location) AS title,
                        u.id AS customer_id, u.name AS customer_name,
                        u.email AS customer_email, u.phone AS customer_phone,
                        x.pickup_time AS reservation_date, x.price AS amount,
                        x.status, x.created_at
                    FROM transfers x JOIN users u ON u.id = x.user_id
                    WHERE x.partner_id = ?
                ) reservations
                ORDER BY created_at DESC
                LIMIT ?
                """, partnerId, partnerId, partnerId, limit);
    }

    private Map<String, Object> publicListing(
            Map<String, Object> row,
            String type) {
        Map<String, Object> listing = new LinkedHashMap<>(attributes(row.get("attributes")));
        long id = ((Number) row.get("id")).longValue();
        String title = text(row.get("title"));
        String city = text(row.get("city"));
        String country = text(row.get("country"));
        String partnerName = text(row.get("partner_name"));
        Object partnerSlug = row.get("partner_slug");
        if (partnerSlug != null) {
            applyGeneratedAttributes(
                    listing,
                    type,
                    id,
                    new PartnerIdentity(0, partnerName, "", text(partnerSlug)),
                    true);
        }
        listing.put("id", "partner-" + id);
        listing.put("partner_listing_id", id);
        listing.put("partner_name", partnerName);
        listing.put("city", city);
        listing.put("country", country);
        listing.put("description",
                "flight".equals(type) ? "" : text(row.get("description")));
        listing.put("image_url", "flight".equals(type) ? null : row.get("image_url"));
        switch (type) {
            case "flight" -> {
                listing.put("airline", partnerName);
                listing.put("title", title);
                listing.put("origin_city", value(listing, "origin_city", city));
                listing.put("origin_code", value(listing, "origin_code", ""));
                listing.put("destination_city",
                        value(listing, "destination_city", ""));
                listing.put("destination_code",
                        value(listing, "destination_code", ""));
                listing.putIfAbsent("flight_number", "");
                listing.putIfAbsent("airline_code", "");
                listing.put("status", "published");
                listing.put("is_active", true);
                listing.put("economy_price", row.get("price"));
                listing.put("airline_logo_url", null);
            }
            case "hotel" -> {
                String locationName = text(row.get("location_name"));
                if (locationName.isBlank()) {
                    locationName = value(listing, "location_name",
                            value(listing, "address", city));
                }
                String googleMapsUrl = text(row.get("google_maps_url"));
                if (googleMapsUrl.isBlank()) {
                    googleMapsUrl = value(listing, "google_maps_url",
                            value(listing, "location_input", ""));
                }
                String placeId = text(row.get("place_id"));
                if (placeId.isBlank()) {
                    placeId = value(listing, "place_id",
                            value(listing, "google_place_id", ""));
                }
                Object rawGoogleReviewCount = row.get("google_review_count");
                Integer googleReviewCount = rawGoogleReviewCount instanceof Number count
                        ? count.intValue() : null;
                Object rawAmenities = row.get("amenities") == null
                        ? listing.get("amenities") : row.get("amenities");
                HotelListing hotel = new HotelListing(
                        "partner-" + id,
                        title,
                        locationName,
                        googleMapsUrl,
                        placeId,
                        nullableDecimal(row.get("google_rating")),
                        googleReviewCount,
                        stringArray(rawAmenities),
                        text(row.get("description")),
                        decimal(row.get("price")),
                        row.get("tax_and_fees_percentage") == null
                                ? BigDecimal.valueOf(12)
                                : decimal(row.get("tax_and_fees_percentage")),
                        row.get("available_rooms") instanceof Number rooms
                                ? rooms.intValue() : 0);
                listing.put("name", hotel.name());
                listing.put("location_name", hotel.locationName());
                listing.put("address", hotel.locationName());
                listing.put("google_maps_url", hotel.googleMapsUrl());
                listing.put("place_id", hotel.placeId());
                listing.put("google_rating", hotel.googleRating() == null
                        ? 0.0 : hotel.googleRating().doubleValue());
                listing.put("google_review_count",
                        hotel.googleReviewCount() == null ? 0 : hotel.googleReviewCount());
                listing.put("price_per_night", hotel.pricePerNight());
                listing.put("tax_and_fees_percentage", hotel.taxAndFeesPercentage());
                listing.put("available_rooms", hotel.availableRooms());
                listing.put("amenities", hotel.amenities());
                listing.put("rating", hotel.googleRating() == null
                        ? 0.0 : hotel.googleRating().doubleValue());
                listing.put("review_count", hotel.googleReviewCount() == null
                        ? 0 : hotel.googleReviewCount());
                listing.put("user_rating",
                        doubleValue(row.get("aggregated_rating")));
                listing.put("user_review_count",
                        row.get("aggregated_review_count") == null
                                ? 0 : ((Number) row.get("aggregated_review_count")).intValue());
                listing.putIfAbsent("stars", 0);
                listing.put("status", "published");
                listing.put("is_active", true);
                if (row.get("distance_meters") != null) {
                    listing.put("distance_meters",
                            ((Number) row.get("distance_meters")).doubleValue());
                }
            }
            case "car" -> {
                listing.putIfAbsent("brand", partnerName);
                listing.putIfAbsent("model", title);
                listing.putIfAbsent("category", "economy");
                listing.putIfAbsent("year", 2026);
                listing.put("price_per_day", row.get("price"));
                listing.putIfAbsent("seats", 4);
                listing.putIfAbsent("luggage_capacity", 2);
                listing.putIfAbsent("transmission", "automatic");
                listing.putIfAbsent("fuel_type", "gasoline");
                listing.putIfAbsent("features", List.of());
                listing.putIfAbsent("rating", 0);
                listing.putIfAbsent("insurance_fee", 4);
                listing.putIfAbsent("service_fee", 10);
                listing.putIfAbsent("available_vehicles", 1);
                listing.put("pickup_location", value(listing, "pickup_location", city));
                listing.putIfAbsent("has_ac", true);
                listing.putIfAbsent("has_gps", false);
                listing.put("status", "published");
                listing.put("is_active", true);
            }
            case "attraction" -> {
                listing.put("name", title);
                listing.put("entry_fee", row.get("price"));
                listing.putIfAbsent("category", "landmark");
                listing.putIfAbsent("rating", 0);
                listing.putIfAbsent("review_count", 0);
                listing.putIfAbsent("latitude", 0);
                listing.putIfAbsent("longitude", 0);
                listing.putIfAbsent("tags", List.of());
                listing.putIfAbsent("opening_hours", "");
                listing.put("status", "published");
                listing.put("is_active", true);
            }
            case "transfer" -> {
                listing.put("provider_name", partnerName);
                listing.put("vehicle_name", title);
                listing.put("vehicle_type", value(listing, "vehicle_type", "sedan"));
                listing.put("price", row.get("price"));
                listing.putIfAbsent("max_passengers", 4);
                listing.putIfAbsent("max_luggage", 2);
                listing.putIfAbsent("pickup_location", city);
                listing.putIfAbsent("dropoff_location", "");
                listing.putIfAbsent("duration_minutes", 60);
                listing.putIfAbsent("included_services", List.of());
                listing.put("status", "published");
                listing.put("is_active", true);
                listing.put("vehicle_image_url", row.get("image_url"));
            }
            case "package" -> {
                listing.put("title", title);
                listing.put("location", city);
                listing.put("country", country);
                listing.put("flight_price_per_person", row.get("price"));
                listing.put("hotel_price_per_night", 0);
                listing.putIfAbsent("duration_nights", 1);
                listing.putIfAbsent("highlights", List.of());
                listing.put("status", "published");
                listing.put("is_active", true);
            }
            default -> throw new IllegalStateException("Unsupported listing type.");
        }
        return listing;
    }

    private Map<String, Object> findListing(long partnerId, long id) {
        try {
            Map<String, Object> listing = jdbc.queryForMap("""
                    SELECT id, partner_id, type, title, city, country, description,
                           image_url, price, active, attributes, location_name,
                           google_maps_url, place_id, google_rating,
                           google_review_count, amenities, tax_and_fees_percentage,
                           available_rooms, created_at, updated_at,
                           COALESCE((SELECT AVG(rating) FROM user_reviews
                               WHERE item_type = 'hotel'
                                 AND item_id = CONCAT('partner-', partner_listings.id)), 0)
                               AS aggregated_rating,
                           COALESCE((SELECT COUNT(*) FROM user_reviews
                               WHERE item_type = 'hotel'
                                 AND item_id = CONCAT('partner-', partner_listings.id)), 0)
                               AS aggregated_review_count
                    FROM partner_listings
                    WHERE id = ? AND partner_id = ?
                    """, id, partnerId);
            Map<String, Object> listingAttributes =
                    attributes(listing.get("attributes"));
            if ("hotel".equals(text(listing.get("type")))) {
                Object googleRating = listing.get("google_rating");
                Object googleReviewCount = listing.get("google_review_count");
                int availableRooms = ((Number) listing.get("available_rooms")).intValue();
                listingAttributes.put("name", listing.get("title"));
                listingAttributes.put("location_name", listing.get("location_name"));
                listingAttributes.put("google_maps_url", listing.get("google_maps_url"));
                listingAttributes.put("place_id", listing.get("place_id"));
                listingAttributes.put("google_rating",
                        googleRating == null ? 0.0 : googleRating);
                listingAttributes.put("google_review_count",
                        googleReviewCount == null ? 0 : googleReviewCount);
                listingAttributes.put("amenities", stringArray(listing.get("amenities")));
                listingAttributes.put(
                        "tax_and_fees_percentage", listing.get("tax_and_fees_percentage"));
                listingAttributes.put("available_rooms", availableRooms);
                listingAttributes.put(
                        "rating",
                        googleRating == null ? 0.0 : doubleValue(googleRating));
                listingAttributes.put(
                        "review_count",
                        googleReviewCount == null
                                ? 0 : ((Number) googleReviewCount).intValue());
                listing.put("google_rating", googleRating == null ? 0.0 : googleRating);
                listing.put("google_review_count",
                        googleReviewCount == null ? 0 : googleReviewCount);
                listing.put("amenities", stringArray(listing.get("amenities")));
                listing.put("available_rooms", availableRooms);
                listing.put("rating", googleRating == null ? 0.0 : googleRating);
                listing.put("review_count",
                        googleReviewCount == null
                                ? 0 : ((Number) googleReviewCount).intValue());
            }
            listing.put("attributes", listingAttributes);
            return listing;
        } catch (org.springframework.dao.EmptyResultDataAccessException exception) {
            throw new ResponseStatusException(HttpStatus.NOT_FOUND, "Listing not found");
        }
    }

    private PartnerIdentity requirePartner(HttpServletRequest request) {
        Object userId = request.getAttribute("authUserId");
        if (!(userId instanceof Number number)) {
            throw new ResponseStatusException(HttpStatus.UNAUTHORIZED, "Unauthenticated");
        }
        try {
            Map<String, Object> user = jdbc.queryForMap("""
                    SELECT u.partner_id, p.name, p.service_type, p.slug
                    FROM users u JOIN partners p ON p.id = u.partner_id
                    WHERE u.id = ? AND u.role = 'partner' AND p.status = 'active'
                    """, number.longValue());
            return new PartnerIdentity(
                    ((Number) user.get("partner_id")).longValue(),
                    text(user.get("name")),
                    text(user.get("service_type")),
                    text(user.get("slug")));
        } catch (org.springframework.dao.EmptyResultDataAccessException exception) {
            throw new ResponseStatusException(
                    HttpStatus.FORBIDDEN, "Active partner access required");
        }
    }

    private static void ensurePartnerCanManageType(
            PartnerIdentity partner, String listingType) {
        String requiredService = switch (listingType) {
            case "flight" -> "airline";
            case "hotel" -> "hotel";
            case "car" -> "car";
            case "attraction" -> "attraction";
            case "transfer" -> "transfer";
            case "package" -> "travel";
            default -> throw new ResponseStatusException(
                    HttpStatus.BAD_REQUEST, "Unsupported listing type");
        };
        if (!requiredService.equals(partner.serviceType())) {
            throw new ResponseStatusException(
                    HttpStatus.FORBIDDEN, "This company cannot manage that listing type");
        }
    }

    private static String normalizeListingType(String type) {
        String normalized = type.trim().toLowerCase(Locale.ROOT);
        if (!LISTING_TYPES.contains(normalized)) {
            throw new ResponseStatusException(
                    HttpStatus.BAD_REQUEST, "Unsupported listing type");
        }
        return normalized;
    }

    private static void validateLimit(int limit) {
        if (limit < 1 || limit > 100) {
            throw new ResponseStatusException(
                    HttpStatus.BAD_REQUEST, "limit must be between 1 and 100");
        }
    }

    private static String required(Map<String, Object> body, String key) {
        String value = text(body.get(key)).trim();
        if (value.isEmpty()) {
            throw new ResponseStatusException(
                    HttpStatus.BAD_REQUEST, key + " is required");
        }
        return value;
    }

    private static String text(Object value) {
        return value == null ? "" : value.toString();
    }

    private static String value(
            Map<String, Object> body, String key, String fallback) {
        return body.get(key) == null ? fallback : text(body.get(key));
    }

    private static String nullableText(Object value) {
        String text = text(value).trim();
        return text.isEmpty() ? null : text;
    }

    private static String safeImageUrl(Object value) {
        String url = text(value).trim();
        if (url.isEmpty()) return null;
        if (url.length() > 2048
                || !(url.startsWith("https://") || url.startsWith("http://"))) {
            throw new ResponseStatusException(
                    HttpStatus.BAD_REQUEST, "image_url must be a valid HTTP(S) URL");
        }
        return url;
    }

    private static String listingCountry(
            String type, Object requestedCountry, LocationMetadata location) {
        if (!"hotel".equals(type)) return location.country();
        String country = text(requestedCountry).trim();
        if (country.isEmpty() || country.length() > 255) {
            throw new ResponseStatusException(
                    HttpStatus.BAD_REQUEST,
                    "Hotel country is required and must not exceed 255 characters");
        }
        return country;
    }

    private static String listingImage(String type, Object imageValue) {
        String imageUrl = safeImageUrl(imageValue);
        if ("hotel".equals(type) && (imageUrl == null || imageUrl.isBlank())) {
            throw new ResponseStatusException(
                    HttpStatus.BAD_REQUEST, "Hotel listings require a photo URL");
        }
        return imageUrl;
    }

    private static BigDecimal decimal(Object value) {
        try {
            BigDecimal amount = new BigDecimal(text(value).isBlank() ? "0" : text(value));
            if (amount.signum() < 0 || amount.precision() > 10 || amount.scale() > 2) {
                throw new NumberFormatException();
            }
            return amount;
        } catch (NumberFormatException exception) {
            throw new ResponseStatusException(
                    HttpStatus.BAD_REQUEST, "price must be a non-negative amount with at most two decimals");
        }
    }

    private static BigDecimal nullableDecimal(Object value) {
        return value == null ? null : decimal(value);
    }

    private static double doubleValue(Object value) {
        if (value instanceof Number number) return number.doubleValue();
        try {
            return Double.parseDouble(text(value));
        } catch (NumberFormatException exception) {
            return 0;
        }
    }

    private static boolean bool(Object value, boolean fallback) {
        if (value instanceof Boolean result) return result;
        if (value instanceof Number number) return number.intValue() != 0;
        if (value instanceof String text) {
            if ("true".equalsIgnoreCase(text) || "1".equals(text)) return true;
            if ("false".equalsIgnoreCase(text) || "0".equals(text)) return false;
        }
        return fallback;
    }

    private static String serializeAttributes(Object raw) {
        try {
            return JSON.writeValueAsString(attributes(raw));
        } catch (com.fasterxml.jackson.core.JsonProcessingException exception) {
            throw new IllegalStateException("Could not serialize listing attributes", exception);
        }
    }

    private static Map<String, Object> attributes(Object raw) {
        if (raw instanceof Map<?, ?> map) {
            Map<String, Object> result = new LinkedHashMap<>();
            map.forEach((key, value) -> result.put(key.toString(), value));
            return result;
        }
        if (raw == null) return new LinkedHashMap<>();
        try {
            return JSON.readValue(raw.toString(), new TypeReference<>() {});
        } catch (com.fasterxml.jackson.core.JsonProcessingException exception) {
            throw new IllegalStateException("Could not parse stored listing attributes", exception);
        }
    }

    private static List<String> stringArray(Object raw) {
        try {
            List<?> values;
            if (raw instanceof List<?> list) {
                values = list;
            } else if (raw instanceof String json && !json.isBlank()) {
                values = JSON.readValue(json, new TypeReference<List<Object>>() {});
            } else {
                return List.of();
            }
            return values.stream()
                    .filter(String.class::isInstance)
                    .map(String.class::cast)
                    .toList();
        } catch (com.fasterxml.jackson.core.JsonProcessingException exception) {
            throw new IllegalStateException("Could not parse hotel amenities", exception);
        }
    }

    private static String serializeJson(Object value) {
        try {
            return JSON.writeValueAsString(value);
        } catch (com.fasterxml.jackson.core.JsonProcessingException exception) {
            throw new IllegalStateException("Could not serialize hotel field", exception);
        }
    }

    private long insert(String sql, Object... args) {
        KeyHolder keyHolder = new GeneratedKeyHolder();
        jdbc.update(connection -> {
            PreparedStatement statement =
                    connection.prepareStatement(sql, Statement.RETURN_GENERATED_KEYS);
            for (int i = 0; i < args.length; i++) {
                statement.setObject(i + 1, args[i]);
            }
            return statement;
        }, keyHolder);
        Number key = keyHolder.getKey();
        if (key == null) throw new IllegalStateException("Listing insert did not return an ID");
        return key.longValue();
    }

    record PartnerIdentity(long id, String name, String serviceType, String slug) {}

    private record LocationMetadata(
            String code, String country, String region, String city) {
        private LocationMetadata(String code, String country, String region) {
            this(code, country, region, "");
        }
    }
}
