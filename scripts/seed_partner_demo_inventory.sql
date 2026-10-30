-- Idempotent demo inventory for the Al-Masa Hotel and Zentrip Car Rental
-- partner accounts. Register both users and configure their partner roles
-- before running this script. Hotel available_rooms is live global inventory;
-- the seeded date schedule and rental vehicle counts remain descriptive metadata.

SELECT
    u.email,
    u.role,
    p.name AS partner_name,
    p.service_type,
    p.status AS partner_status
FROM users u
LEFT JOIN partners p ON p.id = u.partner_id
WHERE u.email IN (
    'almasahotel@zentrip.ly',
    'zentripcarrental@zentrip.com'
);

START TRANSACTION;

INSERT INTO partner_listings (
    partner_id, type, title, city, country, description, image_url,
    price, active, attributes, location_name, google_maps_url, place_id,
    google_rating, google_review_count, amenities, tax_and_fees_percentage,
    available_rooms,
    created_at, updated_at
)
SELECT
    p.id,
    'hotel',
    'Al-Masa Hotel',
    'Tripoli',
    'Libya',
    'Demo hotel inventory for the Al-Masa Hotel partner.',
    'https://images.unsplash.com/photo-1566073771259-6a8506099945?w=900&auto=format&fit=crop',
    120.00,
    TRUE,
    JSON_OBJECT(
        'seed_key', 'al-masa-hotel-demo-v1',
        'name', 'Al-Masa Hotel',
        'location_name', 'Airport Road, Tripoli',
        'google_maps_url',
            'https://www.google.com/maps/search/?api=1&query=32.8872%2C13.1913',
        'location_input', '32.8872,13.1913',
        'latitude', 32.8872,
        'longitude', 13.1913,
        'tax_and_fees_percentage', 12.00,
        'available_rooms', 15,
        'amenities', JSON_ARRAY(
            'Gym', 'Wi-Fi', 'Restaurant', 'Spa', 'Pool'
        ),
        'room_types', JSON_ARRAY(
            JSON_OBJECT(
                'code', 'standard',
                'name', 'Standard Room',
                'price_per_night', 120.00,
                'max_guests', 2,
                'rooms_available', 12
            ),
            JSON_OBJECT(
                'code', 'deluxe',
                'name', 'Deluxe Room',
                'price_per_night', 175.00,
                'max_guests', 2,
                'rooms_available', 8
            ),
            JSON_OBJECT(
                'code', 'family-suite',
                'name', 'Family Suite',
                'price_per_night', 260.00,
                'max_guests', 4,
                'rooms_available', 4
            )
        ),
        'availability_schedule', JSON_ARRAY(
            JSON_OBJECT(
                'start_date', CURRENT_DATE,
                'end_date', DATE_ADD(CURRENT_DATE, INTERVAL 365 DAY),
                'available', TRUE
            )
        )
    ),
    'Airport Road, Tripoli',
    'https://www.google.com/maps/search/?api=1&query=32.8872%2C13.1913',
    0.0,
    0,
    NULL,
    JSON_ARRAY('Gym', 'Wi-Fi', 'Restaurant', 'Spa', 'Pool'),
    12.00,
    15,
    NOW(),
    NOW()
FROM partners p
JOIN users u ON u.partner_id = p.id
WHERE u.email = 'almasahotel@zentrip.ly'
  AND u.role = 'partner'
  AND p.slug = 'al-masa-hotel'
  AND p.service_type = 'hotel'
  AND p.status = 'active'
  AND NOT EXISTS (
      SELECT 1
      FROM partner_listings existing
      WHERE existing.partner_id = p.id
        AND JSON_UNQUOTE(JSON_EXTRACT(existing.attributes, '$.seed_key'))
            = 'al-masa-hotel-demo-v1'
  );

UPDATE partner_listings listing
JOIN partners partner ON partner.id = listing.partner_id
JOIN users user_account ON user_account.partner_id = partner.id
SET listing.amenities = JSON_ARRAY('Gym', 'Wi-Fi', 'Restaurant', 'Spa', 'Pool'),
    listing.google_maps_url =
        'https://www.google.com/maps/search/?api=1&query=32.8872%2C13.1913',
    listing.available_rooms = IF(
        JSON_EXTRACT(listing.attributes, '$.available_rooms') IS NULL
        AND NOT EXISTS (
            SELECT 1 FROM bookings
            WHERE partner_listing_id = listing.id
        ),
        15,
        listing.available_rooms
    ),
    listing.attributes = JSON_SET(
        listing.attributes,
        '$.google_maps_url',
            'https://www.google.com/maps/search/?api=1&query=32.8872%2C13.1913',
        '$.amenities', JSON_ARRAY('Gym', 'Wi-Fi', 'Restaurant', 'Spa', 'Pool'),
        '$.available_rooms', IF(
            JSON_EXTRACT(listing.attributes, '$.available_rooms') IS NULL
            AND NOT EXISTS (
                SELECT 1 FROM bookings
                WHERE partner_listing_id = listing.id
            ),
            15,
            JSON_EXTRACT(listing.attributes, '$.available_rooms')
        )
    ),
    listing.updated_at = NOW()
WHERE user_account.email = 'almasahotel@zentrip.ly'
  AND listing.type = 'hotel'
  AND JSON_UNQUOTE(JSON_EXTRACT(listing.attributes, '$.seed_key'))
      = 'al-masa-hotel-demo-v1';

INSERT INTO partner_listings (
    partner_id, type, title, city, country, description, image_url,
    price, active, attributes, created_at, updated_at
)
SELECT
    p.id,
    'car',
    inventory.title,
    'Tripoli',
    'Libya',
    inventory.description,
    inventory.image_url,
    inventory.price_per_day,
    TRUE,
    JSON_OBJECT(
        'seed_key', inventory.seed_key,
        'brand', inventory.brand,
        'model', inventory.model,
        'category', inventory.category,
        'year', inventory.model_year,
        'seats', inventory.seats,
        'transmission', inventory.transmission,
        'fuel_type', inventory.fuel_type,
        'features', inventory.features,
        'rating', inventory.rating,
        'pickup_location', 'Tripoli',
        'return_location', 'Tripoli',
        'vehicles_available', inventory.vehicles_available,
        'has_ac', TRUE,
        'has_gps', inventory.has_gps,
        'availability_schedule', JSON_ARRAY(
            JSON_OBJECT(
                'start_date', CURRENT_DATE,
                'end_date', DATE_ADD(CURRENT_DATE, INTERVAL 365 DAY),
                'available', TRUE
            )
        )
    ),
    NOW(),
    NOW()
FROM partners p
JOIN users u ON u.partner_id = p.id
CROSS JOIN (
    SELECT
        'zentrip-car-sedan-v1' AS seed_key,
        'Toyota Corolla' AS title,
        'Toyota' AS brand,
        'Corolla' AS model,
        'economy' AS category,
        2024 AS model_year,
        5 AS seats,
        'automatic' AS transmission,
        'hybrid' AS fuel_type,
        JSON_ARRAY('Bluetooth', 'Backup camera', 'Low fuel consumption') AS features,
        4.6 AS rating,
        45.00 AS price_per_day,
        6 AS vehicles_available,
        FALSE AS has_gps,
        'Economy sedan rental in Tripoli.' AS description,
        'https://images.unsplash.com/photo-1552519507-da3b142c6e3d?w=900&auto=format&fit=crop' AS image_url
    UNION ALL
    SELECT
        'zentrip-car-suv-v1',
        'Hyundai Tucson',
        'Hyundai',
        'Tucson',
        'suv',
        2025,
        5,
        'automatic',
        'gasoline',
        JSON_ARRAY('Bluetooth', 'Backup camera', 'Large luggage space'),
        4.7,
        75.00,
        4,
        TRUE,
        'SUV rental in Tripoli.',
        'https://images.unsplash.com/photo-1519641471654-76ce0107ad1b?w=900&auto=format&fit=crop'
    UNION ALL
    SELECT
        'zentrip-car-luxury-v1',
        'Mercedes-Benz C-Class',
        'Mercedes-Benz',
        'C-Class',
        'luxury',
        2025,
        5,
        'automatic',
        'gasoline',
        JSON_ARRAY('Bluetooth', 'Leather interior', 'Navigation'),
        4.8,
        125.00,
        2,
        TRUE,
        'Luxury sedan rental in Tripoli.',
        'https://images.unsplash.com/photo-1618843479313-40f8afb4b4d8?w=900&auto=format&fit=crop'
) inventory
WHERE u.email = 'zentripcarrental@zentrip.com'
  AND u.role = 'partner'
  AND p.slug = 'zentrip-car-rental'
  AND p.service_type = 'car'
  AND p.status = 'active'
  AND NOT EXISTS (
      SELECT 1
      FROM partner_listings existing
      WHERE existing.partner_id = p.id
        AND JSON_UNQUOTE(JSON_EXTRACT(existing.attributes, '$.seed_key'))
            = inventory.seed_key
  );

UPDATE partner_listings
SET attributes = JSON_SET(
        attributes,
        '$.location_input',
        COALESCE(
            JSON_UNQUOTE(JSON_EXTRACT(attributes, '$.location_input')),
            '32.8872,13.1913'
        ),
        '$.latitude',
        COALESCE(JSON_EXTRACT(attributes, '$.latitude'), 32.8872),
        '$.longitude',
        COALESCE(JSON_EXTRACT(attributes, '$.longitude'), 13.1913)
    ),
    updated_at = NOW()
WHERE JSON_UNQUOTE(JSON_EXTRACT(attributes, '$.seed_key'))
    = 'al-masa-hotel-demo-v1'
  AND (
      JSON_EXTRACT(attributes, '$.latitude') IS NULL
      OR JSON_EXTRACT(attributes, '$.longitude') IS NULL
  );

UPDATE partner_listings
SET location_name = COALESCE(location_name, 'Airport Road, Tripoli'),
    google_maps_url = COALESCE(google_maps_url, '32.8872,13.1913'),
    amenities = COALESCE(
        amenities,
        JSON_EXTRACT(attributes, '$.amenities'),
        JSON_ARRAY()
    ),
    tax_and_fees_percentage = COALESCE(tax_and_fees_percentage, 12.00)
WHERE JSON_UNQUOTE(JSON_EXTRACT(attributes, '$.seed_key'))
    = 'al-masa-hotel-demo-v1';

-- Match the reference/status fields generated by PartnerController for
-- listings created through the partner dashboard.
UPDATE partner_listings
SET attributes = JSON_SET(
        attributes,
        '$.listing_code',
        CONCAT(
            CASE type WHEN 'hotel' THEN 'HTL' ELSE 'CAR' END,
            '-',
            LPAD(id, 6, '0')
        ),
        '$.status',
        IF(active, 'published', 'paused'),
        '$.is_active',
        active
    ),
    updated_at = NOW()
WHERE JSON_UNQUOTE(JSON_EXTRACT(attributes, '$.seed_key')) IN (
    'al-masa-hotel-demo-v1',
    'zentrip-car-sedan-v1',
    'zentrip-car-suv-v1',
    'zentrip-car-luxury-v1'
);

COMMIT;

SELECT
    p.name AS partner_name,
    l.type,
    l.title,
    l.city,
    l.price,
    JSON_UNQUOTE(JSON_EXTRACT(l.attributes, '$.listing_code')) AS listing_code,
    l.active
FROM partner_listings l
JOIN partners p ON p.id = l.partner_id
WHERE JSON_UNQUOTE(JSON_EXTRACT(l.attributes, '$.seed_key')) IN (
    'al-masa-hotel-demo-v1',
    'zentrip-car-sedan-v1',
    'zentrip-car-suv-v1',
    'zentrip-car-luxury-v1'
)
ORDER BY p.name, l.title;
