-- Add the canonical hotel fields to existing shared partner listings.
-- Run against the Zentrip database before deploying the hotel model update.
ALTER TABLE partner_listings
    ADD COLUMN location_name VARCHAR(512) NULL,
    ADD COLUMN google_maps_url VARCHAR(2048) NULL,
    ADD COLUMN place_id VARCHAR(255) NULL,
    ADD COLUMN google_rating DECIMAL(2,1) NOT NULL DEFAULT 0.0,
    ADD COLUMN google_review_count INT UNSIGNED NOT NULL DEFAULT 0,
    ADD COLUMN amenities JSON NULL,
    ADD COLUMN tax_and_fees_percentage DECIMAL(5,2) NOT NULL DEFAULT 12.00,
    ADD COLUMN available_rooms INT UNSIGNED NOT NULL DEFAULT 0;

UPDATE partner_listings
SET google_rating = COALESCE(
        NULLIF(google_rating, 0.0),
        CAST(NULLIF(JSON_UNQUOTE(JSON_EXTRACT(
            attributes, '$.google_rating'
        )), '') AS DECIMAL(2,1)),
        0.0
    ),
    google_review_count = COALESCE(
        NULLIF(google_review_count, 0),
        CAST(NULLIF(JSON_UNQUOTE(JSON_EXTRACT(
            attributes, '$.google_review_count'
        )), '') AS UNSIGNED),
        0
    ),
    location_name = COALESCE(
        location_name,
        NULLIF(JSON_UNQUOTE(JSON_EXTRACT(attributes, '$.location_name')), ''),
        NULLIF(JSON_UNQUOTE(JSON_EXTRACT(attributes, '$.address')), ''),
        NULLIF(JSON_UNQUOTE(JSON_EXTRACT(attributes, '$.neighborhood')), ''),
        city
    ),
    google_maps_url = COALESCE(
        google_maps_url,
        NULLIF(JSON_UNQUOTE(JSON_EXTRACT(attributes, '$.google_maps_url')), ''),
        NULLIF(JSON_UNQUOTE(JSON_EXTRACT(attributes, '$.location_input')), '')
    ),
    place_id = COALESCE(
        place_id,
        NULLIF(JSON_UNQUOTE(JSON_EXTRACT(attributes, '$.place_id')), ''),
        NULLIF(JSON_UNQUOTE(JSON_EXTRACT(attributes, '$.google_place_id')), '')
    ),
    amenities = COALESCE(
        amenities,
        JSON_EXTRACT(attributes, '$.amenities'),
        JSON_ARRAY()
    ),
    tax_and_fees_percentage = CASE
        WHEN tax_and_fees_percentage = 12.00
             AND JSON_EXTRACT(attributes, '$.tax_and_fees_percentage') IS NOT NULL
        THEN CAST(JSON_UNQUOTE(JSON_EXTRACT(
            attributes, '$.tax_and_fees_percentage'
        )) AS DECIMAL(5,2))
        ELSE tax_and_fees_percentage
    END,
    available_rooms = CASE
        WHEN JSON_EXTRACT(attributes, '$.available_rooms') IS NOT NULL
        THEN CAST(JSON_UNQUOTE(JSON_EXTRACT(
            attributes, '$.available_rooms'
        )) AS UNSIGNED)
        WHEN JSON_LENGTH(JSON_EXTRACT(attributes, '$.room_types')) > 0
        THEN (
            SELECT COALESCE(SUM(room_counts.rooms_available), 0)
            FROM JSON_TABLE(
                partner_listings.attributes,
                '$.room_types[*]' COLUMNS (
                    rooms_available INT PATH '$.rooms_available'
                )
            ) AS room_counts
        )
        ELSE available_rooms
    END
WHERE type = 'hotel';
