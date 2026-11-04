package com.zentrip.api;

import org.springframework.http.HttpStatus;
import org.springframework.web.server.ResponseStatusException;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;
import java.util.concurrent.ArrayBlockingQueue;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.CompletionException;
import java.util.concurrent.Executor;
import java.util.concurrent.ThreadPoolExecutor;
import java.util.concurrent.TimeUnit;
import java.util.function.Supplier;

/**
 * Normalizes independently sourced search results without changing the legacy
 * response keys or the amount/currency used by existing booking flows.
 */
public class UnifiedInventoryService {
    private static final Set<String> DISPLAY_CURRENCIES = Set.of("USD", "EUR", "GBP");
    private static final Executor PROVIDER_EXECUTOR = new ThreadPoolExecutor(
            2,
            4,
            30,
            TimeUnit.SECONDS,
            new ArrayBlockingQueue<>(32),
            runnable -> {
                Thread thread = new Thread(runnable, "zentrip-provider-search");
                thread.setDaemon(true);
                return thread;
            },
            new ThreadPoolExecutor.CallerRunsPolicy());

    private final ExchangeRateService exchangeRateService;

    public UnifiedInventoryService(ExchangeRateService exchangeRateService) {
        this.exchangeRateService = exchangeRateService;
    }

    public record SourceOutcome(
            List<Map<String, Object>> items,
            List<String> warnings,
            String status,
            Map<String, Object> diagnostics) {
        public SourceOutcome(
                List<Map<String, Object>> items,
                List<String> warnings) {
            this(items, warnings,
                    items == null || items.isEmpty() ? "empty" : "success",
                    Map.of());
        }

        public SourceOutcome {
            items = items == null
                    ? List.of()
                    : items.stream().filter(item -> item != null).toList();
            warnings = warnings == null
                    ? List.of()
                    : warnings.stream()
                            .filter(warning -> warning != null && !warning.isBlank())
                            .toList();
            status = status == null || status.isBlank() ? "unknown" : status;
            diagnostics = diagnostics == null ? Map.of() : Map.copyOf(diagnostics);
        }

        public static SourceOutcome of(List<Map<String, Object>> items) {
            return new SourceOutcome(items, List.of());
        }
    }

    public record ProviderSearch(
            String source,
            String warning,
            Supplier<SourceOutcome> search) {
        public ProviderSearch {
            source = source == null ? "" : source.trim().toLowerCase(Locale.ROOT);
            warning = warning == null || warning.isBlank()
                    ? "External inventory is temporarily unavailable."
                    : warning;
            if (source.isBlank() || source.equals("partner") || search == null) {
                throw new IllegalArgumentException("A provider source and search are required");
            }
        }
    }

    public record SearchOutcome(
            List<Map<String, Object>> items,
            List<String> warnings,
            Map<String, Long> sources,
            Map<String, String> providerStatuses,
            Map<String, Map<String, Object>> providerDiagnostics) {
        public SearchOutcome(
                List<Map<String, Object>> items,
                List<String> warnings,
                Map<String, Long> sources) {
            this(items, warnings, sources, Map.of(), Map.of());
        }

        public SearchOutcome {
            items = items == null
                    ? List.of()
                    : items.stream().filter(item -> item != null).toList();
            warnings = warnings == null
                    ? List.of()
                    : warnings.stream()
                            .filter(warning -> warning != null && !warning.isBlank())
                            .toList();
            sources = sources == null ? Map.of() : Map.copyOf(sources);
            providerStatuses = providerStatuses == null
                    ? Map.of()
                    : Map.copyOf(providerStatuses);
            if (providerDiagnostics == null) {
                providerDiagnostics = Map.of();
            } else {
                Map<String, Map<String, Object>> copy = new LinkedHashMap<>();
                providerDiagnostics.forEach((source, values) ->
                        copy.put(source, values == null ? Map.of() : Map.copyOf(values)));
                providerDiagnostics = Map.copyOf(copy);
            }
        }
    }

    public record HotelFilters(
            String currency,
            BigDecimal priceMin,
            BigDecimal priceMax,
            BigDecimal ratingMin,
            String amenities,
            String roomType,
            String preferences) {}

    public record FilterOutcome(
            List<Map<String, Object>> hotels,
            List<String> warnings) {}

    /**
     * The partner supplier runs on the request thread so database/RLS transaction
     * context is retained. Only the external provider call runs on the bounded
     * executor.
     */
    public SearchOutcome merge(
            String type,
            Supplier<List<Map<String, Object>>> partnerSearch,
            Supplier<SourceOutcome> providerSearch,
            String partnerWarning,
            String providerWarning) {
        return merge(
                type,
                partnerSearch,
                List.of(new ProviderSearch("duffel", providerWarning, providerSearch)),
                partnerWarning);
    }

    public SearchOutcome merge(
            String type,
            Supplier<List<Map<String, Object>>> partnerSearch,
            List<ProviderSearch> providerSearches,
            String partnerWarning) {
        List<ProviderSearch> providers = providerSearches == null
                ? List.of()
                : providerSearches.stream().filter(provider -> provider != null).toList();
        List<CompletableFuture<SourceOutcome>> providerFutures = providers.stream()
                .map(provider -> CompletableFuture.supplyAsync(
                        provider.search(), PROVIDER_EXECUTOR))
                .toList();

        List<String> warnings = new ArrayList<>();
        List<Map<String, Object>> results = new ArrayList<>();
        Map<String, String> providerStatuses = new LinkedHashMap<>();
        Map<String, Map<String, Object>> providerDiagnostics = new LinkedHashMap<>();
        try {
            List<Map<String, Object>> partnerItems = partnerSearch.get();
            if (partnerItems != null) {
                partnerItems.stream()
                        .filter(item -> item != null)
                        .map(item -> normalize(item, type))
                        .forEach(results::add);
            }
        } catch (RuntimeException exception) {
            warnings.add(partnerWarning);
        }

        for (int index = 0; index < providerFutures.size(); index++) {
            SourceOutcome providerItems;
            try {
                providerItems = providerFutures.get(index).join();
            } catch (CompletionException exception) {
                warnings.add(providers.get(index).warning());
                providerStatuses.put(providers.get(index).source(), "unavailable");
                providerDiagnostics.put(
                        providers.get(index).source(),
                        Map.of("error_type", exception.getCause() == null
                                ? exception.getClass().getSimpleName()
                                : exception.getCause().getClass().getSimpleName()));
                continue;
            }
            if (providerItems == null) {
                warnings.add(providers.get(index).warning());
                providerStatuses.put(providers.get(index).source(), "unavailable");
                providerDiagnostics.put(providers.get(index).source(), Map.of());
                continue;
            }
            providerStatuses.put(providers.get(index).source(), providerItems.status());
            providerDiagnostics.put(
                    providers.get(index).source(), providerItems.diagnostics());
            providerItems.items().stream()
                    .filter(item -> item != null)
                    .map(item -> normalize(item, type))
                    .forEach(results::add);
            warnings.addAll(providerItems.warnings());
        }

        long partnerCount = results.stream()
                .filter(item -> "partner".equals(item.get("source")))
                .count();
        Map<String, Long> sourceCounts = new LinkedHashMap<>();
        sourceCounts.put("partner", partnerCount);
        for (ProviderSearch provider : providers) {
            sourceCounts.put(
                    provider.source(),
                    results.stream()
                            .filter(item -> provider.source().equals(item.get("source")))
                            .count());
        }
        return new SearchOutcome(
                List.copyOf(results),
                List.copyOf(new LinkedHashSet<>(warnings)),
                sourceCounts,
                providerStatuses,
                providerDiagnostics);
    }

    public FilterOutcome filterHotels(
            List<Map<String, Object>> hotels,
            HotelFilters requestedFilters) {
        HotelFilters filters = validateFilters(requestedFilters);
        List<Map<String, Object>> candidates =
                hotels == null ? List.of() : hotels;
        List<String> warnings = new ArrayList<>();
        Map<String, BigDecimal> usdRates = Map.of("USD", BigDecimal.ONE);

        boolean needsConversion = (filters.priceMin() != null || filters.priceMax() != null)
                && candidates.stream().filter(hotel -> hotel != null).anyMatch(hotel ->
                        !filters.currency().equals(currencyOf(hotel)));
        if (needsConversion) {
            try {
                usdRates = readUsdRates(exchangeRateService.latest());
            } catch (RuntimeException exception) {
                warnings.add(
                        "Some hotel prices could not be converted for the selected currency filter.");
            }
        }

        List<Map<String, Object>> filtered = new ArrayList<>();
        boolean omittedUnconvertiblePrice = false;
        for (Map<String, Object> hotel : candidates) {
            if (hotel == null) continue;
            if (filters.ratingMin() != null
                    && ratingOf(hotel).compareTo(filters.ratingMin()) < 0) {
                continue;
            }
            if (!matchesAmenities(hotel, filters.amenities())) continue;
            if (!matchesRoomType(hotel, filters.roomType())) continue;
            if (!matchesPreferences(hotel, filters.preferences())) continue;
            if (filters.priceMin() != null || filters.priceMax() != null) {
                BigDecimal price = decimal(hotel.get("price"));
                BigDecimal converted = price == null
                        ? null
                        : convert(price, currencyOf(hotel), filters.currency(), usdRates);
                if (converted == null) {
                    omittedUnconvertiblePrice = true;
                    continue;
                }
                if (filters.priceMin() != null
                        && converted.compareTo(filters.priceMin()) < 0) continue;
                if (filters.priceMax() != null
                        && converted.compareTo(filters.priceMax()) > 0) continue;
            }
            filtered.add(hotel);
        }
        if (omittedUnconvertiblePrice && warnings.isEmpty()) {
            warnings.add(
                    "Some hotel prices could not be converted for the selected currency filter.");
        }
        return new FilterOutcome(
                List.copyOf(filtered),
                List.copyOf(new LinkedHashSet<>(warnings)));
    }

    public static String validateCurrency(String value) {
        String normalized = value == null ? "USD" : value.trim().toUpperCase(Locale.ROOT);
        if (!DISPLAY_CURRENCIES.contains(normalized)) {
            throw new ResponseStatusException(
                    HttpStatus.BAD_REQUEST, "currency must be USD, EUR, or GBP");
        }
        return normalized;
    }

    public HotelFilters validateFilters(HotelFilters filters) {
        return validate(filters);
    }

    private static HotelFilters validate(HotelFilters filters) {
        String currency = validateCurrency(filters.currency());
        BigDecimal min = validateAmount(filters.priceMin(), "price_min");
        BigDecimal max = validateAmount(filters.priceMax(), "price_max");
        BigDecimal rating = filters.ratingMin();
        if (rating != null && (rating.signum() < 0
                || rating.compareTo(BigDecimal.valueOf(5)) > 0)) {
            throw new ResponseStatusException(
                    HttpStatus.BAD_REQUEST, "rating_min must be between 0 and 5");
        }
        if (min != null && max != null && min.compareTo(max) > 0) {
            throw new ResponseStatusException(
                    HttpStatus.BAD_REQUEST, "price_min must not exceed price_max");
        }
        validateFilterText(filters.roomType(), "room_type");
        validateFilterText(filters.amenities(), "amenities");
        validateFilterText(filters.preferences(), "preferences");
        return new HotelFilters(
                currency,
                min,
                max,
                rating,
                filters.amenities(),
                filters.roomType(),
                filters.preferences());
    }

    private static BigDecimal validateAmount(BigDecimal amount, String name) {
        if (amount != null && (amount.signum() < 0
                || amount.precision() > 16
                || amount.scale() > 4)) {
            throw new ResponseStatusException(
                    HttpStatus.BAD_REQUEST, name + " must be a non-negative amount");
        }
        return amount;
    }

    private static void validateFilterText(String value, String name) {
        if (value != null && value.length() > 300) {
            throw new ResponseStatusException(
                    HttpStatus.BAD_REQUEST, name + " is too long");
        }
    }

    private static BigDecimal ratingOf(Map<String, Object> hotel) {
        BigDecimal rating = decimal(hotel.get("rating"));
        if (rating == null) rating = decimal(hotel.get("google_rating"));
        return rating == null ? BigDecimal.ZERO : rating;
    }

    private static boolean matchesAmenities(Map<String, Object> hotel, String query) {
        List<String> requested = tokens(query);
        if (requested.isEmpty()) return true;
        Set<String> amenities = new LinkedHashSet<>();
        Object values = hotel.get("amenities");
        if (values instanceof List<?> list) {
            list.stream().filter(value -> value != null)
                    .map(value -> value.toString().toLowerCase(Locale.ROOT)
                            .replaceAll("[^\\p{L}\\p{N}]", ""))
                    .forEach(amenities::add);
        }
        return requested.stream().map(token ->
                token.replaceAll("[^\\p{L}\\p{N}]", ""))
                .filter(token -> !token.isBlank())
                .allMatch(token -> amenities.stream().anyMatch(value -> value.contains(token)));
    }

    private static boolean matchesRoomType(Map<String, Object> hotel, String requested) {
        String needle = requested == null ? "" : requested.trim().toLowerCase(Locale.ROOT);
        if (needle.isEmpty()) return true;
        for (String key : List.of("room_types", "offers")) {
            Object values = hotel.get(key);
            if (!(values instanceof List<?> list)) continue;
            for (Object value : list) {
                if (!(value instanceof Map<?, ?> item)) continue;
                String roomName = text(item.get("room_name")) + " "
                        + text(item.get("name")) + " " + text(item.get("room_type"));
                if (roomName.toLowerCase(Locale.ROOT).contains(needle)) return true;
            }
        }
        return false;
    }

    private static boolean matchesPreferences(Map<String, Object> hotel, String query) {
        List<String> requested = tokens(query);
        if (requested.isEmpty()) return true;
        StringBuilder searchable = new StringBuilder();
        for (String key : List.of("name", "title", "description", "location_name")) {
            searchable.append(' ').append(text(hotel.get(key)));
        }
        Object amenities = hotel.get("amenities");
        if (amenities instanceof List<?> list) {
            list.forEach(value -> searchable.append(' ').append(text(value)));
        }
        Object offers = hotel.get("offers");
        if (offers instanceof List<?> list) {
            list.forEach(value -> searchable.append(' ').append(text(value)));
        }
        String haystack = searchable.toString().toLowerCase(Locale.ROOT);
        return requested.stream().allMatch(haystack::contains);
    }

    private static List<String> tokens(String value) {
        if (value == null || value.isBlank()) return List.of();
        return java.util.Arrays.stream(value.split(","))
                .map(token -> token.trim().toLowerCase(Locale.ROOT))
                .filter(token -> !token.isEmpty())
                .limit(10)
                .toList();
    }

    private static Map<String, BigDecimal> readUsdRates(Map<String, Object> response) {
        Map<String, BigDecimal> rates = new LinkedHashMap<>();
        rates.put("USD", BigDecimal.ONE);
        Object rows = response.get("rates");
        if (!(rows instanceof List<?> list)) return rates;
        for (Object value : list) {
            if (!(value instanceof Map<?, ?> row)) continue;
            String quote = text(row.get("quote")).toUpperCase(Locale.ROOT);
            BigDecimal rate = decimal(row.get("rate"));
            if (quote.matches("[A-Z]{3}") && rate != null && rate.signum() > 0) {
                rates.putIfAbsent(quote, rate);
            }
        }
        return rates;
    }

    private static BigDecimal convert(
            BigDecimal amount,
            String source,
            String target,
            Map<String, BigDecimal> usdRates) {
        if (source.equals(target)) return amount;
        BigDecimal sourceRate = usdRates.get(source);
        BigDecimal targetRate = usdRates.get(target);
        if (sourceRate == null || targetRate == null) return null;
        return amount.divide(sourceRate, 10, RoundingMode.HALF_UP)
                .multiply(targetRate);
    }

    private static String currencyOf(Map<String, Object> hotel) {
        Object value = hotel.get("currency");
        if (value == null) value = hotel.get("price_currency");
        if (value == null) value = hotel.get("price_currency_code");
        String normalized = text(value).toUpperCase(Locale.ROOT);
        return normalized.matches("[A-Z]{3}") ? normalized : "USD";
    }

    private static BigDecimal decimal(Object value) {
        if (value instanceof BigDecimal decimal) return decimal;
        if (value instanceof Number number) {
            double parsed = number.doubleValue();
            return Double.isFinite(parsed) ? BigDecimal.valueOf(parsed) : null;
        }
        if (value == null) return null;
        try {
            return new BigDecimal(value.toString().trim());
        } catch (NumberFormatException exception) {
            return null;
        }
    }

    private static String text(Object value) {
        return value == null ? "" : value.toString();
    }

    private static Map<String, Object> normalize(Map<String, Object> original, String type) {
        Map<String, Object> item = new LinkedHashMap<>(original);
        String source = text(item.get("source")).toLowerCase(Locale.ROOT);
        boolean supportedProvider = ("flight".equals(type) && "duffel".equals(source))
                || ("hotel".equals(type) && "liteapi".equals(source));
        if (!supportedProvider) source = "partner";
        item.put("source", source);
        item.put("type", type);

        String title = firstNonBlank(item.get("title"), item.get("name"));
        if (title.isBlank() && "flight".equals(type)) {
            title = firstNonBlank(item.get("airline"), item.get("flight_number"));
        }
        item.put("title", title);

        Object price = item.get("price");
        if (price == null) {
            price = "hotel".equals(type)
                    ? item.get("price_per_night")
                    : firstValue(item.get("economy_price"), item.get("price_per_day"));
        }
        item.put("price", price);

        String currency = firstNonBlank(
                item.get("price_currency"),
                item.get("price_currency_code"),
                item.get("total_currency"),
                item.get("currency"));
        if (currency.isBlank()) currency = "USD";
        currency = currency.toUpperCase(Locale.ROOT);
        item.put("currency", currency);

        Map<String, Object> location = new LinkedHashMap<>();
        putIfPresent(location, "city", firstValue(item.get("city"), item.get("location_name")));
        putIfPresent(location, "country", item.get("country"));
        putIfPresent(location, "address", item.get("location_name"));
        putIfPresent(location, "origin", firstValue(item.get("origin_city"), item.get("origin")));
        putIfPresent(location, "destination",
                firstValue(item.get("destination_city"), item.get("destination")));
        putIfPresent(location, "origin_code", item.get("origin_code"));
        putIfPresent(location, "destination_code", item.get("destination_code"));
        putIfPresent(location, "latitude", item.get("latitude"));
        putIfPresent(location, "longitude", item.get("longitude"));
        item.put("location", location);

        Map<String, Object> dates = new LinkedHashMap<>();
        Object start = firstValue(item.get("departure_time"), item.get("check_in_date"));
        Object end = firstValue(item.get("arrival_time"), item.get("check_out_date"));
        dates.put("start", start);
        dates.put("end", end);
        item.put("dates", dates);

        LinkedHashSet<String> images = new LinkedHashSet<>();
        addImage(images, item.get("image_url"));
        addImage(images, item.get("airline_logo_url"));
        addImages(images, item.get("images"));
        addImages(images, item.get("gallery_images"));
        item.put("images", List.copyOf(images));

        Object rating = firstValue(item.get("rating"), item.get("google_rating"));
        item.put("rating", rating);
        if (!(item.get("amenities") instanceof List<?>)) item.put("amenities", List.of());

        List<Map<String, Object>> offers = normalizeOffers(item.get("offers"), item, title);
        item.put("offers", offers);
        // Search inventory is not a booking record; never propagate private refs
        // from partner attributes or provider payloads into a public search result.
        item.put("booking_ref", null);
        return item;
    }

    private static List<Map<String, Object>> normalizeOffers(
            Object rawOffers,
            Map<String, Object> item,
            String title) {
        List<Map<String, Object>> offers = new ArrayList<>();
        if (rawOffers instanceof List<?> list) {
            for (Object value : list) {
                if (!(value instanceof Map<?, ?> raw)) continue;
                Map<String, Object> offer = new LinkedHashMap<>();
                raw.forEach((key, entry) -> {
                    if (key != null) offer.put(key.toString(), entry);
                });
                Object offerPrice = firstValue(
                        offer.get("total_amount"), offer.get("price_per_night"),
                        offer.get("economy_price"), offer.get("price"));
                String offerCurrency = firstNonBlank(
                        offer.get("total_currency"), offer.get("price_currency"),
                        offer.get("currency"), item.get("currency"));
                offer.put("price", offerPrice);
                offer.put("currency", offerCurrency.toUpperCase(Locale.ROOT));
                offer.putIfAbsent("source", item.get("source"));
                offer.putIfAbsent(
                        "name", firstNonBlank(
                                offer.get("room_name"), offer.get("name"), title));
                offer.putIfAbsent("conditions", null);
                offers.add(offer);
            }
        }
        if (!offers.isEmpty()) return List.copyOf(offers);

        Object price = item.get("price");
        if (price == null) return List.of();
        Map<String, Object> offer = new LinkedHashMap<>();
        offer.put("id", firstValue(item.get("duffel_offer_id"), item.get("id")));
        offer.put("name", title);
        offer.put("price", price);
        offer.put("currency", item.get("currency"));
        offer.put("source", item.get("source"));
        offer.put("conditions", null);
        offers.add(offer);
        return List.copyOf(offers);
    }

    private static String firstNonBlank(Object... values) {
        for (Object value : values) {
            if (value != null && !value.toString().isBlank()) return value.toString().trim();
        }
        return "";
    }

    private static Object firstValue(Object... values) {
        for (Object value : values) {
            if (value != null && !value.toString().isBlank()) return value;
        }
        return null;
    }

    private static void putIfPresent(Map<String, Object> target, String key, Object value) {
        if (value != null && !value.toString().isBlank()) target.put(key, value);
    }

    private static void addImage(Set<String> target, Object value) {
        if (value == null) return;
        String url = value.toString().trim();
        if (url.startsWith("https://") || url.startsWith("http://")) target.add(url);
    }

    private static void addImages(Set<String> target, Object raw) {
        if (raw instanceof List<?> list) list.forEach(value -> addImage(target, value));
    }
}
