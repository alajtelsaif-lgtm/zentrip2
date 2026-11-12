package com.zentrip.api;

import java.net.URI;
import java.net.URLEncoder;
import java.nio.charset.StandardCharsets;
import java.text.Normalizer;
import java.time.Duration;
import java.time.Instant;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.LinkedHashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.TimeUnit;
import java.util.function.Supplier;
import java.util.regex.Pattern;

import jakarta.annotation.PostConstruct;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpStatus;
import org.springframework.http.client.SimpleClientHttpRequestFactory;
import org.springframework.stereotype.Service;
import org.springframework.web.client.ResourceAccessException;
import org.springframework.web.client.RestClient;
import org.springframework.web.client.RestClientException;
import org.springframework.web.client.RestClientResponseException;
import org.springframework.web.server.ResponseStatusException;

/**
 * OpenTripMap is the only external place/landmark provider used by this service.
 * The API key is only ever attached to server-side provider requests.
 */
@Service
public class OpenTripMapAttractionService implements LandmarkProvider {
    private static final Logger LOG =
            LoggerFactory.getLogger(OpenTripMapAttractionService.class);

    private static final String BASE_URL = "https://api.opentripmap.com/0.1";
    private static final int SEARCH_RADIUS_METERS = 25_000;
    private static final int PROVIDER_LIMIT = 250;
    private static final int DETAILS_LIMIT = 80;
    private static final int RESULT_LIMIT = 80;
    private static final int DROPPED_EXAMPLE_LIMIT = 250;
    private static final Duration SEARCH_TTL = Duration.ofHours(24);
    private static final Duration DETAILS_TTL = Duration.ofDays(7);
    private static final Duration SUGGESTIONS_TTL = Duration.ofMinutes(15);
    private static final long REQUEST_SPACING_NANOS = TimeUnit.MILLISECONDS.toNanos(100);
    private static final Pattern XID = Pattern.compile("^[A-Za-z0-9_-]{1,64}$");
    private static final Pattern CODE_OR_NUMBER = Pattern.compile("^[\\p{N}\\p{Punct}\\s]+$");
    private static final Pattern SHORT_CODE_NAME =
            Pattern.compile("(?i)^[A-Z]{2,6}\\d{1,5}$");
    private static final Set<String> ISO_COUNTRY_CODES =
            Set.of(Locale.getISOCountries());
    private static final Map<String, String> COUNTRY_NAME_TO_CODE =
            buildCountryNameIndex();

    /*
     * These are category IDs copied from OpenTripMap's published category tree.
     * Parent/leaf IDs are sent with OR semantics and then checked again locally.
     */
    private static final Set<String> ALLOWED_KINDS = Set.of(
            "natural", "natural_springs", "mountain_peaks", "caves", "waterfalls",
            "other_lakes", "beaches", "nature_reserves", "national_parks",
            "natural_monuments", "museums", "national_museums", "local_museums",
            "museums_of_science_and_technology", "maritime_museums",
            "railway_museums", "aviation_museums", "automobile_museums",
            "other_technology_museums", "science_museums", "military_museums",
            "history_museums", "archaeological_museums", "biographical_museums",
            "open_air_museums", "fashion_museums", "children_museums",
            "historic_house_museums", "other_museums", "gardens_and_parks",
            "historic", "historical_places", "historic_districts",
            "historic_settlements", "fortifications", "castles", "hillforts",
            "fortified_towers", "other_fortifications", "monuments_and_memorials",
            "monuments", "archaeology", "cave_paintings",
            "other_archaeological_sites", "architecture", "historic_architecture",
            "historic_object");
    private static final String ALL_KINDS = String.join(",", ALLOWED_KINDS);

    private static final Set<String> BUSINESS_KINDS = Set.of(
            "foods", "restaurants", "cafes", "fast_food", "food_courts", "shops",
            "supermarkets", "marketplaces", "banks", "accomodations", "hotels",
            "hostels", "adult_hotels", "transport", "fuel", "parking",
            "pharmacies", "clinics", "schools", "gyms", "salons", "nightclubs",
            "bars", "offices", "residential", "apartments", "streets", "bus_stops",
            "neighborhoods", "districts", "cities");
    private static final Set<String> GENERIC_NAMES = Set.of(
            "park", "museum", "monument", "attraction", "landmark", "historic site",
            "historical site", "building", "beach", "castle", "garden", "city",
            "district", "neighborhood");

    private static final ExecutorService DETAIL_EXECUTOR =
            Executors.newFixedThreadPool(4, task -> {
                Thread thread = new Thread(task, "opentripmap-details");
                thread.setDaemon(true);
                return thread;
            });

    private final String apiKey;
    private final boolean commercialUse;
    private final boolean freePlan;
    private final RestClient client;
    private final RestClient wikipediaClient;
    private final Map<String, TimedEntry<SearchOutcome>> searchCache =
            new ConcurrentHashMap<>();
    private final Map<String, TimedEntry<Map<String, Object>>> detailCache =
            new ConcurrentHashMap<>();
    private final Map<String, TimedEntry<String>> wikipediaImageCache =
            new ConcurrentHashMap<>();
    private final Map<String, TimedEntry<List<Map<String, Object>>>> suggestionCache =
            new ConcurrentHashMap<>();
    private final Map<String, TimedEntry<Geoname>> destinationGeonameCache =
            new ConcurrentHashMap<>();
    private final Object requestGate = new Object();
    private long nextRequestNanos;

    @Autowired
    public OpenTripMapAttractionService(
            @Value("${opentripmap.api-key:}") String apiKey,
            @Value("${app.commercial-use:true}") boolean commercialUse,
            @Value("${opentripmap.free-plan:true}") boolean freePlan) {
        this(apiKey, commercialUse, freePlan, createClient());
    }

    OpenTripMapAttractionService(
            String apiKey,
            boolean commercialUse,
            boolean freePlan,
            RestClient client) {
        this(apiKey, commercialUse, freePlan, client, createWikipediaClient());
    }

    OpenTripMapAttractionService(
            String apiKey,
            boolean commercialUse,
            boolean freePlan,
            RestClient client,
            RestClient wikipediaClient) {
        this.apiKey = apiKey == null ? "" : apiKey.trim();
        this.commercialUse = commercialUse;
        this.freePlan = freePlan;
        this.client = client;
        this.wikipediaClient = wikipediaClient;
    }

    private static RestClient createClient() {
        SimpleClientHttpRequestFactory requestFactory =
                new SimpleClientHttpRequestFactory();
        requestFactory.setConnectTimeout(Duration.ofSeconds(3));
        requestFactory.setReadTimeout(Duration.ofSeconds(8));
        return RestClient.builder()
                .baseUrl(BASE_URL)
                .requestFactory(requestFactory)
                .build();
    }

    private static RestClient createWikipediaClient() {
        SimpleClientHttpRequestFactory requestFactory =
                new SimpleClientHttpRequestFactory();
        requestFactory.setConnectTimeout(Duration.ofSeconds(2));
        requestFactory.setReadTimeout(Duration.ofSeconds(3));
        return RestClient.builder()
                .requestFactory(requestFactory)
                .build();
    }

    @PostConstruct
    void warnWhenFreePlanIsUsedCommercially() {
        if (commercialUse && freePlan) {
            LOG.warn("OpenTripMap free plan is for non-commercial use only "
                    + "(5,000 requests/day, 10 requests/second). "
                    + "Confirm a commercial plan before enabling this provider in production.");
        }
    }

    public SearchOutcome searchAttractionsWithStatus(
            String city, String country, String language) {
        return searchAttractionsWithStatus(
                city, country, language, null, null, null,
                null, null, null, null, null);
    }

    public SearchOutcome searchAttractionsWithStatus(
            String city,
            String country,
            String language,
            String category,
            Double latitude,
            Double longitude,
            Double south,
            Double west,
            Double north,
            Double east,
            String xid) {
        requireApiKey();
        String normalizedCity = clean(city);
        String normalizedCountry = clean(country);
        String apiLanguage = apiLanguage(language);
        String normalizedCategory = normalizeCategory(category);
        String normalizedXid = clean(xid);
        if ("unsupported".equals(normalizedCategory)) {
            return new SearchOutcome(
                    List.of(), null, 0, Map.of(), List.of(),
                    List.of("OpenTripMap does not provide this category."), 0);
        }
        String cacheKey = String.join("|",
                normalizedCity == null ? "" : normalizedCity.toLowerCase(Locale.ROOT),
                normalizedCountry == null
                        ? "" : normalizedCountry.toLowerCase(Locale.ROOT),
                apiLanguage,
                normalizedCategory,
                coordinateKey(latitude), coordinateKey(longitude),
                coordinateKey(south), coordinateKey(west),
                coordinateKey(north), coordinateKey(east),
                normalizedXid);
        TimedEntry<SearchOutcome> cached = searchCache.get(cacheKey);
        Instant now = Instant.now();
        if (cached != null && now.isBefore(cached.expiresAt())) {
            return cached.value();
        }

        try {
            Map<String, Object> selectedDetail =
                    normalizedXid == null ? null : getDetails(normalizedXid, apiLanguage);
            GeoPoint center = explicitPoint(
                    latitude, longitude, normalizedCity, normalizedCountry,
                    south, west, north, east);
            if (center == null && selectedDetail != null) {
                center = pointFromDetails(
                        selectedDetail, normalizedCity, normalizedCountry);
            }
            boolean cityFound = center != null;
            if (center == null) {
                String destination = normalizedCity == null
                        ? normalizedCountry : normalizedCity;
                if (destination == null) {
                    return emptyOutcome(false, "Enter a place or destination to search.");
                }
                Geoname geoname = geoname(destination, normalizedCountry, apiLanguage);
                if (geoname == null) {
                    return emptyOutcome(false, null);
                }
                center = new GeoPoint(
                        geoname.latitude(), geoname.longitude(),
                        geoname.name(), displayCountry(geoname.country(), normalizedCountry),
                        null, null, null, null);
                cityFound = true;
            }

            List<Map<?, ?>> candidates = fetchCandidates(
                    center, apiLanguage, normalizedCategory,
                    south, west, north, east);
            List<RejectedItem> dropped = new ArrayList<>();
            Map<String, Integer> droppedCounts = new LinkedHashMap<>();
            List<Candidate> eligible = new ArrayList<>();
            for (Map<?, ?> raw : candidates) {
                Candidate candidate = candidateFrom(raw, center);
                String reason = preDetailRejection(candidate, center,
                        south, west, north, east);
                if (reason != null) {
                    reject(candidate, reason, droppedCounts, dropped);
                } else {
                    eligible.add(candidate);
                }
            }
            if (selectedDetail != null) {
                Candidate selected = candidateFrom(selectedDetail, center);
                if (eligible.stream().noneMatch(item -> item.xid().equals(selected.xid()))) {
                    String reason = preDetailRejection(
                            selected, center, south, west, north, east);
                    if (reason == null) eligible.add(selected);
                    else reject(selected, reason, droppedCounts, dropped);
                }
            }

            eligible.sort(candidateComparator(center));
            List<Candidate> detailCandidates =
                    eligible.stream().limit(DETAILS_LIMIT).toList();
            List<CompletableFuture<DetailResult>> detailFutures = detailCandidates.stream()
                    .map(candidate -> CompletableFuture.supplyAsync(
                            () -> fetchDetailResult(candidate, apiLanguage),
                            DETAIL_EXECUTOR))
                    .toList();
            CompletableFuture.allOf(
                    detailFutures.toArray(CompletableFuture[]::new)).join();

            List<Map<String, Object>> places = new ArrayList<>();
            List<String> warnings = new ArrayList<>();
            for (CompletableFuture<DetailResult> future : detailFutures) {
                DetailResult detailResult = future.join();
                Candidate candidate = detailResult.candidate();
                if (detailResult.details() == null) {
                    warnings.add("Some OpenTripMap place details could not be loaded.");
                    continue;
                }
            Map<String, Object> details = detailResult.details();
            if (clean(text(details.get("image"))) == null
                    && clean(text(asMap(details.get("preview")).get("source"))) == null) {
                String wikipediaImage = wikipediaImage(
                        text(details.get("wikipedia")), language);
                if (wikipediaImage != null) {
                    details.put("_wikipedia_image_url", wikipediaImage);
                }
            }
            Candidate enriched = enrich(candidate, details);
                Validation validation = isRealLandmark(
                        enriched, center, south, west, north, east);
                if (!validation.accepted()) {
                    reject(enriched, validation.reason(), droppedCounts, dropped);
                    continue;
                }
                if (!categoryMatches(normalizedCategory, validation.category())) {
                    reject(enriched, "type", droppedCounts, dropped);
                    continue;
                }
                places.add(toPlace(enriched, center, apiLanguage));
            }

            places.sort(placeComparator(center));
            List<Map<String, Object>> unique = deduplicate(places, droppedCounts, dropped);
            List<Map<String, Object>> limited =
                    List.copyOf(unique.stream().limit(RESULT_LIMIT).toList());
            SearchOutcome outcome = new SearchOutcome(
                    limited,
                    cityFound,
                    candidates.size(),
                    Map.copyOf(droppedCounts),
                    List.copyOf(dropped.stream().limit(DROPPED_EXAMPLE_LIMIT).toList()),
                    warnings.stream().distinct().toList(),
                    unique.size());
            searchCache.put(cacheKey, new TimedEntry<>(outcome, now.plus(SEARCH_TTL)));
            return outcome;
        } catch (ResponseStatusException exception) {
            throw exception;
        } catch (RestClientException exception) {
            LOG.warn("OpenTripMap destination lookup unavailable ({})",
                    providerFailure(exception));
            throw unavailable();
        }
    }

    public List<Map<String, Object>> searchAttractions(
            String city, String country, String language) {
        return searchAttractionsWithStatus(city, country, language).places();
    }

    public DestinationSuggestion suggestDestination(String query) {
        return suggestDestination(query, "en");
    }

    public DestinationSuggestion suggestDestination(String query, String language) {
        String normalized = clean(query);
        if (normalized == null || apiKey.isBlank()) return null;
        String normalizedLanguage = "ar".equalsIgnoreCase(language) ? "ar" : "en";
        String cacheKey = normalize(normalized) + "|" + normalizedLanguage;
        Instant now = Instant.now();
        TimedEntry<Geoname> cached = destinationGeonameCache.get(cacheKey);
        if (cached != null && now.isBefore(cached.expiresAt())) {
            return toDestinationSuggestion(cached.value());
        }
        Geoname place = geoname(normalized, null, normalizedLanguage);
        destinationGeonameCache.put(
                cacheKey, new TimedEntry<>(place, now.plus(SUGGESTIONS_TTL)));
        return toDestinationSuggestion(place);
    }

    private static DestinationSuggestion toDestinationSuggestion(Geoname place) {
        return place == null ? null : new DestinationSuggestion(
                place.name(), place.country(), place.latitude(), place.longitude());
    }

    public List<Map<String, Object>> searchAtCoordinates(
            double latitude,
            double longitude,
            String city,
            String country,
            String language) {
        return searchAtCoordinates(
                latitude, longitude, city, country, language, null);
    }

    public List<Map<String, Object>> searchAtCoordinates(
            double latitude,
            double longitude,
            String city,
            String country,
            String language,
            String category) {
        return searchAttractionsWithStatus(
                city, country, language, category,
                latitude, longitude, null, null, null, null, null).places();
    }

    public List<Map<String, Object>> searchNearby(
            double latitude,
            double longitude,
            double radiusMeters,
            String category,
            String language) {
        String normalizedCategory = normalizeCategory(category);
        if ("unsupported".equals(normalizedCategory)) return List.of();
        if (!validCoordinates(latitude, longitude)) {
            throw new ResponseStatusException(
                    HttpStatus.BAD_REQUEST, "Valid latitude and longitude are required.");
        }
        double radius = Math.max(1_000, Math.min(100_000, radiusMeters));
        GeoPoint center = new GeoPoint(latitude, longitude, null, null, null,
                null, null, null);
        requireApiKey();
        String apiLanguage = apiLanguage(language);
        try {
            List<Map<?, ?>> candidates =
                    fetchCandidates(center, apiLanguage, normalizedCategory,
                            null, null, null, null, radius);
            return enrichAndFilter(
                    candidates, center, apiLanguage, normalizedCategory,
                    null, null, null, null);
        } catch (ResponseStatusException exception) {
            throw exception;
        } catch (RestClientException exception) {
            LOG.warn("OpenTripMap nearby search unavailable ({})",
                    providerFailure(exception));
            throw unavailable();
        }
    }

    public List<Map<String, Object>> suggestPlaces(
            String query, String language, Double contextLatitude, Double contextLongitude) {
        requireApiKey();
        String normalized = clean(query);
        if (normalized == null || normalized.length() < 2) return List.of();
        String apiLanguage = apiLanguage(language);
        String cacheKey = normalized.toLowerCase(Locale.ROOT) + "|" + apiLanguage
                + "|" + coordinateKey(contextLatitude) + "|"
                + coordinateKey(contextLongitude);
        TimedEntry<List<Map<String, Object>>> cached = suggestionCache.get(cacheKey);
        Instant now = Instant.now();
        if (cached != null && now.isBefore(cached.expiresAt())) {
            return cached.value();
        }

        List<Map<String, Object>> suggestions = new ArrayList<>();
        Geoname resolved = geoname(normalized, null, apiLanguage);
        if (resolved != null) {
            Map<String, Object> citySuggestion = new LinkedHashMap<>();
            citySuggestion.put("label", resolved.name());
            citySuggestion.put("city", resolved.name());
            citySuggestion.put("country", displayCountry(resolved.country(), ""));
            citySuggestion.put("country_code", resolved.country());
            citySuggestion.put("result_type", "city");
            citySuggestion.put("latitude", resolved.latitude());
            citySuggestion.put("longitude", resolved.longitude());
            suggestions.add(citySuggestion);
        }

        Double contextLat = validCoordinates(contextLatitude, contextLongitude)
                ? contextLatitude : resolved == null ? null : resolved.latitude();
        Double contextLon = validCoordinates(contextLatitude, contextLongitude)
                ? contextLongitude : resolved == null ? null : resolved.longitude();
        if (normalized.length() >= 3 && contextLat != null && contextLon != null) {
            try {
                List<?> response = retry(() -> client.get()
                        .uri(uri -> uri.path("/{lang}/places/autosuggest")
                                .queryParam("name", normalized)
                                .queryParam("radius", SEARCH_RADIUS_METERS)
                                .queryParam("lat", contextLat)
                                .queryParam("lon", contextLon)
                                .queryParam("kinds", ALL_KINDS)
                                .queryParam("limit", 8)
                                .queryParam("format", "json")
                                .queryParam("apikey", apiKey)
                                .build(apiLanguage))
                        .retrieve()
                        .body(List.class));
                for (Object item : safeList(response)) {
                    Map<?, ?> raw = asMap(item);
                    Candidate candidate = candidateFrom(raw, new GeoPoint(
                            contextLat, contextLon, null, null, null,
                            null, null, null));
                    if (preDetailRejection(candidate, null, null, null, null, null) != null) {
                        continue;
                    }
                    Map<String, Object> suggestion = new LinkedHashMap<>();
                    suggestion.put("label", candidate.name());
                    suggestion.put("city", resolved == null ? "" : resolved.name());
                    suggestion.put("country", resolved == null
                            ? "" : displayCountry(resolved.country(), ""));
                    suggestion.put("country_code", resolved == null
                            ? "" : nonBlank(resolved.country(), ""));
                    suggestion.put("result_type", "landmark");
                    suggestion.put("place_id", candidate.xid());
                    suggestion.put("latitude", candidate.latitude());
                    suggestion.put("longitude", candidate.longitude());
                    suggestions.add(suggestion);
                }
            } catch (RestClientException exception) {
                LOG.warn("OpenTripMap autosuggest unavailable ({})",
                        providerFailure(exception));
                if (resolved == null) throw unavailable();
            }
        }

        List<Map<String, Object>> unique = deduplicateSuggestions(suggestions);
        List<Map<String, Object>> immutable = List.copyOf(unique);
        suggestionCache.put(
                cacheKey, new TimedEntry<>(immutable, now.plus(SUGGESTIONS_TTL)));
        return immutable;
    }

    public static Validation isRealLandmark(
            Candidate candidate,
            GeoPoint center,
            Double south,
            Double west,
            Double north,
            Double east) {
        if (candidate == null) return Validation.reject("type");
        if (isHistoricalEvent(candidate)) return Validation.reject("event");
        if (isBusiness(candidate)) return Validation.reject("business");
        String category = categoryForKinds(candidate.kinds());
        if (category == null) return Validation.reject("type");
        String name = clean(candidate.name());
        if (candidate.xid() == null || !XID.matcher(candidate.xid()).matches()
                || name == null || CODE_OR_NUMBER.matcher(name).matches()
                || SHORT_CODE_NAME.matcher(name).matches()
                || GENERIC_NAMES.contains(normalize(name))) {
            return Validation.reject("no_identity");
        }
        if (!validCoordinates(candidate.latitude(), candidate.longitude())) {
            return Validation.reject("location");
        }
        if (!insideBounds(candidate.latitude(), candidate.longitude(),
                south, west, north, east)) {
            return Validation.reject("location");
        }
        if (center != null
                && distanceMeters(
                        center.latitude(), center.longitude(),
                        candidate.latitude(), candidate.longitude()) > SEARCH_RADIUS_METERS) {
            return Validation.reject("location");
        }
        if (popularity(candidate.rate()) < 2
                && clean(candidate.wikidataId()) == null
                && clean(candidate.wikipediaUrl()) == null
                && clean(candidate.imageUrl()) == null
                && clean(candidate.previewUrl()) == null) {
            return Validation.reject("no_identity");
        }
        return Validation.accept(category);
    }

    private SearchOutcome emptyOutcome(boolean cityFound, String warning) {
        List<String> warnings = warning == null ? List.of() : List.of(warning);
        return new SearchOutcome(
                List.of(), cityFound, 0, Map.of(), List.of(), warnings, 0);
    }

    private void requireApiKey() {
        if (apiKey.isBlank()) {
            throw new ResponseStatusException(
                    HttpStatus.SERVICE_UNAVAILABLE,
                    "OpenTripMap is not configured. Add OPENTRIPMAP_API_KEY to server secrets.");
        }
    }

    private Geoname geoname(String placeName, String country, String language) {
        String query = clean(placeName);
        if (query == null) return null;
        try {
            Map<?, ?> result = retry(() -> client.get()
                    .uri(uri -> {
                        var builder = uri.path("/{lang}/places/geoname")
                                .queryParam("name", query)
                                .queryParam("apikey", apiKey);
                        String countryCode = isoCountry(country);
                        if (countryCode != null) {
                            builder.queryParam("country", countryCode);
                        }
                        return builder.build(language);
                    })
                    .retrieve()
                    .body(Map.class));
            if (result == null) return null;
            Double latitude = number(result.get("lat"));
            Double longitude = number(result.get("lon"));
            if (!validCoordinates(latitude, longitude)) return null;
            String requestedCountryCode = isoCountry(country);
            String resolvedCountryCode = isoCountry(text(result.get("country")));
            if (requestedCountryCode != null
                    && !requestedCountryCode.equals(resolvedCountryCode)) {
                return null;
            }
            return new Geoname(
                    nonBlank(text(result.get("name")), query),
                    text(result.get("country")), latitude, longitude);
        } catch (RestClientResponseException exception) {
            if (exception.getStatusCode().value() == 404) return null;
            LOG.warn("OpenTripMap geoname lookup unavailable (HTTP {})",
                    exception.getStatusCode().value());
            throw unavailable();
        }
    }

    private List<Map<?, ?>> fetchCandidates(
            GeoPoint center,
            String language,
            String category,
            Double south,
            Double west,
            Double north,
            Double east) {
        return fetchCandidates(
                center, language, category, south, west, north, east,
                SEARCH_RADIUS_METERS);
    }

    private List<Map<?, ?>> fetchCandidates(
            GeoPoint center,
            String language,
            String category,
            Double south,
            Double west,
            Double north,
            Double east,
            double radiusMeters) {
        boolean hasBounds = validBounds(south, west, north, east);
        return retry(() -> {
            List<?> response = client.get()
                    .uri(uri -> {
                        var builder = uri.path(hasBounds
                                        ? "/{lang}/places/bbox"
                                        : "/{lang}/places/radius");
                        if (hasBounds) {
                            builder.queryParam("lon_min", west)
                                    .queryParam("lat_min", south)
                                    .queryParam("lon_max", east)
                                    .queryParam("lat_max", north);
                        } else {
                            builder.queryParam("radius", radiusMeters)
                                    .queryParam("lon", center.longitude())
                                    .queryParam("lat", center.latitude());
                        }
                        return builder
                                .queryParam("kinds", kindsForCategory(category))
                                .queryParam("format", "json")
                                .queryParam("limit", PROVIDER_LIMIT)
                                .queryParam("offset", 0)
                                .queryParam("apikey", apiKey)
                                .build(language);
                    })
                    .retrieve()
                    .body(List.class);
            return safeList(response).stream().map(OpenTripMapAttractionService::asMap)
                    .toList();
        });
    }

    private Map<String, Object> getDetails(String xid, String language) {
        if (xid == null || !XID.matcher(xid).matches()) return null;
        String cacheKey = language + "|" + xid;
        TimedEntry<Map<String, Object>> cached = detailCache.get(cacheKey);
        Instant now = Instant.now();
        if (cached != null && now.isBefore(cached.expiresAt())) return cached.value();
        try {
            Map<?, ?> response = retry(() -> client.get()
                    .uri(uri -> uri.path("/{lang}/places/xid/{xid}")
                            .queryParam("apikey", apiKey)
                            .build(language, xid))
                    .retrieve()
                    .body(Map.class));
            if (response == null) return null;
            Map<String, Object> details = stringMap(response);
            detailCache.put(cacheKey, new TimedEntry<>(details, now.plus(DETAILS_TTL)));
            return details;
        } catch (RestClientResponseException exception) {
            if (exception.getStatusCode().value() == 404) return null;
            throw exception;
        }
    }

    private DetailResult fetchDetailResult(Candidate candidate, String language) {
        try {
            return new DetailResult(candidate, getDetails(candidate.xid(), language));
        } catch (RestClientException exception) {
            LOG.debug("OpenTripMap details unavailable for xid {} ({})",
                    candidate.xid(), providerFailure(exception));
            return new DetailResult(candidate, null);
        }
    }

    private String wikipediaImage(String article, String language) {
        String title = wikipediaTitle(article);
        if (title == null) return null;
        String apiLanguage = apiLanguage(language);
        String cacheKey = apiLanguage + "|" + title.toLowerCase(Locale.ROOT);
        Instant now = Instant.now();
        TimedEntry<String> cached = wikipediaImageCache.get(cacheKey);
        if (cached != null && now.isBefore(cached.expiresAt())) {
            return cached.value().isBlank() ? null : cached.value();
        }

        String encodedTitle = URLEncoder.encode(
                title.replace(' ', '_'), StandardCharsets.UTF_8).replace("+", "%20");
        String endpoint = "https://" + apiLanguage
                + ".wikipedia.org/api/rest_v1/page/summary/" + encodedTitle;
        String image = null;
        try {
            Map<?, ?> summary = wikipediaClient.get()
                    .uri(URI.create(endpoint))
                    .retrieve()
                    .body(Map.class);
            if (summary != null) {
                image = firstNonBlank(
                        text(asMap(summary.get("original")).get("source")),
                        text(asMap(summary.get("thumbnail")).get("source")));
                if (!isHttpUrl(image)) image = null;
            }
        } catch (RestClientException | IllegalArgumentException exception) {
            LOG.debug("Wikipedia image fallback unavailable for OpenTripMap article {}",
                    article);
        }
        wikipediaImageCache.put(cacheKey, new TimedEntry<>(
                image == null ? "" : image, now.plus(DETAILS_TTL)));
        return image;
    }

    private static String wikipediaTitle(String article) {
        String value = clean(article);
        if (value == null) return null;
        if (value.startsWith("https://") || value.startsWith("http://")) {
            try {
                String path = URI.create(value).getPath();
                int wikiIndex = path == null ? -1 : path.indexOf("/wiki/");
                if (wikiIndex >= 0) value = path.substring(wikiIndex + 6);
            } catch (IllegalArgumentException ignored) {
                return null;
            }
        } else if (value.matches("(?i)^[a-z]{2,3}:.*")) {
            value = value.substring(value.indexOf(':') + 1);
        }
        value = value.replace('_', ' ').trim();
        return value.isBlank() ? null : value;
    }

    private static String wikipediaUrl(String article, String language) {
        String value = clean(article);
        if (value == null) return null;
        if (isHttpUrl(value)) return value;
        String title = wikipediaTitle(value);
        if (title == null) return null;
        String encodedTitle = URLEncoder.encode(
                title.replace(' ', '_'), StandardCharsets.UTF_8).replace("+", "%20");
        return "https://" + apiLanguage(language) + ".wikipedia.org/wiki/" + encodedTitle;
    }

    private static boolean isHttpUrl(String value) {
        if (value == null || value.isBlank()) return false;
        try {
            URI uri = URI.create(value);
            return ("https".equalsIgnoreCase(uri.getScheme())
                    || "http".equalsIgnoreCase(uri.getScheme()))
                    && uri.getHost() != null;
        } catch (IllegalArgumentException ignored) {
            return false;
        }
    }

    static String displayImageUrl(
            String previewUrl, String wikipediaImage, String providerImage) {
        for (String candidate : List.of(
                previewUrl == null ? "" : previewUrl,
                wikipediaImage == null ? "" : wikipediaImage,
                providerImage == null ? "" : providerImage)) {
            String image = clean(candidate);
            if (!isHttpUrl(image)) continue;
            String commonsImage = commonsDirectImageUrl(image);
            if (commonsImage != null) return commonsImage;
            String validThumbnail = normalizeWikimediaThumbnail(image);
            return validThumbnail == null ? image : validThumbnail;
        }
        return null;
    }

    private static String commonsDirectImageUrl(String imageUrl) {
        try {
            URI uri = URI.create(imageUrl);
            if (!"commons.wikimedia.org".equalsIgnoreCase(uri.getHost())) return null;
            String path = uri.getPath();
            String filePrefix = "/wiki/File:";
            if (path == null || !path.regionMatches(
                    true, 0, filePrefix, 0, filePrefix.length())) {
                return null;
            }
            String filename = path.substring(filePrefix.length());
            if (filename.isBlank()) return null;
            String encodedFilename = URLEncoder.encode(
                    filename, StandardCharsets.UTF_8).replace("+", "%20");
            return "https://commons.wikimedia.org/wiki/Special:FilePath/"
                    + encodedFilename;
        } catch (IllegalArgumentException ignored) {
            return null;
        }
    }

    private static String normalizeWikimediaThumbnail(String imageUrl) {
        try {
            URI uri = URI.create(imageUrl);
            if (!"upload.wikimedia.org".equalsIgnoreCase(uri.getHost())) return null;
            String path = uri.getRawPath();
            if (path == null || !path.contains("/thumb/")) return null;
            int lastSlash = path.lastIndexOf('/');
            if (lastSlash < 0) return null;
            String thumbnail = path.substring(lastSlash + 1);
            if (!thumbnail.startsWith("400px-")) return null;
            String normalizedPath = path.substring(0, lastSlash + 1)
                    + "500px-" + thumbnail.substring("400px-".length());
            return uri.getScheme() + "://" + uri.getRawAuthority() + normalizedPath
                    + (uri.getRawQuery() == null ? "" : "?" + uri.getRawQuery());
        } catch (IllegalArgumentException ignored) {
            return null;
        }
    }

    private List<Map<String, Object>> enrichAndFilter(
            List<Map<?, ?>> rawCandidates,
            GeoPoint center,
            String language,
            String category,
            Double south,
            Double west,
            Double north,
            Double east) {
        List<Candidate> eligible = rawCandidates.stream()
                .map(raw -> candidateFrom(raw, center))
                .filter(candidate -> preDetailRejection(
                        candidate, center, south, west, north, east) == null)
                .sorted(candidateComparator(center))
                .limit(DETAILS_LIMIT)
                .toList();
        List<CompletableFuture<DetailResult>> futures = eligible.stream()
                .map(candidate -> CompletableFuture.supplyAsync(
                        () -> fetchDetailResult(candidate, language), DETAIL_EXECUTOR))
                .toList();
        CompletableFuture.allOf(futures.toArray(CompletableFuture[]::new)).join();
        List<Map<String, Object>> places = new ArrayList<>();
        for (CompletableFuture<DetailResult> future : futures) {
            DetailResult result = future.join();
            if (result.details() == null) continue;
            Candidate candidate = enrich(result.candidate(), result.details());
            Validation validation = isRealLandmark(
                    candidate, center, south, west, north, east);
            if (validation.accepted()
                    && categoryMatches(category, validation.category())) {
                places.add(toPlace(candidate, center, language));
            }
        }
        return places.stream().sorted(placeComparator(center))
                .limit(RESULT_LIMIT).toList();
    }

    private Candidate candidateFrom(Map<?, ?> raw, GeoPoint fallback) {
        Map<?, ?> point = asMap(raw.get("point"));
        return new Candidate(
                clean(text(raw.get("xid"))),
                clean(text(raw.get("name"))),
                clean(text(raw.get("kinds"))),
                firstNumber(number(point.get("lat")), number(raw.get("lat"))),
                firstNumber(number(point.get("lon")), number(raw.get("lon"))),
                text(raw.get("rate")),
                text(raw.get("wikidata")),
                text(raw.get("wikipedia")),
                text(raw.get("image")),
                text(asMap(raw.get("preview")).get("source")),
                text(asMap(raw.get("wikipedia_extracts")).get("text")),
                text(asMap(raw.get("info")).get("descr")),
                raw);
    }

    private Candidate enrich(Candidate candidate, Map<String, Object> details) {
        Map<?, ?> point = asMap(details.get("point"));
        Map<?, ?> address = asMap(details.get("address"));
        Map<?, ?> preview = asMap(details.get("preview"));
        Map<?, ?> extracts = asMap(details.get("wikipedia_extracts"));
        Map<?, ?> info = asMap(details.get("info"));
        return new Candidate(
                nonBlank(text(details.get("xid")), candidate.xid()),
                nonBlank(text(details.get("name")), candidate.name()),
                nonBlank(text(details.get("kinds")), candidate.kinds()),
                firstNumber(number(point.get("lat")), candidate.latitude()),
                firstNumber(number(point.get("lon")), candidate.longitude()),
                nonBlank(text(details.get("rate")), candidate.rate()),
                nonBlank(text(details.get("wikidata")), candidate.wikidataId()),
                nonBlank(text(details.get("wikipedia")), candidate.wikipediaUrl()),
                nonBlank(text(details.get("image")), candidate.imageUrl()),
                nonBlank(text(preview.get("source")), candidate.previewUrl()),
                nonBlank(text(extracts.get("text")), candidate.description()),
                nonBlank(text(info.get("descr")), candidate.infoDescription()),
                mergeDetails(candidate.raw(), details, address));
    }

    private static Map<String, Object> mergeDetails(
            Map<?, ?> raw, Map<String, Object> details, Map<?, ?> address) {
        Map<String, Object> merged = stringMap(raw);
        merged.putAll(details);
        merged.put("_address_city", firstNonBlank(
                text(address.get("city")), text(address.get("town")),
                text(address.get("village")), text(address.get("municipality"))));
        merged.put("_address_country", text(address.get("country")));
        return merged;
    }

    private Map<String, Object> toPlace(
            Candidate item, GeoPoint center, String language) {
        Map<?, ?> raw = item.raw();
        Map<String, Object> place = new LinkedHashMap<>();
        String city = firstNonBlank(
                text(raw.get("_address_city")),
                text(raw.get("city")),
                center == null ? null : center.city(),
                "");
        String country = firstNonBlank(
                text(raw.get("_address_country")),
                text(raw.get("country")),
                center == null ? null : center.country(),
                "");
        String wikipediaImage = text(raw.get("_wikipedia_image_url"));
        String image = displayImageUrl(
                item.previewUrl(), wikipediaImage, item.imageUrl());
        String description = firstNonBlank(item.description(), item.infoDescription(), "");
        place.put("id", item.xid());
        place.put("xid", item.xid());
        place.put("name", item.name());
        place.put("name_en", "en".equals(language) ? item.name() : null);
        place.put("name_ar", null);
        place.put("city", city);
        place.put("country", country);
        place.put("location", String.join(", ",
                List.of(city, country).stream().filter(value -> !value.isBlank()).toList()));
        place.put("description", description);
        place.put("category", categoryForKinds(item.kinds()));
        place.put("category_tag", categoryForKinds(item.kinds()));
        place.put("rating", popularity(item.rate()));
        place.put("review_count", 0);
        place.put("visit_count", 0);
        place.put("country_visit_count", 0);
        place.put("latitude", item.latitude());
        place.put("longitude", item.longitude());
        place.put("image_url", image);
        place.put("opening_hours", text(raw.get("opening_hours")));
        place.put("best_time_to_visit", null);
        place.put("tags", splitKinds(item.kinds()));
        place.put("source_provider", "opentripmap");
        place.put("response_language", language);
        place.put("source_attribution", sourceAttribution(raw));
        place.put("image_attribution", wikipediaImage == null
                ? "OpenTripMap; follow the linked source attribution."
                : "Wikipedia article image; check the linked source for author and license.");
        place.put("source_url", text(raw.get("otm")));
        place.put("wikipedia_url", wikipediaUrl(item.wikipediaUrl(), language));
        place.put("wikidata_id", item.wikidataId());
        place.put("distance_km", center == null ? null
                : distanceMeters(center.latitude(), center.longitude(),
                        item.latitude(), item.longitude()) / 1000.0);
        place.put("entry_fee", null);
        return place;
    }

    private static String sourceAttribution(Map<?, ?> raw) {
        Map<?, ?> sources = asMap(raw.get("sources"));
        List<String> attributes = safeList(sources.get("attributes")).stream()
                .map(OpenTripMapAttractionService::text)
                .filter(value -> value != null && !value.isBlank())
                .map(value -> switch (value.toLowerCase(Locale.ROOT)) {
                    case "osm" -> "OpenStreetMap contributors (ODbL)";
                    case "wikidata" -> "Wikidata (CC0)";
                    default -> value;
                })
                .distinct()
                .toList();
        return attributes.isEmpty()
                ? "OpenTripMap · verify the linked source for image licensing."
                : "OpenTripMap · " + String.join(" · ", attributes);
    }

    private static String preDetailRejection(
            Candidate candidate,
            GeoPoint center,
            Double south,
            Double west,
            Double north,
            Double east) {
        if (candidate == null) return "type";
        if (isHistoricalEvent(candidate)) return "event";
        if (isBusiness(candidate)) return "business";
        if (categoryForKinds(candidate.kinds()) == null) return "type";
        String name = clean(candidate.name());
        if (candidate.xid() == null || !XID.matcher(candidate.xid()).matches()
                || name == null || CODE_OR_NUMBER.matcher(name).matches()
                || SHORT_CODE_NAME.matcher(name).matches()
                || GENERIC_NAMES.contains(normalize(name))) {
            return "no_identity";
        }
        if (!validCoordinates(candidate.latitude(), candidate.longitude())
                || !insideBounds(candidate.latitude(), candidate.longitude(),
                        south, west, north, east)
                || (!validBounds(south, west, north, east) && center != null && distanceMeters(
                        center.latitude(), center.longitude(),
                        candidate.latitude(), candidate.longitude()) > SEARCH_RADIUS_METERS)) {
            return "location";
        }
        return null;
    }

    private static boolean isBusiness(Candidate candidate) {
        Set<String> kinds = new LinkedHashSet<>(splitKinds(candidate.kinds()));
        if (kinds.stream().anyMatch(BUSINESS_KINDS::contains)) return true;
        String name = normalize(candidate.name());
        return name.matches(".*\\b(shop|store|market|restaurant|cafe|café|hotel|hostel|"
                + "bank|pharmacy|clinic|school|gas station|parking|gym|salon|bar|club|"
                + "office|company|companies|business|service|apartment|residential|"
                + "bus stop|street|neighborhood|district)\\b.*");
    }

    private static boolean isHistoricalEvent(Candidate candidate) {
        Set<String> kinds = new LinkedHashSet<>(splitKinds(candidate.kinds()));
        return kinds.contains("battlefields")
                && normalize(candidate.name()).matches("^(the )?battle of\\b.*");
    }

    private static String categoryForKinds(String kindsValue) {
        Set<String> kinds = new LinkedHashSet<>(splitKinds(kindsValue));
        if (kinds.stream().anyMatch(kind ->
                kind.equals("museums") || kind.endsWith("_museums"))) return "museum";
        if (kinds.stream().anyMatch(kind ->
                kind.equals("beaches") || kind.endsWith("_beaches"))) return "beach";
        if (kinds.contains("gardens_and_parks")) return "park";
        if (kinds.stream().anyMatch(kind -> Set.of(
                "natural", "natural_springs", "mountain_peaks", "caves",
                "waterfalls", "other_lakes", "nature_reserves", "national_parks",
                "natural_monuments").contains(kind))) return "natural";
        if (kinds.contains("architecture") || kinds.contains("historic_architecture")) {
            return "architecture";
        }
        if (kinds.stream().anyMatch(kind -> Set.of(
                "historic", "historical_places", "historic_districts",
                "historic_settlements", "fortifications", "castles", "hillforts",
                "fortified_towers", "other_fortifications",
                "monuments_and_memorials", "monuments", "archaeology",
                "cave_paintings", "other_archaeological_sites", "historic_object")
                .contains(kind))) return "historical";
        return null;
    }

    private static String kindsForCategory(String category) {
        if (category == null || category.isBlank() || "all".equals(category)) {
            return ALL_KINDS;
        }
        return switch (category) {
            case "historical" -> String.join(",",
                    "historic", "historical_places", "historic_districts",
                    "historic_settlements", "fortifications", "castles",
                    "hillforts", "fortified_towers", "other_fortifications",
                    "monuments_and_memorials", "monuments", "archaeology",
                    "cave_paintings", "other_archaeological_sites", "historic_object");
            case "natural" -> String.join(",",
                    "natural", "natural_springs", "mountain_peaks", "caves",
                    "waterfalls", "other_lakes", "nature_reserves",
                    "national_parks", "natural_monuments");
            case "architecture" -> "architecture,historic_architecture";
            case "museum" -> "museums";
            case "park" -> "gardens_and_parks";
            case "beach" -> "beaches";
            case "landmark", "cultural" -> String.join(",",
                    "historic", "historical_places", "monuments_and_memorials",
                    "monuments", "museums", "architecture", "historic_architecture");
            default -> ALL_KINDS;
        };
    }

    private static List<Map<String, Object>> deduplicate(
            List<Map<String, Object>> places,
            Map<String, Integer> droppedCounts,
            List<RejectedItem> dropped) {
        List<Map<String, Object>> unique = new ArrayList<>();
        for (Map<String, Object> candidate : places) {
            String name = duplicateNameKey(
                    text(candidate.get("name")), safeList(candidate.get("tags")));
            double lat = number(candidate.get("latitude")) == null
                    ? 0 : number(candidate.get("latitude"));
            double lon = number(candidate.get("longitude")) == null
                    ? 0 : number(candidate.get("longitude"));
            boolean duplicate = unique.stream().anyMatch(existing -> {
                if (sharesProviderIdentity(existing, candidate)) return true;
                Double existingLatitude = number(existing.get("latitude"));
                Double existingLongitude = number(existing.get("longitude"));
                String existingName = duplicateNameKey(
                        text(existing.get("name")), safeList(existing.get("tags")));
                return existingName.equals(name)
                        && existingLatitude != null && existingLongitude != null
                        && distanceMeters(lat, lon,
                                existingLatitude, existingLongitude) <= 100;
            });
            if (duplicate) {
                LOG.debug("Dropped OpenTripMap place xid={} name={} reason=duplicate",
                        candidate.get("id"), candidate.get("name"));
                addCount(droppedCounts, "duplicate", 1);
                addDroppedExample(dropped, new RejectedItem(
                        text(candidate.get("name")), text(candidate.get("id")),
                        text(candidate.get("category")), "opentripmap", "duplicate"));
            } else {
                unique.add(candidate);
            }
        }
        return unique;
    }

    private static boolean sharesProviderIdentity(
            Map<String, Object> left, Map<String, Object> right) {
        String leftWikidataId = clean(text(left.get("wikidata_id")));
        String rightWikidataId = clean(text(right.get("wikidata_id")));
        if (leftWikidataId != null
                && rightWikidataId != null
                && leftWikidataId.equalsIgnoreCase(rightWikidataId)) {
            return true;
        }

        String leftWikipediaPage = wikipediaPageKey(left.get("wikipedia_url"));
        String rightWikipediaPage = wikipediaPageKey(right.get("wikipedia_url"));
        return leftWikipediaPage != null
                && rightWikipediaPage != null
                && leftWikipediaPage.equals(rightWikipediaPage);
    }

    private static String wikipediaPageKey(Object rawValue) {
        String value = clean(text(rawValue));
        if (value == null) return null;
        try {
            URI uri = URI.create(value);
            String host = uri.getHost();
            String path = uri.getPath();
            if (host == null || path == null) return null;
            String normalizedHost = host.toLowerCase(Locale.ROOT)
                    .replaceFirst("^www\\.", "");
            if (!normalizedHost.equals("wikipedia.org")
                    && !normalizedHost.endsWith(".wikipedia.org")) {
                return null;
            }
            int articleStart = path.toLowerCase(Locale.ROOT).indexOf("/wiki/");
            if (articleStart < 0) return null;
            String pageName = duplicateNameKey(
                    path.substring(articleStart + "/wiki/".length()), List.of());
            if (pageName.isBlank()) return null;
            return normalizedHost + "|" + pageName;
        } catch (IllegalArgumentException ignored) {
            return null;
        }
    }

    private static String duplicateNameKey(String name, List<?> tags) {
        String key = Normalizer.normalize(normalize(name), Normalizer.Form.NFD)
                .replaceAll("\\p{M}+", "")
                .replaceAll("[^\\p{L}\\p{N}]+", " ")
                .trim();
        boolean bridge = tags.stream()
                .map(OpenTripMapAttractionService::text)
                .anyMatch("bridges"::equals);
        return bridge ? key.replaceFirst("\\s+bridge$", "") : key;
    }

    private static List<Map<String, Object>> deduplicateSuggestions(
            List<Map<String, Object>> suggestions) {
        Map<String, Map<String, Object>> unique = new LinkedHashMap<>();
        for (Map<String, Object> suggestion : suggestions) {
            String key = normalize(text(suggestion.get("label"))) + "|"
                    + coordinateKey(number(suggestion.get("latitude"))) + "|"
                    + coordinateKey(number(suggestion.get("longitude")));
            unique.putIfAbsent(key, suggestion);
        }
        return List.copyOf(unique.values());
    }

    private static void reject(
            Candidate candidate,
            String reason,
            Map<String, Integer> counts,
            List<RejectedItem> dropped) {
        LOG.debug("Dropped OpenTripMap place xid={} name={} reason={}",
                candidate == null ? null : candidate.xid(),
                candidate == null ? null : candidate.name(),
                reason);
        addCount(counts, reason, 1);
        addDroppedExample(dropped, new RejectedItem(
                candidate == null ? null : candidate.name(),
                candidate == null ? null : candidate.xid(),
                candidate == null ? null : categoryForKinds(candidate.kinds()),
                "opentripmap", reason));
    }

    private static void addDroppedExample(
            List<RejectedItem> items, RejectedItem item) {
        if (items.size() < DROPPED_EXAMPLE_LIMIT) items.add(item);
    }

    private static void addCount(Map<String, Integer> counts, String reason, int amount) {
        counts.merge(reason, amount, Integer::sum);
    }

    private static Comparator<Candidate> candidateComparator(GeoPoint center) {
        return Comparator.comparingInt((Candidate item) -> popularity(item.rate()))
                .reversed()
                .thenComparing(item -> clean(item.imageUrl()) == null
                        && clean(item.previewUrl()) == null)
                .thenComparingDouble(item -> center == null ? 0
                        : distanceMeters(center.latitude(), center.longitude(),
                                item.latitude(), item.longitude()));
    }

    private static Comparator<Map<String, Object>> placeComparator(GeoPoint center) {
        return Comparator.<Map<String, Object>>comparingInt(
                        item -> popularity(text(item.get("rating"))))
                .reversed()
                .thenComparing(item -> clean(text(item.get("image_url"))) == null)
                .thenComparingDouble(item -> center == null ? 0
                        : distanceMeters(center.latitude(), center.longitude(),
                                number(item.get("latitude")), number(item.get("longitude"))));
    }

    private static int popularity(String rate) {
        if (rate == null) return 0;
        String value = rate.trim().toLowerCase(Locale.ROOT);
        if (value.endsWith("h")) value = value.substring(0, value.length() - 1);
        try {
            return Math.max(0, Math.min(3, Integer.parseInt(value)));
        } catch (NumberFormatException ignored) {
            return 0;
        }
    }

    private static GeoPoint explicitPoint(
            Double latitude,
            Double longitude,
            String city,
            String country,
            Double south,
            Double west,
            Double north,
            Double east) {
        if (validCoordinates(latitude, longitude)) {
            return new GeoPoint(latitude, longitude, city, country,
                    south, west, north, east);
        }
        if (validBounds(south, west, north, east)) {
            return new GeoPoint((south + north) / 2.0, (west + east) / 2.0,
                    city, country, south, west, north, east);
        }
        return null;
    }

    private static GeoPoint pointFromDetails(
            Map<String, Object> details, String city, String country) {
        Map<?, ?> point = asMap(details.get("point"));
        Double latitude = number(point.get("lat"));
        Double longitude = number(point.get("lon"));
        if (!validCoordinates(latitude, longitude)) return null;
        return new GeoPoint(latitude, longitude, city, country,
                null, null, null, null);
    }

    private static boolean insideBounds(
            double latitude, double longitude,
            Double south, Double west, Double north, Double east) {
        return !validBounds(south, west, north, east)
                || (latitude >= south && latitude <= north
                    && longitude >= west && longitude <= east);
    }

    private static boolean validBounds(
            Double south, Double west, Double north, Double east) {
        return south != null && west != null && north != null && east != null
                && Double.isFinite(south) && Double.isFinite(west)
                && Double.isFinite(north) && Double.isFinite(east)
                && south >= -90 && north <= 90 && west >= -180 && east <= 180
                && south < north && west < east;
    }

    private static boolean validCoordinates(Double latitude, Double longitude) {
        return latitude != null && longitude != null
                && Double.isFinite(latitude) && Double.isFinite(longitude)
                && latitude >= -90 && latitude <= 90
                && longitude >= -180 && longitude <= 180;
    }

    private static double distanceMeters(
            double latitude1, double longitude1,
            double latitude2, double longitude2) {
        double lat1 = Math.toRadians(latitude1);
        double lat2 = Math.toRadians(latitude2);
        double deltaLat = lat2 - lat1;
        double deltaLon = Math.toRadians(longitude2 - longitude1);
        double a = Math.pow(Math.sin(deltaLat / 2), 2)
                + Math.cos(lat1) * Math.cos(lat2)
                        * Math.pow(Math.sin(deltaLon / 2), 2);
        return 6_371_000 * 2 * Math.asin(Math.sqrt(Math.min(1, a)));
    }

    private static Candidate candidateFrom(
            Candidate candidate, Map<String, Object> details) {
        Map<?, ?> point = asMap(details.get("point"));
        Map<?, ?> preview = asMap(details.get("preview"));
        Map<?, ?> extracts = asMap(details.get("wikipedia_extracts"));
        Map<?, ?> info = asMap(details.get("info"));
        Map<?, ?> address = asMap(details.get("address"));
        return new Candidate(
                nonBlank(text(details.get("xid")), candidate.xid()),
                nonBlank(text(details.get("name")), candidate.name()),
                nonBlank(text(details.get("kinds")), candidate.kinds()),
                firstNumber(number(point.get("lat")), candidate.latitude()),
                firstNumber(number(point.get("lon")), candidate.longitude()),
                nonBlank(text(details.get("rate")), candidate.rate()),
                nonBlank(text(details.get("wikidata")), candidate.wikidataId()),
                nonBlank(text(details.get("wikipedia")), candidate.wikipediaUrl()),
                nonBlank(text(details.get("image")), candidate.imageUrl()),
                nonBlank(text(preview.get("source")), candidate.previewUrl()),
                nonBlank(text(extracts.get("text")), candidate.description()),
                nonBlank(text(info.get("descr")), candidate.infoDescription()),
                mergeDetails(candidate.raw(), details, address));
    }

    private <T> T retry(Supplier<T> request) {
        RestClientException lastFailure = null;
        for (int attempt = 0; attempt < 3; attempt++) {
            waitForRequestSlot();
            try {
                return request.get();
            } catch (RestClientResponseException exception) {
                lastFailure = exception;
                int status = exception.getStatusCode().value();
                if (status < 500 && status != 429) throw exception;
            } catch (ResourceAccessException exception) {
                lastFailure = exception;
            } catch (RestClientException exception) {
                lastFailure = exception;
                if (attempt == 2) break;
            }
            if (attempt < 2) sleepBackoff(attempt);
        }
        throw lastFailure == null
                ? new RestClientException("OpenTripMap request failed")
                : lastFailure;
    }

    private void waitForRequestSlot() {
        synchronized (requestGate) {
            long now = System.nanoTime();
            long delay = nextRequestNanos - now;
            if (delay > 0) {
                try {
                    TimeUnit.NANOSECONDS.sleep(delay);
                } catch (InterruptedException exception) {
                    Thread.currentThread().interrupt();
                    throw new RestClientException(
                            "OpenTripMap request interrupted", exception);
                }
            }
            nextRequestNanos = System.nanoTime() + REQUEST_SPACING_NANOS;
        }
    }

    private static void sleepBackoff(int attempt) {
        try {
            Thread.sleep(200L << attempt);
        } catch (InterruptedException exception) {
            Thread.currentThread().interrupt();
            throw new RestClientException("OpenTripMap retry interrupted", exception);
        }
    }

    private static String providerFailure(RestClientException exception) {
        if (exception instanceof RestClientResponseException response) {
            return "HTTP " + response.getStatusCode().value();
        }
        return "network or timeout error";
    }

    private static ResponseStatusException unavailable() {
        return new ResponseStatusException(
                HttpStatus.SERVICE_UNAVAILABLE,
                "OpenTripMap is temporarily unavailable. Please try again.");
    }

    private static String apiLanguage(String language) {
        // OpenTripMap officially documents only English and Russian.
        return language != null && language.toLowerCase(Locale.ROOT).startsWith("ru")
                ? "ru" : "en";
    }

    private static String normalizeCategory(String value) {
        if (value == null || value.isBlank() || "all".equalsIgnoreCase(value.trim())) {
            return null;
        }
        String category = value.trim().toLowerCase(Locale.ROOT)
                .replace("&", "and").replaceAll("\\s+", " ");
        return switch (category) {
            case "history" -> "historical";
            case "nature" -> "natural";
            case "museums" -> "museum";
            case "gardens", "gardens and parks", "parks" -> "park";
            case "family and culture", "culture" -> "cultural";
            case "historical", "natural", "architecture", "museum", "park",
                    "beach", "landmark", "cultural" -> category;
            default -> "unsupported";
        };
    }

    private static boolean categoryMatches(String requested, String actual) {
        if (requested == null || "landmark".equals(requested)) return true;
        if ("cultural".equals(requested)) {
            return Set.of("historical", "architecture", "museum").contains(actual);
        }
        return requested.equals(actual);
    }

    private static String displayCountry(String countryCode, String fallback) {
        String code = isoCountry(countryCode);
        if (code == null) return nonBlank(fallback, "");
        try {
            String display = new Locale.Builder().setRegion(code).build()
                    .getDisplayCountry(Locale.ENGLISH);
            return display == null || display.isBlank()
                    ? nonBlank(fallback, code) : display;
        } catch (RuntimeException ignored) {
            return nonBlank(fallback, code);
        }
    }

    private static String isoCountry(String value) {
        String country = clean(value);
        if (country == null) return null;
        if (country.matches("(?i)^[a-z]{2}$")) {
            String code = country.toUpperCase(Locale.ROOT);
            return ISO_COUNTRY_CODES.contains(code) ? code : null;
        }
        return COUNTRY_NAME_TO_CODE.get(normalizeCountryName(country));
    }

    private static Map<String, String> buildCountryNameIndex() {
        Map<String, Set<String>> candidates = new LinkedHashMap<>();
        Locale[] languages = Locale.getAvailableLocales();
        for (String code : Locale.getISOCountries()) {
            Locale country = new Locale.Builder().setRegion(code).build();
            for (Locale language : languages) {
                String displayName = country.getDisplayCountry(language);
                String normalized = normalizeCountryName(displayName);
                if (!normalized.isEmpty()) {
                    candidates.computeIfAbsent(normalized, ignored -> new LinkedHashSet<>())
                            .add(code);
                }
            }
        }
        Map<String, String> names = new LinkedHashMap<>();
        candidates.forEach((name, codes) -> {
            if (codes.size() == 1) names.put(name, codes.iterator().next());
        });
        Map<String, String> aliases = Map.ofEntries(
                Map.entry("usa", "US"),
                Map.entry("united states of america", "US"),
                Map.entry("uk", "GB"),
                Map.entry("great britain", "GB"),
                Map.entry("turkey", "TR"),
                Map.entry("turkiye", "TR"),
                Map.entry("russia", "RU"),
                Map.entry("south korea", "KR"),
                Map.entry("north korea", "KP"),
                Map.entry("iran", "IR"),
                Map.entry("syria", "SY"),
                Map.entry("myanmar", "MM"),
                Map.entry("czech republic", "CZ"),
                Map.entry("ivory coast", "CI"),
                Map.entry("vietnam", "VN"));
        names.putAll(aliases);
        return Map.copyOf(names);
    }

    private static String normalizeCountryName(String value) {
        if (value == null) return "";
        return Normalizer.normalize(value, Normalizer.Form.NFD)
                .replaceAll("\\p{M}", "")
                .toLowerCase(Locale.ROOT)
                .replaceAll("[^\\p{L}\\p{N}]+", " ")
                .trim()
                .replaceAll("\\s+", " ");
    }

    private static List<String> splitKinds(String kinds) {
        if (kinds == null || kinds.isBlank()) return List.of();
        return java.util.Arrays.stream(kinds.split(","))
                .map(value -> value.trim().toLowerCase(Locale.ROOT))
                .filter(value -> !value.isBlank())
                .distinct()
                .toList();
    }

    private static List<?> safeList(Object value) {
        return value instanceof List<?> list ? list : List.of();
    }

    private static Map<?, ?> asMap(Object value) {
        return value instanceof Map<?, ?> map ? map : Map.of();
    }

    private static Map<String, Object> stringMap(Map<?, ?> value) {
        Map<String, Object> result = new LinkedHashMap<>();
        value.forEach((key, item) -> {
            if (key != null) result.put(String.valueOf(key), item);
        });
        return result;
    }

    private static Double number(Object value) {
        if (value instanceof Number number) return number.doubleValue();
        if (value instanceof String string) {
            try {
                return Double.parseDouble(string);
            } catch (NumberFormatException ignored) {
                return null;
            }
        }
        return null;
    }

    private static Double firstNumber(Double... values) {
        for (Double value : values) {
            if (value != null && Double.isFinite(value)) return value;
        }
        return null;
    }

    private static String text(Object value) {
        return value == null ? null : String.valueOf(value).trim();
    }

    private static String clean(String value) {
        String cleaned = value == null ? null : value.trim();
        return cleaned == null || cleaned.isEmpty() ? null : cleaned;
    }

    private static String nonBlank(String value, String fallback) {
        String cleaned = clean(value);
        return cleaned == null ? fallback : cleaned;
    }

    private static String firstNonBlank(String... values) {
        for (String value : values) {
            if (value != null && !value.isBlank()) return value.trim();
        }
        return "";
    }

    private static String normalize(String value) {
        return value == null ? "" : value.trim().toLowerCase(Locale.ROOT)
                .replaceAll("\\s+", " ");
    }

    private static String coordinateKey(Double value) {
        return value == null ? "" : String.format(Locale.ROOT, "%.5f", value);
    }

    public record Candidate(
            String xid,
            String name,
            String kinds,
            Double latitude,
            Double longitude,
            String rate,
            String wikidataId,
            String wikipediaUrl,
            String imageUrl,
            String previewUrl,
            String description,
            String infoDescription,
            Map<?, ?> raw) {}

    public record GeoPoint(
            double latitude,
            double longitude,
            String city,
            String country,
            Double south,
            Double west,
            Double north,
            Double east) {}

    public record Validation(boolean accepted, String category, String reason) {
        static Validation accept(String category) {
            return new Validation(true, category, null);
        }

        static Validation reject(String reason) {
            return new Validation(false, null, reason);
        }
    }

    public record SearchOutcome(
            List<Map<String, Object>> places,
            Boolean cityFound,
            int candidateCount,
            Map<String, Integer> droppedByReason,
            List<RejectedItem> droppedItems,
            List<String> warnings,
            int totalCount) {}

    public record RejectedItem(
            String name, String id, String category, String source, String reason) {}

    public record DestinationSuggestion(
            String name, String country, double latitude, double longitude) {}

    private record Geoname(
            String name, String country, double latitude, double longitude) {}

    private record DetailResult(
            Candidate candidate, Map<String, Object> details) {}

    private record TimedEntry<T>(T value, Instant expiresAt) {}
}
