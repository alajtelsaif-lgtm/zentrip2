package com.zentrip.api;

import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;
import jakarta.servlet.http.HttpServletRequest;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
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
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.server.ResponseStatusException;

import java.math.BigDecimal;
import java.util.List;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.UUID;
import java.util.Map;
import java.util.Locale;
import java.util.Set;
import java.util.LinkedHashSet;

@RestController
@RequestMapping("/api/admin")
public class AdminController {
    private static final String OFFER_FLIGHT_MIGRATION_REQUIRED =
            "Apply migration 20261107_offer_flight_link.sql in Supabase before linking flights to offers";

    private static final ObjectMapper JSON = new ObjectMapper();
    private static final Set<String> PARTNER_SERVICE_TYPES =
            Set.of("airline", "hotel", "car", "transfer", "travel");
    private final JdbcTemplate jdbc;

    public AdminController(JdbcTemplate jdbc) {
        this.jdbc = jdbc;
    }

    @GetMapping("/dashboard")
    public Map<String, Object> dashboard(HttpServletRequest request) {
        requireAdminId(request);
        Map<String, Object> summary = jdbc.queryForMap("""
                SELECT
                    (SELECT COUNT(*) FROM users WHERE role = 'customer') AS customer_count,
                    (SELECT COUNT(*) FROM users
                        WHERE role = 'customer' AND created_at >= NOW() - INTERVAL '30 day')
                        AS new_customers_30d,
                    (SELECT COUNT(*) FROM users) AS total_user_count,
                    (SELECT COUNT(*) FROM partners
                        WHERE LOWER(status) = 'active') AS partner_count,
                    (SELECT COUNT(*) FROM partner_listings pl
                        JOIN partners p ON p.id = pl.partner_id
                        WHERE pl.active = TRUE AND LOWER(p.status) = 'active')
                        AS active_partner_listing_count,
                    (SELECT COUNT(*) FROM bookings WHERE LOWER(status) <> 'cancelled')
                      + (SELECT COUNT(*) FROM trips WHERE LOWER(status) <> 'cancelled')
                      + (SELECT COUNT(*) FROM transfers WHERE LOWER(status) <> 'cancelled')
                        AS reservation_count,
                    (SELECT COUNT(*) FROM trips WHERE LOWER(status) <> 'cancelled')
                        AS flight_count,
                    (SELECT COUNT(*) FROM bookings WHERE LOWER(status) <> 'cancelled')
                        AS service_booking_count,
                    (SELECT COUNT(*) FROM transfers WHERE LOWER(status) <> 'cancelled')
                        AS transfer_count,
                    COALESCE((SELECT SUM(total_amount) FROM bookings
                        WHERE LOWER(status) <> 'cancelled'), 0)
                      + COALESCE((SELECT SUM(price) FROM trips
                        WHERE LOWER(status) <> 'cancelled'), 0)
                      + COALESCE((SELECT SUM(price) FROM transfers
                        WHERE LOWER(status) <> 'cancelled'), 0)
                        AS booked_value
                """);
        return Map.of(
                "summary", summary,
                "recent_reservations", recentReservations(8));
    }

    @GetMapping("/attractions/popularity")
    public Map<String, Object> attractionPopularity(HttpServletRequest request) {
        requireAdminId(request);
        List<Map<String, Object>> places = jdbc.queryForList("""
                SELECT title,
                       TRIM(SPLIT_PART(location, ',', 1)) AS city,
                       COALESCE(NULLIF(TRIM(SPLIT_PART(location, ',', 2)), ''), '')
                           AS country,
                       COALESCE(visit_counts.visit_count, 0) AS visit_count
                FROM tourist_monuments monuments
                LEFT JOIN attraction_visit_counts visit_counts
                    ON visit_counts.attraction_id = monuments.id
                WHERE monuments.is_active = TRUE
                ORDER BY COALESCE(visit_counts.visit_count, 0) DESC,
                         LOWER(monuments.title)
                """);
        List<Map<String, Object>> countries = jdbc.queryForList("""
                WITH country_visits AS (
                    SELECT COALESCE(
                               NULLIF(TRIM(SPLIT_PART(monuments.location, ',', 2)), ''),
                               'Unspecified country') AS country,
                           LOWER(COALESCE(
                               NULLIF(TRIM(SPLIT_PART(monuments.location, ',', 2)), ''),
                               'Unspecified country')) AS country_key,
                           COALESCE(visit_counts.visit_count, 0) AS visit_count
                    FROM tourist_monuments monuments
                    LEFT JOIN attraction_visit_counts visit_counts
                        ON visit_counts.attraction_id = monuments.id
                    WHERE monuments.is_active = TRUE
                ),
                country_totals AS (
                    SELECT MIN(country) AS country, SUM(visit_count) AS visit_count
                    FROM country_visits
                    GROUP BY country_key
                )
                SELECT country, visit_count
                FROM country_totals
                ORDER BY visit_count DESC, LOWER(country)
                """);
        return Map.of("places", places, "countries", countries);
    }

    @GetMapping("/partners")
    public Map<String, Object> partners(HttpServletRequest request) {
        requireAdminId(request);
        List<Map<String, Object>> rows = jdbc.queryForList("""
                SELECT p.id, p.name, p.slug, p.service_type, p.status, p.created_at,
                       COALESCE(accounts.account_count, 0) AS account_count,
                       COALESCE(accounts.contact_emails, '') AS contact_emails,
                       COALESCE(listings.listing_count, 0) AS listing_count,
                       NULL::timestamp AS attraction_reviewed_at
                FROM partners p
                LEFT JOIN (
                    SELECT partner_id, COUNT(*) AS account_count,
                           STRING_AGG(email, ', ' ORDER BY email) AS contact_emails
                    FROM users
                    WHERE partner_id IS NOT NULL
                    GROUP BY partner_id
                ) accounts ON accounts.partner_id = p.id
                LEFT JOIN (
                    SELECT partner_id, COUNT(*) AS listing_count
                    FROM partner_listings
                    GROUP BY partner_id
                ) listings ON listings.partner_id = p.id
                WHERE TRIM(LOWER(COALESCE(p.service_type, ''))) <> 'attraction'
                ORDER BY (LOWER(p.status) = 'active') DESC, LOWER(p.name), p.id
                """);
        return Map.of("partners", rows);
    }

    @GetMapping("/partners/legacy-attractions")
    public Map<String, Object> legacyAttractionPartners(HttpServletRequest request) {
        requireAdminId(request);
        boolean hasReviewStorage = legacyAttractionReviewStorageExists();
        String reviewColumns = hasReviewStorage
                ? "reviews.approved_at, reviewer.name AS reviewed_by_name"
                : "NULL AS approved_at, NULL AS reviewed_by_name";
        String reviewJoins = hasReviewStorage
                ? """
                  LEFT JOIN legacy_attraction_partner_reviews reviews
                      ON reviews.partner_id = p.id
                  LEFT JOIN users reviewer ON reviewer.id = reviews.reviewed_by
                  """
                : "";
        String sql = """
                SELECT p.id AS partner_id, p.name AS partner_name, p.slug,
                       p.status, p.created_at, %s,
                       u.email AS account_email,
                       l.id AS listing_id, l.type AS listing_type, l.title,
                       l.city, l.country, l.description, l.image_url, l.price,
                       l.active AS listing_active, l.attributes::text AS listing_attributes,
                       l.google_rating, l.google_review_count, l.location_name,
                       l.google_maps_url, l.place_id
                FROM partners p
                LEFT JOIN users u ON u.partner_id = p.id
                %s
                LEFT JOIN partner_listings l ON l.partner_id = p.id
                WHERE LOWER(p.service_type) = 'attraction'
                ORDER BY p.id, l.id, u.email
                """.formatted(reviewColumns, reviewJoins);
        List<Map<String, Object>> rows = jdbc.queryForList(sql);

        Map<Long, Map<String, Object>> partnersById = new LinkedHashMap<>();
        for (Map<String, Object> row : rows) {
            long partnerId = ((Number) row.get("partner_id")).longValue();
            Map<String, Object> partner = partnersById.computeIfAbsent(partnerId, id -> {
                Map<String, Object> value = new LinkedHashMap<>();
                value.put("id", id);
                value.put("name", row.get("partner_name"));
                value.put("slug", row.get("slug"));
                value.put("status", row.get("status"));
                value.put("created_at", row.get("created_at"));
                value.put("reviewed_at", row.get("approved_at"));
                value.put("reviewed_by_name", row.get("reviewed_by_name"));
                value.put("accounts", new LinkedHashSet<String>());
                value.put("listings", new ArrayList<Map<String, Object>>());
                value.put("_listing_ids", new LinkedHashSet<Long>());
                return value;
            });
            if (row.get("account_email") != null) {
                @SuppressWarnings("unchecked")
                Set<String> accounts = (Set<String>) partner.get("accounts");
                accounts.add(text(row.get("account_email")));
            }
            if (row.get("listing_id") != null) {
                @SuppressWarnings("unchecked")
                Set<Long> addedListingIds = (Set<Long>) partner.get("_listing_ids");
                long listingId = ((Number) row.get("listing_id")).longValue();
                if (!addedListingIds.add(listingId)) continue;
                Map<String, Object> listing = new LinkedHashMap<>();
                listing.put("id", listingId);
                listing.put("type", row.get("listing_type"));
                listing.put("title", row.get("title"));
                listing.put("city", row.get("city"));
                listing.put("country", row.get("country"));
                listing.put("description", row.get("description"));
                listing.put("image_url", row.get("image_url"));
                listing.put("price", row.get("price"));
                listing.put("active", row.get("listing_active"));
                listing.put("attributes", parseObject(row.get("listing_attributes")));
                listing.put("google_rating", row.get("google_rating"));
                listing.put("google_review_count", row.get("google_review_count"));
                listing.put("location_name", row.get("location_name"));
                listing.put("google_maps_url", row.get("google_maps_url"));
                listing.put("place_id", row.get("place_id"));
                @SuppressWarnings("unchecked")
                List<Map<String, Object>> listings =
                        (List<Map<String, Object>>) partner.get("listings");
                listings.add(listing);
            }
        }
        for (Map<String, Object> partner : partnersById.values()) {
            @SuppressWarnings("unchecked")
            Set<String> accounts = (Set<String>) partner.get("accounts");
            partner.put("accounts", List.copyOf(accounts));
            partner.remove("_listing_ids");
        }
        return Map.of("partners", List.copyOf(partnersById.values()));
    }

    @PostMapping("/partners/{id}/attraction-review")
    @Transactional
    public Map<String, Object> reviewAndRetireAttractionPartner(
            @PathVariable long id,
            @RequestBody Map<String, Object> body,
            HttpServletRequest request) {
        long adminId = requireAdminId(request);
        if (!legacyAttractionReviewStorageExists()) {
            throw new ResponseStatusException(
                    HttpStatus.CONFLICT,
                    "Legacy attraction review storage is unavailable; no changes were made");
        }
        if (!booleanValue(body.get("approved"), false)) {
            throw new ResponseStatusException(
                    HttpStatus.BAD_REQUEST, "Admin approval is required before retiring access");
        }

        List<Map<String, Object>> partnerRows = jdbc.queryForList("""
                SELECT id, service_type, status
                FROM partners
                WHERE id = ?
                FOR UPDATE
                """, id);
        if (partnerRows.isEmpty()) {
            throw new ResponseStatusException(HttpStatus.NOT_FOUND, "Attraction partner not found");
        }
        Map<String, Object> partner = partnerRows.getFirst();
        if (!"attraction".equalsIgnoreCase(text(partner.get("service_type")))) {
            throw new ResponseStatusException(
                    HttpStatus.CONFLICT, "This review is only for attraction partners");
        }
        String status = text(partner.get("status"));
        if (!"active".equalsIgnoreCase(status)
                && !"inactive".equalsIgnoreCase(status)) {
            throw new ResponseStatusException(
                    HttpStatus.CONFLICT, "Attraction partner must be active or inactive");
        }
        Integer priorReview = jdbc.queryForObject(
                "SELECT COUNT(*) FROM legacy_attraction_partner_reviews WHERE partner_id = ?",
                Integer.class,
                id);
        if (priorReview != null && priorReview > 0) {
            throw new ResponseStatusException(
                    HttpStatus.CONFLICT, "This attraction partner has already been reviewed");
        }

        List<Map<String, Object>> sourceListings = jdbc.queryForList("""
                SELECT id, type, title, city, country, description, image_url, price,
                       attributes::text AS attributes, google_rating, google_review_count
                FROM partner_listings
                WHERE partner_id = ? AND LOWER(type) = 'attraction'
                ORDER BY id
                FOR UPDATE
                """, id);
        List<Map<String, Object>> submitted = reviewDecisions(body.get("listings"));
        Map<Long, Map<String, Object>> decisionsByListing = new LinkedHashMap<>();
        for (Map<String, Object> decision : submitted) {
            long listingId = positiveLong(decision.get("listing_id"), "listing_id");
            if (decisionsByListing.putIfAbsent(listingId, decision) != null) {
                throw new ResponseStatusException(
                        HttpStatus.BAD_REQUEST, "Each attraction listing must be reviewed once");
            }
        }
        Set<Long> sourceIds = new LinkedHashSet<>();
        for (Map<String, Object> listing : sourceListings) {
            sourceIds.add(((Number) listing.get("id")).longValue());
        }
        if (!sourceIds.equals(decisionsByListing.keySet())) {
            throw new ResponseStatusException(
                    HttpStatus.BAD_REQUEST,
                    "Review every attraction listing before approving this account");
        }

        List<Map<String, Object>> auditDecisions = new ArrayList<>();
        int mappedCount = 0;
        int skippedCount = 0;
        for (Map<String, Object> source : sourceListings) {
            long listingId = ((Number) source.get("id")).longValue();
            Map<String, Object> decision = decisionsByListing.get(listingId);
            String action = requiredText(decision, "action", 30)
                    .toLowerCase(Locale.ROOT);
            Map<String, Object> audit = new LinkedHashMap<>();
            audit.put("listing_id", listingId);
            audit.put("action", action);
            switch (action) {
                case "existing" -> {
                    String monumentId = requiredText(decision, "monument_id", 64);
                    requireCatalogItem(
                            "SELECT COUNT(*) FROM tourist_monuments "
                                    + "WHERE id = ? AND is_active = TRUE",
                            monumentId,
                            "Selected active place was not found");
                    audit.put("monument_id", monumentId);
                    mappedCount++;
                }
                case "create" -> {
                    String monumentId = createMonumentFromLegacyListing(source);
                    audit.put("monument_id", monumentId);
                    mappedCount++;
                }
                case "omit" -> skippedCount++;
                default -> throw new ResponseStatusException(
                        HttpStatus.BAD_REQUEST,
                        "Choose an existing place, create a place, or leave the listing unmapped");
            }
            auditDecisions.add(audit);
        }

        jdbc.update("""
                INSERT INTO legacy_attraction_partner_reviews
                    (partner_id, reviewed_by, decisions, mapped_listing_count, omitted_listing_count)
                VALUES (?, ?, CAST(? AS JSONB), ?, ?)
                """, id, adminId, jsonList(auditDecisions), mappedCount, skippedCount);
        jdbc.update("""
                UPDATE partners
                SET status = 'inactive', updated_at = NOW()
                WHERE id = ?
                """, id);
        jdbc.update("""
                UPDATE users
                SET role = 'customer', updated_at = NOW()
                WHERE partner_id = ? AND role = 'partner'
                """, id);
        return Map.of(
                "message", "Attraction partner reviewed and access retired",
                "mapped_listing_count", mappedCount,
                "omitted_listing_count", skippedCount);
    }

    @PostMapping("/partners")
    @ResponseStatus(HttpStatus.CREATED)
    @Transactional
    public Map<String, Object> addPartner(
            @RequestBody Map<String, Object> body,
            HttpServletRequest request) {
        requireAdminId(request);
        String name = requiredText(body, "name", 255);
        String email = requiredText(body, "email", 255).toLowerCase(Locale.ROOT);
        if (!email.matches("^[^\\s@]+@[^\\s@]+\\.[^\\s@]+$")) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "Enter a valid email address");
        }
        String serviceType = requiredText(body, "service_type", 30)
                .toLowerCase(Locale.ROOT);
        if (!PARTNER_SERVICE_TYPES.contains(serviceType)) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "Select a valid partner service");
        }

        List<Long> userIds = jdbc.query("""
                SELECT id
                FROM users
                WHERE LOWER(email) = ? AND role = 'customer' AND partner_id IS NULL
                FOR UPDATE
                """, (resultSet, rowNum) -> resultSet.getLong(1), email);
        if (userIds.isEmpty()) {
            throw new ResponseStatusException(
                    HttpStatus.NOT_FOUND,
                    "Register this email in Zentrip before adding it as a partner.");
        }

        String slugBase = name.toLowerCase(Locale.ROOT)
                .replaceAll("[^a-z0-9]+", "-")
                .replaceAll("(^-+|-+$)", "");
        if (slugBase.isEmpty()) slugBase = "partner";
        if (slugBase.length() > 72) slugBase = slugBase.substring(0, 72);
        String slug = slugBase + "-" + UUID.randomUUID().toString().substring(0, 8);
        Long partnerId = jdbc.queryForObject("""
                INSERT INTO partners (slug, name, service_type, status)
                VALUES (?, ?, ?, 'active')
                RETURNING id
                """, Long.class, slug, name, serviceType);
        if (partnerId == null) {
            throw new IllegalStateException("The partner record could not be created");
        }

        int updated = jdbc.update("""
                UPDATE users
                SET role = 'partner', partner_id = ?, updated_at = NOW()
                WHERE id = ? AND role = 'customer' AND partner_id IS NULL
                """, partnerId, userIds.getFirst());
        if (updated != 1) {
            throw new ResponseStatusException(
                    HttpStatus.CONFLICT, "The user account changed. Refresh and try again.");
        }
        return Map.of("partner", Map.of(
                "id", partnerId,
                "name", name,
                "slug", slug,
                "service_type", serviceType,
                "status", "active",
                "account_count", 1,
                "contact_emails", email,
                "listing_count", 0));
    }

    @DeleteMapping("/partners/{id}")
    @Transactional
    public Map<String, String> disablePartner(
            @PathVariable long id,
            HttpServletRequest request) {
        requireAdminId(request);
        int updated = jdbc.update("""
                UPDATE partners
                SET status = 'inactive', updated_at = NOW()
                WHERE id = ? AND LOWER(status) = 'active'
                    AND LOWER(service_type) <> 'attraction'
                """, id);
        if (updated == 0) {
            if (isAttractionPartner(id)) {
                throw new ResponseStatusException(
                        HttpStatus.CONFLICT,
                        "Review and approve this attraction partner before retiring access");
            }
            throw new ResponseStatusException(HttpStatus.NOT_FOUND, "Active partner not found");
        }
        jdbc.update("""
                UPDATE users
                SET role = 'customer', updated_at = NOW()
                WHERE partner_id = ? AND role = 'partner'
                """, id);
        return Map.of("message", "Partner access disabled; partner records were preserved.");
    }

    @PostMapping("/partners/{id}/activate")
    @Transactional
    public Map<String, String> activatePartner(
            @PathVariable long id,
            HttpServletRequest request) {
        requireAdminId(request);
        int updated = jdbc.update("""
                UPDATE partners
                SET status = 'active', updated_at = NOW()
                WHERE id = ? AND LOWER(status) <> 'active'
                    AND LOWER(service_type) <> 'attraction'
                """, id);
        if (updated == 0) {
            if (isAttractionPartner(id)) {
                throw new ResponseStatusException(
                        HttpStatus.CONFLICT,
                        "Attraction partner access cannot be restored through partner management");
            }
            throw new ResponseStatusException(HttpStatus.NOT_FOUND, "Inactive partner not found");
        }
        jdbc.update("""
                UPDATE users
                SET role = 'partner', updated_at = NOW()
                WHERE partner_id = ? AND role = 'customer'
                """, id);
        return Map.of("message", "Partner access restored.");
    }

    @GetMapping("/reservations")
    public Map<String, Object> reservations(
            @RequestParam(defaultValue = "50") int limit,
            HttpServletRequest request) {
        requireAdminId(request);
        validateLimit(limit);
        return Map.of("reservations", recentReservations(limit));
    }

    @GetMapping("/customers")
    public Map<String, Object> customers(
            @RequestParam(defaultValue = "50") int limit,
            HttpServletRequest request) {
        requireAdminId(request);
        validateLimit(limit);
        List<Map<String, Object>> rows = jdbc.queryForList("""
                SELECT u.id, u.name, u.email, u.phone, u.created_at,
                    (SELECT COUNT(*) FROM bookings b WHERE b.user_id = u.id)
                      + (SELECT COUNT(*) FROM trips t WHERE t.user_id = u.id)
                      + (SELECT COUNT(*) FROM transfers x WHERE x.user_id = u.id)
                      AS reservation_count
                FROM users u
                WHERE u.role = 'customer'
                ORDER BY u.created_at DESC
                LIMIT ?
                """, limit);
        return Map.of("customers", rows);
    }

    @GetMapping("/monuments")
    public Map<String, Object> monuments(HttpServletRequest request) {
        requireAdminId(request);
        List<Map<String, Object>> rows = jdbc.queryForList("""
                SELECT id, title, location, category_tag, category, rating,
                       review_count, description, working_hours,
                       best_time_to_visit, entry_fee, image_url, tags, is_active
                FROM tourist_monuments
                ORDER BY sort_order ASC, title ASC
                """);
        return Map.of("monuments", rows.stream().map(AdminController::monumentPayload).toList());
    }

    @PostMapping("/monuments")
    @Transactional
    public Map<String, Object> createMonument(
            @RequestBody Map<String, Object> body,
            HttpServletRequest request) {
        requireAdminId(request);
        Map<String, Object> monument = validateMonument(body);
        String id = UUID.randomUUID().toString();
        jdbc.update("""
                INSERT INTO tourist_monuments (
                    id, title, location, category_tag, category, rating,
                    review_count, description, working_hours, best_time_to_visit,
                    entry_fee, image_url, tags, is_active
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                id,
                monument.get("title"),
                monument.get("location"),
                monument.get("category_tag"),
                monument.get("category"),
                monument.get("rating"),
                monument.get("review_count"),
                monument.get("description"),
                monument.get("working_hours"),
                monument.get("best_time_to_visit"),
                monument.get("entry_fee"),
                monument.get("image_url"),
                jsonList(monument.get("tags")),
                monument.get("is_active"));
        monument.put("id", id);
        return Map.of("monument", monument);
    }

    @PutMapping("/monuments/{id}")
    @Transactional
    public Map<String, Object> updateMonument(
            @PathVariable String id,
            @RequestBody Map<String, Object> body,
            HttpServletRequest request) {
        requireAdminId(request);
        Map<String, Object> monument = validateMonument(body);
        requireCatalogItem(
                "SELECT COUNT(*) FROM tourist_monuments WHERE id = ?", id, "Monument not found");
        int updated = jdbc.update("""
                UPDATE tourist_monuments
                SET title = ?, location = ?, category_tag = ?, category = ?,
                    rating = ?, review_count = ?, description = ?,
                    working_hours = ?, best_time_to_visit = ?, entry_fee = ?,
                    image_url = ?, tags = ?, is_active = ?
                WHERE id = ?
                """,
                monument.get("title"),
                monument.get("location"),
                monument.get("category_tag"),
                monument.get("category"),
                monument.get("rating"),
                monument.get("review_count"),
                monument.get("description"),
                monument.get("working_hours"),
                monument.get("best_time_to_visit"),
                monument.get("entry_fee"),
                monument.get("image_url"),
                jsonList(monument.get("tags")),
                monument.get("is_active"),
                id);
        if (updated == 0
                && !catalogItemExists(
                        "SELECT COUNT(*) FROM tourist_monuments WHERE id = ?", id)) {
            throw new ResponseStatusException(HttpStatus.NOT_FOUND, "Monument not found");
        }
        monument.put("id", id);
        return Map.of("monument", monument);
    }

    @DeleteMapping("/monuments/{id}")
    @Transactional
    public Map<String, String> deleteMonument(
            @PathVariable String id,
            HttpServletRequest request) {
        requireAdminId(request);
        if (jdbc.update("DELETE FROM tourist_monuments WHERE id = ?", id) == 0) {
            throw new ResponseStatusException(HttpStatus.NOT_FOUND, "Monument not found");
        }
        return Map.of("message", "Monument deleted");
    }

    @GetMapping("/offers")
    public Map<String, Object> offers(HttpServletRequest request) {
        requireAdminId(request);
        boolean flightLinkSchemaReady = hasOfferFlightLinkColumn();
        String linkedFlightColumn = flightLinkSchemaReady
                ? "o.flight_listing_id" : "NULL::BIGINT";
        String flightJoin = flightLinkSchemaReady
                ? "LEFT JOIN partner_listings fl ON fl.id = o.flight_listing_id"
                : "LEFT JOIN partner_listings fl ON FALSE";
        List<Map<String, Object>> rows = jdbc.queryForList("""
                SELECT o.id, o.title, o.location, o.country, o.destination_code,
                       o.description, o.image_url, o.price_per_person,
                       o.flight_price_per_person, o.hotel_price_per_night,
                       o.duration_nights, o.rating, o.review_count, o.highlights,
                       o.is_featured, o.category, o.is_active,
                       %s AS flight_listing_id, COALESCE(m.badge, '') AS badge,
                       fl.id AS linked_flight_id, fl.title AS flight_title,
                       fl.city AS flight_city, fl.country AS flight_country,
                       fl.price AS linked_flight_price, fl.active AS flight_active,
                       fl.attributes AS flight_attributes, p.name AS flight_airline
                FROM offers o
                LEFT JOIN offer_catalog_metadata m ON m.offer_id = o.id
                %s
                LEFT JOIN partners p ON p.id = fl.partner_id
                WHERE o.is_active = TRUE
                ORDER BY o.is_featured DESC, o.sort_order ASC, o.title ASC
                """.formatted(linkedFlightColumn, flightJoin));
        return Map.of(
                "offers", rows.stream().map(AdminController::offerPayload).toList(),
                "flight_link_schema_ready", flightLinkSchemaReady);
    }

    @GetMapping("/flight-listings")
    public Map<String, Object> offerFlightListings(HttpServletRequest request) {
        requireAdminId(request);
        List<Map<String, Object>> rows = jdbc.queryForList("""
                SELECT l.id AS linked_flight_id, l.title AS flight_title,
                       l.city AS flight_city, l.country AS flight_country,
                       l.price AS linked_flight_price, l.active AS flight_active,
                       l.attributes AS flight_attributes, p.name AS flight_airline
                FROM partner_listings l
                JOIN partners p ON p.id = l.partner_id AND p.status = 'active'
                WHERE l.type = 'flight' AND l.active = TRUE
                ORDER BY p.name, l.title
                """);
        return Map.of("flights", rows.stream()
                .map(AdminController::flightListingPayload)
                .toList());
    }

    @PostMapping("/offers")
    @Transactional
    public ResponseEntity<Map<String, Object>> createOffer(
            @RequestBody Map<String, Object> body,
            HttpServletRequest request) {
        requireAdminId(request);
        Map<String, Object> offer = validateOffer(body);
        if (!hasOfferFlightLinkColumn()) {
            return ResponseEntity.status(HttpStatus.CONFLICT)
                    .body(Map.of("message", OFFER_FLIGHT_MIGRATION_REQUIRED));
        }
        resolveOfferFlightPrice(offer);
        String id = UUID.randomUUID().toString();
        jdbc.update("""
                INSERT INTO offers (
                    id, title, location, country, destination_code, description,
                    image_url, price_per_person, flight_price_per_person,
                    hotel_price_per_night, duration_nights, rating, review_count,
                    highlights, flight_listing_id, is_featured, category, is_active
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                id,
                offer.get("title"),
                offer.get("location"),
                offer.get("country"),
                offer.get("destination_code"),
                offer.get("description"),
                offer.get("image_url"),
                offer.get("price_per_person"),
                offer.get("flight_price_per_person"),
                offer.get("hotel_price_per_night"),
                offer.get("duration_nights"),
                offer.get("rating"),
                offer.get("review_count"),
                jsonList(offer.get("highlights")),
                offer.get("flight_listing_id"),
                offer.get("is_featured"),
                offer.get("category"),
                offer.get("is_active"));
        jdbc.update("""
                INSERT INTO offer_catalog_metadata (offer_id, badge)
                VALUES (?, ?)
                """, id, offer.get("badge"));
        offer.put("id", id);
        return ResponseEntity.ok(Map.of("offer", offer));
    }

    @PutMapping("/offers/{id}")
    @Transactional
    public ResponseEntity<Map<String, Object>> updateOffer(
            @PathVariable String id,
            @RequestBody Map<String, Object> body,
            HttpServletRequest request) {
        requireAdminId(request);
        Map<String, Object> offer = validateOffer(body);
        if (!hasOfferFlightLinkColumn()) {
            return ResponseEntity.status(HttpStatus.CONFLICT)
                    .body(Map.of("message", OFFER_FLIGHT_MIGRATION_REQUIRED));
        }
        resolveOfferFlightPrice(offer);
        requireCatalogItem(
                "SELECT COUNT(*) FROM offers WHERE id = ? AND is_active = TRUE",
                id,
                "Offer not found");
        int updated = jdbc.update("""
                UPDATE offers
                SET title = ?, location = ?, country = ?, destination_code = ?,
                    description = ?, image_url = ?, price_per_person = ?,
                    flight_price_per_person = ?, hotel_price_per_night = ?,
                    duration_nights = ?, rating = ?, review_count = ?,
                    highlights = ?, flight_listing_id = ?, is_featured = ?,
                    category = ?, is_active = ?
                WHERE id = ?
                """,
                offer.get("title"),
                offer.get("location"),
                offer.get("country"),
                offer.get("destination_code"),
                offer.get("description"),
                offer.get("image_url"),
                offer.get("price_per_person"),
                offer.get("flight_price_per_person"),
                offer.get("hotel_price_per_night"),
                offer.get("duration_nights"),
                offer.get("rating"),
                offer.get("review_count"),
                jsonList(offer.get("highlights")),
                offer.get("flight_listing_id"),
                offer.get("is_featured"),
                offer.get("category"),
                offer.get("is_active"),
                id);
        if (updated == 0
                && !catalogItemExists(
                        "SELECT COUNT(*) FROM offers WHERE id = ? AND is_active = TRUE", id)) {
            throw new ResponseStatusException(HttpStatus.NOT_FOUND, "Offer not found");
        }
        jdbc.update("""
                INSERT INTO offer_catalog_metadata (offer_id, badge)
                VALUES (?, ?)
                ON CONFLICT (offer_id) DO UPDATE SET badge = EXCLUDED.badge
                """, id, offer.get("badge"));
        offer.put("id", id);
        return ResponseEntity.ok(Map.of("offer", offer));
    }

    @DeleteMapping("/offers/{id}")
    @Transactional
    public Map<String, String> deleteOffer(
            @PathVariable String id,
            HttpServletRequest request) {
        requireAdminId(request);
        if (jdbc.update(
                "UPDATE offers SET is_active = FALSE WHERE id = ? AND is_active = TRUE",
                id) == 0) {
            throw new ResponseStatusException(HttpStatus.NOT_FOUND, "Offer not found");
        }
        return Map.of("message", "Offer deleted");
    }

    private static Map<String, Object> validateMonument(Map<String, Object> body) {
        Map<String, Object> monument = new LinkedHashMap<>();
        monument.put("title", requiredText(body, "title", 255));
        monument.put("location", requiredText(body, "location", 255));
        monument.put("category_tag", optionalText(body, "category_tag", 100));
        monument.put("category", optionalText(body, "category", 40, "landmark"));
        monument.put("rating", rating(body.get("rating")));
        monument.put("review_count", nonNegativeInt(body.get("review_count"), "review_count"));
        monument.put("description", requiredText(body, "description", 10000));
        monument.put("working_hours", optionalText(body, "working_hours", 255));
        monument.put("best_time_to_visit", optionalText(body, "best_time_to_visit", 255));
        monument.put("entry_fee", optionalMoney(body.get("entry_fee"), "entry_fee"));
        monument.put("image_url", optionalText(body, "image_url", 2048));
        monument.put("tags", stringList(body.get("tags"), "tags"));
        monument.put("is_active", booleanValue(body.get("is_active"), true));
        return monument;
    }

    private static Map<String, Object> validateOffer(Map<String, Object> body) {
        Map<String, Object> offer = new LinkedHashMap<>();
        offer.put("title", requiredText(body, "title", 255));
        offer.put("location", requiredText(body, "location", 255));
        offer.put("country", requiredText(body, "country", 255));
        offer.put("destination_code", optionalText(body, "destination_code", 10));
        offer.put("description", requiredText(body, "description", 10000));
        offer.put("image_url", optionalText(body, "image_url", 2048));
        offer.put("price_per_person", nonNegativeMoney(body.get("price_per_person"), "price_per_person"));
        offer.put("flight_price_per_person", nonNegativeMoney(
                body.get("flight_price_per_person"), "flight_price_per_person"));
        offer.put("flight_listing_id", positiveLong(
                body.get("flight_listing_id"), "flight_listing_id"));
        offer.put("hotel_price_per_night", nonNegativeMoney(
                body.get("hotel_price_per_night"), "hotel_price_per_night"));
        int nights = nonNegativeInt(body.get("duration_nights"), "duration_nights");
        if (nights < 1 || nights > 365) {
            throw new ResponseStatusException(
                    HttpStatus.BAD_REQUEST, "duration_nights must be between 1 and 365");
        }
        offer.put("duration_nights", nights);
        offer.put("rating", rating(body.get("rating")));
        offer.put("review_count", nonNegativeInt(body.get("review_count"), "review_count"));
        offer.put("highlights", stringList(body.get("highlights"), "highlights"));
        offer.put("badge", optionalText(body, "badge", 100));
        offer.put("is_featured", booleanValue(
                body.getOrDefault("is_featured", body.get("badge")), false));
        offer.put("category", optionalText(body, "category", 40, "city"));
        offer.put("is_active", booleanValue(body.get("is_active"), true));
        return offer;
    }

    private void resolveOfferFlightPrice(Map<String, Object> offer) {
        long flightListingId = ((Number) offer.get("flight_listing_id")).longValue();
        List<Map<String, Object>> rows = jdbc.queryForList("""
                SELECT l.price
                FROM partner_listings l
                JOIN partners p ON p.id = l.partner_id AND p.status = 'active'
                WHERE l.id = ? AND l.type = 'flight' AND l.active = TRUE
                """, flightListingId);
        if (rows.isEmpty()) {
            throw new ResponseStatusException(
                    HttpStatus.UNPROCESSABLE_ENTITY,
                    "Select an active partner flight for this offer");
        }
        BigDecimal flightPrice = decimal(rows.getFirst().get("price"), "flight price");
        BigDecimal hotelPrice = (BigDecimal) offer.get("hotel_price_per_night");
        int nights = ((Number) offer.get("duration_nights")).intValue();
        BigDecimal packageTotal = flightPrice
                .add(hotelPrice.multiply(BigDecimal.valueOf(nights)))
                .setScale(2, java.math.RoundingMode.HALF_UP);
        offer.put("flight_price_per_person", flightPrice);
        offer.put("price_per_person", packageTotal);
    }

    private static Map<String, Object> monumentPayload(Map<String, Object> row) {
        Map<String, Object> payload = new LinkedHashMap<>(row);
        payload.put("name", row.get("title"));
        payload.put("city", firstLocationPart(row.get("location"), 0));
        payload.put("country", firstLocationPart(row.get("location"), 1));
        payload.put("tags", parseStringList(row.get("tags")));
        return payload;
    }

    private static Map<String, Object> offerPayload(Map<String, Object> row) {
        Map<String, Object> payload = new LinkedHashMap<>(row);
        payload.put("highlights", parseStringList(row.get("highlights")));
        Map<String, Object> flight = flightListingPayload(row);
        if (flight != null) {
            payload.put("flight", flight);
            BigDecimal flightPrice = row.get("linked_flight_price") == null
                    ? BigDecimal.ZERO
                    : decimal(row.get("linked_flight_price"), "flight price");
            BigDecimal hotelPrice = row.get("hotel_price_per_night") == null
                    ? BigDecimal.ZERO
                    : decimal(row.get("hotel_price_per_night"), "hotel price");
            int nights = ((Number) row.get("duration_nights")).intValue();
            BigDecimal total = flightPrice.add(
                    hotelPrice.multiply(BigDecimal.valueOf(nights)));
            payload.put("flight_price_per_person", flightPrice);
            payload.put("price_per_person", total);
            payload.put("total_price_per_person", total);
        } else {
            payload.put("flight", null);
            BigDecimal flightPrice = row.get("flight_price_per_person") == null
                    ? BigDecimal.ZERO
                    : decimal(row.get("flight_price_per_person"), "flight price");
            BigDecimal hotelPrice = row.get("hotel_price_per_night") == null
                    ? BigDecimal.ZERO
                    : decimal(row.get("hotel_price_per_night"), "hotel price");
            BigDecimal total = flightPrice.add(hotelPrice
                            .multiply(BigDecimal.valueOf(
                                    row.get("duration_nights") instanceof Number n
                                            ? n.intValue() : 0)));
            payload.put("total_price_per_person", total);
        }
        String badge = text(row.get("badge")).trim();
        boolean featured = Boolean.TRUE.equals(row.get("is_featured"))
                || "1".equals(String.valueOf(row.get("is_featured")))
                || "true".equalsIgnoreCase(String.valueOf(row.get("is_featured")));
        payload.put("badge", badge.isEmpty() && featured ? "Featured Offer" : badge);
        return payload;
    }

    private static Map<String, Object> flightListingPayload(Map<String, Object> row) {
        Object rawId = row.get("linked_flight_id");
        if (rawId == null) return null;
        long id = ((Number) rawId).longValue();
        Map<String, Object> attributes = parseObject(row.get("flight_attributes"));
        boolean active = booleanValue(row.get("flight_active"), false);
        Map<String, Object> flight = new LinkedHashMap<>(attributes);
        flight.put("id", "partner-" + id);
        flight.put("partner_listing_id", id);
        flight.put("title", row.get("flight_title"));
        flight.put("city", row.get("flight_city"));
        flight.put("country", row.get("flight_country"));
        flight.put("airline", row.get("flight_airline"));
        flight.put("origin_city", attributeText(
                attributes, "origin_city", text(row.get("flight_city"))));
        flight.put("destination_city",
                attributeText(attributes, "destination_city", ""));
        flight.put("airline_code", attributeText(attributes, "airline_code", ""));
        flight.put("flight_number", attributeText(attributes, "flight_number", ""));
        flight.put("economy_price", row.get("linked_flight_price"));
        flight.put("airline_logo_url",
                attributeText(attributes, "airline_logo_url", ""));
        flight.put("source", "partner");
        flight.put("is_active", active);
        flight.put("status", active ? "published" : "inactive");
        return flight;
    }

    private static String firstLocationPart(Object value, int index) {
        String[] parts = String.valueOf(value == null ? "" : value).split(",", 2);
        if (index >= parts.length) return "";
        return parts[index].trim();
    }

    private static String requiredText(Map<String, Object> body, String key, int maxLength) {
        String value = text(body.get(key)).trim();
        if (value.isEmpty() || value.length() > maxLength) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, key + " is required");
        }
        return value;
    }

    private static String optionalText(
            Map<String, Object> body, String key, int maxLength) {
        return optionalText(body, key, maxLength, "");
    }

    private static String optionalText(
            Map<String, Object> body, String key, int maxLength, String fallback) {
        String value = body.get(key) == null ? fallback : text(body.get(key)).trim();
        if (value.length() > maxLength) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, key + " is too long");
        }
        return value;
    }

    private static java.math.BigDecimal rating(Object raw) {
        java.math.BigDecimal value = nonNegativeMoney(raw, "rating");
        if (value.compareTo(java.math.BigDecimal.valueOf(5)) > 0) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "rating must be at most 5");
        }
        return value;
    }

    private static java.math.BigDecimal nonNegativeMoney(Object raw, String key) {
        java.math.BigDecimal value = decimal(raw, key);
        if (value.signum() < 0 || value.precision() > 10 || value.scale() > 2) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, key + " is invalid");
        }
        return value;
    }

    private static java.math.BigDecimal optionalMoney(Object raw, String key) {
        return raw == null || String.valueOf(raw).isBlank()
                ? null
                : nonNegativeMoney(raw, key);
    }

    private static java.math.BigDecimal decimal(Object raw, String key) {
        try {
            return new java.math.BigDecimal(String.valueOf(raw));
        } catch (NumberFormatException exception) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, key + " must be numeric");
        }
    }

    private static int nonNegativeInt(Object raw, String key) {
        try {
            int value = Integer.parseInt(String.valueOf(raw));
            if (value < 0) throw new NumberFormatException();
            return value;
        } catch (NumberFormatException exception) {
            throw new ResponseStatusException(
                    HttpStatus.BAD_REQUEST, key + " must be a non-negative integer");
        }
    }

    private static boolean booleanValue(Object raw, boolean fallback) {
        if (raw == null) return fallback;
        if (raw instanceof Boolean value) return value;
        if ("true".equalsIgnoreCase(String.valueOf(raw))
                || "1".equals(String.valueOf(raw))) return true;
        if ("false".equalsIgnoreCase(String.valueOf(raw))
                || "0".equals(String.valueOf(raw))
                || String.valueOf(raw).isBlank()) return false;
        throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "Boolean value is invalid");
    }

    private static List<String> stringList(Object raw, String key) {
        if (raw == null) return List.of();
        if (!(raw instanceof List<?> values)) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, key + " must be a list");
        }
        List<String> result = new ArrayList<>();
        for (Object value : values) {
            String text = String.valueOf(value).trim();
            if (!text.isEmpty() && !result.contains(text)) result.add(text);
            if (result.size() > 100) {
                throw new ResponseStatusException(HttpStatus.BAD_REQUEST, key + " has too many items");
            }
        }
        return List.copyOf(result);
    }

    private static List<String> parseStringList(Object raw) {
        if (raw instanceof List<?> values) {
            return values.stream().map(String::valueOf).toList();
        }
        if (raw == null) return List.of();
        try {
            return JSON.readValue(
                    raw.toString(),
                    JSON.getTypeFactory().constructCollectionType(List.class, String.class));
        } catch (com.fasterxml.jackson.core.JsonProcessingException exception) {
            throw new IllegalStateException("Stored catalog tags are invalid JSON", exception);
        }
    }

    private static Map<String, Object> parseObject(Object raw) {
        if (raw instanceof Map<?, ?> values) {
            Map<String, Object> result = new LinkedHashMap<>();
            values.forEach((key, value) -> result.put(String.valueOf(key), value));
            return result;
        }
        if (raw == null || raw.toString().isBlank()) return new LinkedHashMap<>();
        try {
            return JSON.readValue(
                    raw.toString(),
                    JSON.getTypeFactory().constructMapType(
                            Map.class, String.class, Object.class));
        } catch (com.fasterxml.jackson.core.JsonProcessingException exception) {
            throw new IllegalStateException("Stored partner listing attributes are invalid JSON", exception);
        }
    }

    private static List<Map<String, Object>> reviewDecisions(Object raw) {
        if (!(raw instanceof List<?> values)) {
            throw new ResponseStatusException(
                    HttpStatus.BAD_REQUEST, "listings must contain a decision for every attraction");
        }
        List<Map<String, Object>> decisions = new ArrayList<>();
        for (Object value : values) {
            if (!(value instanceof Map<?, ?> fields)) {
                throw new ResponseStatusException(
                        HttpStatus.BAD_REQUEST, "Each listing decision must be an object");
            }
            Map<String, Object> decision = new LinkedHashMap<>();
            fields.forEach((key, fieldValue) ->
                    decision.put(String.valueOf(key), fieldValue));
            decisions.add(decision);
        }
        return decisions;
    }

    private static long positiveLong(Object raw, String key) {
        try {
            long value = Long.parseLong(String.valueOf(raw));
            if (value <= 0) throw new NumberFormatException();
            return value;
        } catch (NumberFormatException exception) {
            throw new ResponseStatusException(
                    HttpStatus.BAD_REQUEST, key + " must be a positive integer");
        }
    }

    private String createMonumentFromLegacyListing(Map<String, Object> source) {
        Map<String, Object> attributes = parseObject(source.get("attributes"));
        String title = text(source.get("title")).trim();
        String city = text(source.get("city")).trim();
        String country = text(source.get("country")).trim();
        String description = text(source.get("description")).trim();
        if (title.isEmpty() || city.isEmpty() || description.isEmpty()) {
            throw new ResponseStatusException(
                    HttpStatus.BAD_REQUEST,
                    "A place needs a title, city, and description; choose an existing place or omit it");
        }
        String location = country.isEmpty() ? city : city + ", " + country;
        String categoryValue = attributeText(attributes, "category", "landmark")
                .toLowerCase(Locale.ROOT);
        Set<String> allowedCategories =
                Set.of("landmark", "museum", "park", "beach", "restaurant", "shopping");
        String category = allowedCategories.contains(categoryValue)
                ? categoryValue
                : "landmark";
        String categoryTag = attributeText(
                attributes, "category_tag", attributeText(attributes, "category", ""));
        String workingHours = attributeText(
                attributes, "opening_hours", attributeText(attributes, "working_hours", ""));
        String bestTime = attributeText(attributes, "best_time_to_visit", "");
        List<String> tags = parseStringList(attributes.get("tags"));
        java.math.BigDecimal rating = sourceRating(
                attributes.get("rating"), source.get("google_rating"));
        int reviewCount = sourceReviewCount(
                attributes.get("review_count"), source.get("google_review_count"));
        Object entryFee = attributes.get("entry_fee") != null
                ? attributes.get("entry_fee")
                : source.get("price");
        java.math.BigDecimal validEntryFee =
                entryFee == null ? null : nonNegativeMoney(entryFee, "entry_fee");
        String id = UUID.randomUUID().toString();
        jdbc.update("""
                INSERT INTO tourist_monuments (
                    id, title, location, category_tag, category, rating,
                    review_count, description, working_hours, best_time_to_visit,
                    entry_fee, image_url, tags, is_active
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, CAST(? AS JSONB), TRUE)
                """,
                id,
                title,
                location,
                categoryTag,
                category,
                rating,
                reviewCount,
                description,
                workingHours,
                bestTime,
                validEntryFee,
                text(source.get("image_url")),
                jsonList(tags));
        return id;
    }

    private static String attributeText(
            Map<String, Object> attributes, String key, String fallback) {
        Object value = attributes.get(key);
        return value == null ? fallback : text(value).trim();
    }

    private static java.math.BigDecimal sourceRating(Object preferred, Object fallback) {
        java.math.BigDecimal value = sourceDecimal(preferred, fallback);
        if (value.signum() < 0 || value.compareTo(java.math.BigDecimal.valueOf(5)) > 0) {
            return java.math.BigDecimal.ZERO;
        }
        return value;
    }

    private static java.math.BigDecimal sourceDecimal(Object preferred, Object fallback) {
        for (Object candidate : List.of(
                preferred == null ? "" : preferred,
                fallback == null ? "" : fallback)) {
            try {
                if (!String.valueOf(candidate).isBlank()) {
                    return new java.math.BigDecimal(String.valueOf(candidate));
                }
            } catch (NumberFormatException ignored) {
                // Try the next source value, then default to zero.
            }
        }
        return java.math.BigDecimal.ZERO;
    }

    private static int sourceReviewCount(Object preferred, Object fallback) {
        for (Object candidate : List.of(
                preferred == null ? "" : preferred,
                fallback == null ? "" : fallback)) {
            try {
                int value = Integer.parseInt(String.valueOf(candidate));
                return Math.max(value, 0);
            } catch (NumberFormatException ignored) {
                // Try the next source value, then default to zero.
            }
        }
        return 0;
    }

    private boolean isAttractionPartner(long id) {
        Integer count = jdbc.queryForObject("""
                SELECT COUNT(*) FROM partners
                WHERE id = ? AND LOWER(service_type) = 'attraction'
                """, Integer.class, id);
        return count != null && count > 0;
    }

    private boolean legacyAttractionReviewStorageExists() {
        return Boolean.TRUE.equals(jdbc.queryForObject(
                "SELECT to_regclass('legacy_attraction_partner_reviews') IS NOT NULL",
                Boolean.class));
    }

    private static String jsonList(Object raw) {
        try {
            return JSON.writeValueAsString(raw);
        } catch (com.fasterxml.jackson.core.JsonProcessingException exception) {
            throw new IllegalArgumentException("Catalog tags could not be encoded", exception);
        }
    }

    private static String text(Object value) {
        return value == null ? "" : String.valueOf(value);
    }

    private List<Map<String, Object>> recentReservations(int limit) {
        return jdbc.queryForList("""
                SELECT *
                FROM (
                    SELECT CONCAT('flight-', t.id) AS id, 'Flight' AS type,
                        t.title, u.name AS customer_name,
                        COALESCE(t.departure_date, t.created_at) AS reservation_date,
                        COALESCE(t.price, 0) AS amount, t.status, t.created_at
                    FROM trips t JOIN users u ON u.id = t.user_id
                    UNION ALL
                    SELECT CONCAT('booking-', b.id) AS id, b.type,
                        COALESCE(b.title, b.subtitle, 'Booking') AS title,
                        u.name AS customer_name,
                        COALESCE(b.date, b.created_at) AS reservation_date,
                        COALESCE(b.total_amount, b.price, 0) AS amount,
                        b.status, b.created_at
                    FROM bookings b JOIN users u ON u.id = b.user_id
                    UNION ALL
                    SELECT CONCAT('transfer-', x.id) AS id, 'Transfer' AS type,
                        CONCAT(x.pickup_location, ' to ', x.dropoff_location) AS title,
                        u.name AS customer_name, x.pickup_time AS reservation_date,
                        x.price AS amount, x.status, x.created_at
                    FROM transfers x JOIN users u ON u.id = x.user_id
                ) reservations
                ORDER BY created_at DESC
                LIMIT ?
                """, limit);
    }

    private static void validateLimit(int limit) {
        if (limit < 1 || limit > 100) {
            throw new ResponseStatusException(
                    HttpStatus.BAD_REQUEST, "limit must be between 1 and 100");
        }
    }

    private void requireCatalogItem(String query, String id, String message) {
        if (!catalogItemExists(query, id)) {
            throw new ResponseStatusException(HttpStatus.NOT_FOUND, message);
        }
    }

    private boolean catalogItemExists(String query, String id) {
        Integer count = jdbc.queryForObject(query, Integer.class, id);
        return count != null && count > 0;
    }

    private boolean hasOfferFlightLinkColumn() {
        Boolean exists = jdbc.queryForObject("""
                SELECT EXISTS (
                    SELECT 1
                    FROM pg_attribute
                    WHERE attrelid = to_regclass('public.offers')
                      AND attname = 'flight_listing_id'
                      AND NOT attisdropped
                )
                """, Boolean.class);
        return Boolean.TRUE.equals(exists);
    }

    private long requireAdminId(HttpServletRequest request) {
        Object userId = request.getAttribute("authUserId");
        if (!(userId instanceof Number number)) {
            throw new ResponseStatusException(
                    HttpStatus.UNAUTHORIZED, "Unauthenticated");
        }
        String role = jdbc.queryForObject(
                "SELECT role FROM users WHERE id = ?",
                String.class,
                number.longValue());
        if (!"admin".equalsIgnoreCase(role)) {
            throw new ResponseStatusException(
                    HttpStatus.FORBIDDEN, "Administrator access required");
        }
        return number.longValue();
    }
}
