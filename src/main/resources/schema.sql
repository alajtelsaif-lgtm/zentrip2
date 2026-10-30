CREATE TABLE IF NOT EXISTS partners (
    id BIGSERIAL PRIMARY KEY,
    slug VARCHAR(100) NOT NULL UNIQUE,
    name VARCHAR(255) NOT NULL,
    service_type VARCHAR(30) NOT NULL,
    status VARCHAR(20) NOT NULL DEFAULT 'active',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS users (
    id BIGSERIAL PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    email VARCHAR(255) NOT NULL UNIQUE,
    phone VARCHAR(20) NULL,
    email_verified_at TIMESTAMPTZ NULL,
    password VARCHAR(255) NOT NULL,
    role VARCHAR(20) NOT NULL DEFAULT 'customer',
    partner_id BIGINT NULL,
    remember_token VARCHAR(100) NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT users_partner_id_foreign FOREIGN KEY (partner_id) REFERENCES partners(id) ON DELETE SET NULL
);
CREATE INDEX IF NOT EXISTS users_partner_id_index ON users (partner_id);

CREATE TABLE IF NOT EXISTS password_reset_codes (
    email VARCHAR(255) NOT NULL PRIMARY KEY,
    code_hash CHAR(64) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL,
    expires_at TIMESTAMPTZ NOT NULL,
    attempts INTEGER NOT NULL DEFAULT 0,
    CONSTRAINT password_reset_codes_expires_at_index CHECK (expires_at IS NOT NULL)
);
CREATE INDEX IF NOT EXISTS password_reset_codes_expires_at_index ON password_reset_codes (expires_at);

CREATE TABLE IF NOT EXISTS partner_listings (
    id BIGSERIAL PRIMARY KEY,
    partner_id BIGINT NOT NULL,
    type VARCHAR(30) NOT NULL,
    title VARCHAR(255) NOT NULL,
    city VARCHAR(255) NOT NULL DEFAULT '',
    country VARCHAR(255) NOT NULL DEFAULT '',
    description TEXT NULL,
    image_url VARCHAR(2048) NULL,
    price DECIMAL(10,2) NOT NULL DEFAULT 0,
    active BOOLEAN NOT NULL DEFAULT TRUE,
    attributes JSONB NOT NULL,
    location_name VARCHAR(512) NULL,
    google_maps_url VARCHAR(2048) NULL,
    place_id VARCHAR(255) NULL,
    google_rating DECIMAL(2,1) NOT NULL DEFAULT 0.0,
    google_review_count INTEGER NOT NULL DEFAULT 0,
    amenities JSONB NULL,
    tax_and_fees_percentage DECIMAL(5,2) NOT NULL DEFAULT 12.00,
    available_rooms INTEGER NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT partner_listings_partner_foreign FOREIGN KEY (partner_id) REFERENCES partners(id) ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS partner_listings_type_city_index ON partner_listings (type, city, active);
CREATE INDEX IF NOT EXISTS partner_listings_partner_index ON partner_listings (partner_id, active);

CREATE TABLE IF NOT EXISTS airports (
    code CHAR(3) NOT NULL PRIMARY KEY,
    city VARCHAR(100) NOT NULL,
    airport_name VARCHAR(255) NOT NULL,
    country VARCHAR(100) NOT NULL,
    region VARCHAR(100) NOT NULL
);
CREATE INDEX IF NOT EXISTS airports_city_index ON airports (city);

INSERT INTO airports (code, city, airport_name, country, region) VALUES
    ('MJI', 'Tripoli', 'Mitiga International Airport', 'Libya', 'Western Libya'),
    ('MRA', 'Misrata', 'Misrata International Airport', 'Libya', 'Central Libya'),
    ('BEN', 'Benghazi', 'Benina International Airport', 'Libya', 'Eastern Libya'),
    ('SEB', 'Sebha', 'Sebha Airport', 'Libya', 'Southern Libya'),
    ('CAI', 'Cairo', 'Cairo International Airport', 'Egypt', 'North Africa'),
    ('TUN', 'Tunis', 'Tunis-Carthage International Airport', 'Tunisia', 'North Africa'),
    ('IST', 'Istanbul', 'Istanbul Airport', 'Turkiye', 'Europe'),
    ('JED', 'Jeddah', 'King Abdulaziz International Airport', 'Saudi Arabia', 'Middle East'),
    ('DXB', 'Dubai', 'Dubai International Airport', 'United Arab Emirates', 'Middle East'),
    ('DPS', 'Bali', 'Ngurah Rai International Airport', 'Indonesia', 'Southeast Asia'),
    ('CGK', 'Jakarta', 'Soekarno-Hatta International Airport', 'Indonesia', 'Southeast Asia')
ON CONFLICT (code) DO UPDATE SET
    city = EXCLUDED.city,
    airport_name = EXCLUDED.airport_name,
    country = EXCLUDED.country,
    region = EXCLUDED.region;

CREATE TABLE IF NOT EXISTS user_reviews (
    id BIGSERIAL PRIMARY KEY,
    user_id BIGINT NOT NULL,
    item_id VARCHAR(100) NOT NULL,
    item_type VARCHAR(30) NOT NULL,
    rating DECIMAL(2,1) NOT NULL,
    comment TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (user_id, item_type, item_id),
    CONSTRAINT user_reviews_user_foreign FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
    CONSTRAINT user_reviews_rating_check CHECK (rating >= 1 AND rating <= 5)
);
CREATE INDEX IF NOT EXISTS user_reviews_item_rating_index ON user_reviews (item_type, item_id, rating);

CREATE TABLE IF NOT EXISTS user_profiles (
    user_id BIGINT NOT NULL PRIMARY KEY,
    photo_url VARCHAR(2048) NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT user_profiles_user_id_foreign FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS ai_chat_messages (
    id BIGSERIAL PRIMARY KEY,
    user_id BIGINT NOT NULL,
    session_id VARCHAR(100) NOT NULL,
    role TEXT NOT NULL CHECK (role IN ('user', 'model')),
    content TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS ai_chat_session_history_index ON ai_chat_messages (user_id, session_id, id);
CREATE INDEX IF NOT EXISTS ai_chat_messages_user_id_foreign ON ai_chat_messages (user_id);
ALTER TABLE ai_chat_messages ADD CONSTRAINT ai_chat_messages_user_id_foreign FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE;

CREATE TABLE IF NOT EXISTS travel_preferences (
    user_id BIGINT NOT NULL PRIMARY KEY,
    budget_level VARCHAR(20) NOT NULL DEFAULT 'balanced',
    travel_pace VARCHAR(20) NOT NULL DEFAULT 'balanced',
    trip_duration_days SMALLINT NOT NULL DEFAULT 7,
    travelers SMALLINT NOT NULL DEFAULT 1,
    interests VARCHAR(500) NOT NULL DEFAULT '',
    preferred_destination VARCHAR(255) NULL,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT travel_preferences_user_id_foreign FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS tourist_monuments (
    id VARCHAR(64) NOT NULL PRIMARY KEY,
    title VARCHAR(255) NOT NULL,
    location VARCHAR(255) NOT NULL,
    category_tag VARCHAR(100) NOT NULL DEFAULT '',
    category VARCHAR(40) NOT NULL DEFAULT 'landmark',
    rating DECIMAL(3,2) NOT NULL DEFAULT 0,
    review_count INTEGER NOT NULL DEFAULT 0,
    description TEXT NOT NULL,
    working_hours VARCHAR(255) NOT NULL DEFAULT '',
    best_time_to_visit VARCHAR(255) NOT NULL DEFAULT '',
    entry_fee DECIMAL(10,2) NULL,
    image_url VARCHAR(2048) NOT NULL DEFAULT '',
    tags JSONB NOT NULL,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    sort_order INTEGER NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS tourist_monuments_active_order_index ON tourist_monuments (is_active, sort_order, title);

CREATE TABLE IF NOT EXISTS offers (
    id VARCHAR(64) NOT NULL PRIMARY KEY,
    title VARCHAR(255) NOT NULL,
    location VARCHAR(255) NOT NULL,
    country VARCHAR(255) NOT NULL,
    destination_code VARCHAR(10) NOT NULL,
    description TEXT NOT NULL,
    image_url VARCHAR(2048) NOT NULL,
    price_per_person DECIMAL(10,2) NOT NULL,
    flight_price_per_person DECIMAL(10,2) NOT NULL,
    hotel_price_per_night DECIMAL(10,2) NOT NULL,
    duration_nights SMALLINT NOT NULL,
    rating DECIMAL(3,2) NOT NULL DEFAULT 0,
    review_count INTEGER NOT NULL DEFAULT 0,
    highlights JSONB NOT NULL,
    is_featured BOOLEAN NOT NULL DEFAULT FALSE,
    category VARCHAR(40) NOT NULL DEFAULT 'city',
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    sort_order INTEGER NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS offers_active_order_index ON offers (is_active, is_featured, sort_order);

CREATE TABLE IF NOT EXISTS offer_catalog_metadata (
    offer_id VARCHAR(64) NOT NULL PRIMARY KEY,
    badge VARCHAR(100) NOT NULL DEFAULT '',
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

INSERT INTO offers (
    id, title, location, country, destination_code, description, image_url,
    price_per_person, flight_price_per_person, hotel_price_per_night,
    duration_nights, rating, review_count, highlights, is_featured, category, sort_order
) VALUES
('istanbul-dream', 'Istanbul Dream', 'Istanbul', 'Turkey', 'IST',
 'Explore historic palaces, mosques, bazaars, and the Bosphorus.',
 'https://images.unsplash.com/photo-1524231757912-21f4fe3a7200?w=1000',
 1290, 420, 95, 7, 4.8, 2340, jsonb_build_array('Blue Mosque', 'Hagia Sophia', 'Grand Bazaar'), TRUE, 'cultural', 1),
('bali-serenity', 'Bali Serenity', 'Bali', 'Indonesia', 'DPS',
 'Find quiet beaches, temples, rice terraces, and island sunsets.',
 'https://images.unsplash.com/photo-1537996194471-e657df975ab4?w=1000',
 1580, 680, 90, 10, 4.9, 4120, jsonb_build_array('Ubud', 'Tanah Lot', 'Seminyak Beach'), TRUE, 'beach', 2),
('paris-romance', 'Paris Romance', 'Paris', 'France', 'CDG',
 'Discover museums, river walks, neighborhood cafes, and city landmarks.',
 'https://images.unsplash.com/photo-1502602898657-3e91760cbb34?w=1000',
 2100, 750, 225, 6, 4.7, 5890, jsonb_build_array('Eiffel Tower', 'Louvre', 'Seine River'), FALSE, 'city', 3),
('dubai-luxury', 'Dubai Luxury', 'Dubai', 'United Arab Emirates', 'DXB',
 'Pair modern architecture with desert experiences and waterfront evenings.',
 'https://images.unsplash.com/photo-1512453979798-5ea266f8880c?w=1000',
 1750, 390, 270, 5, 4.8, 3210, jsonb_build_array('Burj Khalifa', 'Desert Safari', 'Palm Jumeirah'), TRUE, 'city', 4),
('maldives-escape', 'Maldives Escape', 'Male', 'Maldives', 'MLE',
 'Unwind among coral reefs, clear water, and quiet island stays.',
 'https://images.unsplash.com/photo-1573843981267-be1999ff37cd?w=1000',
 3200, 920, 330, 7, 4.9, 1870, jsonb_build_array('Snorkeling', 'Sunset Cruise', 'Dolphin Watching'), TRUE, 'beach', 5),
('tokyo-explorer', 'Tokyo Explorer', 'Tokyo', 'Japan', 'HND',
 'Explore traditional temples, neon streets, and local food markets.',
 'https://images.unsplash.com/photo-1540959733332-eab4deabeeaf?w=1000',
 2450, 810, 180, 9, 4.8, 2980, jsonb_build_array('Shibuya Crossing', 'Senso-ji', 'Mount Fuji'), FALSE, 'cultural', 6),
('cairo-pharaohs', 'Cairo & the Pyramids', 'Cairo', 'Egypt', 'CAI',
 'Stand beside the Giza pyramids, wander Khan el-Khalili, and cruise the Nile at sunset.',
 'https://thumb.wikimedia.org/wikipedia/commons/thumb/9/96/Pyramids_of_the_Giza_Necropolis.jpg/960px-Pyramids_of_the_Giza_Necropolis.jpg',
 505, 180, 65, 5, 4.7, 3150, jsonb_build_array('Giza Pyramids', 'Khan el-Khalili', 'Nile Cruise'), TRUE, 'cultural', 7),
('tunis-carthage', 'Tunis & Carthage', 'Tunis', 'Tunisia', 'TUN',
 'Walk the Medina alleys, Roman ruins, and the blue-and-white village of Sidi Bou Said.',
 'https://thumb.wikimedia.org/wikipedia/commons/thumb/0/05/Sidi_Chebaan.jpg/960px-Sidi_Chebaan.jpg',
 370, 150, 55, 4, 4.6, 1980, jsonb_build_array('Sidi Bou Said', 'Carthage', 'Tunis Medina'), FALSE, 'cultural', 8),
('jeddah-red-sea', 'Jeddah Red Sea Escape', 'Jeddah', 'Saudi Arabia', 'JED',
 'Waterfront promenades, historic Al-Balad, and Red Sea diving close to the city.',
 'https://thumb.wikimedia.org/wikipedia/commons/thumb/a/a9/Jeddah_Waterfront%2C_Western_Saudi_Arabia_%282026%29.jpg/960px-Jeddah_Waterfront%2C_Western_Saudi_Arabia_%282026%29.jpg',
 810, 260, 110, 5, 4.7, 2640, jsonb_build_array('Al-Balad', 'Corniche', 'Red Sea Diving'), TRUE, 'beach', 9),
('tripoli-heritage', 'Tripoli Heritage Weekend', 'Tripoli', 'Libya', 'MJI',
 'Stroll through the old medina, the Red Castle museum, and the Roman arch of Marcus Aurelius.',
 'https://thumb.wikimedia.org/wikipedia/commons/thumb/8/8d/Tripoli_at_night.jpg/960px-Tripoli_at_night.jpg',
 320, 140, 60, 3, 4.6, 860, jsonb_build_array('Red Castle Museum', 'Old Medina', 'Arch of Marcus Aurelius'), TRUE, 'cultural', 10),
('leptis-magna-discovery', 'Leptis Magna Discovery', 'Khoms', 'Libya', 'MJI',
 'Explore the best-preserved Roman city on the Mediterranean, then visit nearby Sabratha.',
 'https://thumb.wikimedia.org/wikipedia/commons/thumb/3/33/Leptis_Magna_%2829%29_%288288918733%29.jpg/960px-Leptis_Magna_%2829%29_%288288918733%29.jpg',
 305, 140, 55, 3, 4.9, 640, jsonb_build_array('Leptis Magna', 'Sabratha', 'Mediterranean Coast'), FALSE, 'cultural', 11),
('benghazi-green-mountain', 'Benghazi & Green Mountain', 'Benghazi', 'Libya', 'BEN',
 'Coastal city life with day trips to the Greek ruins of Cyrene and the harbour of Apollonia.',
 'https://thumb.wikimedia.org/wikipedia/commons/thumb/3/3c/Cyrene8.jpg/960px-Cyrene8.jpg',
 382, 150, 58, 4, 4.6, 520, jsonb_build_array('Cyrene', 'Apollonia', 'Benghazi Corniche'), FALSE, 'cultural', 12),
('siwa-desert-oasis', 'Siwa Desert Oasis', 'Siwa', 'Egypt', 'CAI',
 'Palm groves, salt lakes, hot springs, and quiet desert sunsets far from the crowds.',
 'https://thumb.wikimedia.org/wikipedia/commons/thumb/a/af/%D9%8A%D9%88%D9%85_%D8%AC%D8%AF%D9%8A%D8%AF.jpg/960px-%D9%8A%D9%88%D9%85_%D8%AC%D8%AF%D9%8A%D8%AF.jpg',
 420, 180, 60, 4, 4.7, 1230, jsonb_build_array('Siwa Oasis', 'Salt Lakes', 'Desert Sunset'), FALSE, 'desert', 13)
ON CONFLICT (id) DO NOTHING;

CREATE TABLE IF NOT EXISTS trips (
    id BIGSERIAL PRIMARY KEY,
    user_id BIGINT NOT NULL,
    partner_id BIGINT NULL,
    partner_listing_id BIGINT NULL,
    title VARCHAR(255) NOT NULL,
    destination VARCHAR(255) NOT NULL,
    start_date DATE NULL,
    end_date DATE NULL,
    details JSONB NULL,
    origin_code VARCHAR(10) NULL,
    origin_city VARCHAR(255) NULL,
    destination_code VARCHAR(10) NULL,
    destination_city VARCHAR(255) NULL,
    departure_date TIMESTAMPTZ NULL,
    return_date TIMESTAMPTZ NULL,
    flight_number VARCHAR(50) NULL,
    airline VARCHAR(255) NULL,
    airline_logo_url VARCHAR(2048) NULL,
    is_direct BOOLEAN NOT NULL DEFAULT TRUE,
    seat_class VARCHAR(50) NULL,
    price DECIMAL(10,2) NULL,
    booking_ref VARCHAR(100) NULL,
    status VARCHAR(30) NOT NULL DEFAULT 'upcoming',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT trips_user_id_foreign FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS trips_user_id_index ON trips (user_id);
CREATE INDEX IF NOT EXISTS trips_partner_id_index ON trips (partner_id);

CREATE TABLE IF NOT EXISTS flight_seat_holds (
    flight_listing_id BIGINT NOT NULL,
    seat_number VARCHAR(5) NOT NULL,
    user_id BIGINT NOT NULL,
    trip_id BIGINT NULL,
    status VARCHAR(16) NOT NULL DEFAULT 'reserved',
    booking_ref VARCHAR(100) NULL,
    expires_at TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (flight_listing_id, seat_number),
    CONSTRAINT flight_seat_holds_listing_foreign
        FOREIGN KEY (flight_listing_id) REFERENCES partner_listings(id) ON DELETE CASCADE,
    CONSTRAINT flight_seat_holds_user_foreign
        FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
    CONSTRAINT flight_seat_holds_trip_foreign
        FOREIGN KEY (trip_id) REFERENCES trips(id) ON DELETE SET NULL
);
CREATE INDEX IF NOT EXISTS flight_seat_holds_user_status_index ON flight_seat_holds (user_id, status, expires_at);
CREATE INDEX IF NOT EXISTS flight_seat_holds_trip_index ON flight_seat_holds (trip_id);

CREATE TABLE IF NOT EXISTS bookings (
    id BIGSERIAL PRIMARY KEY,
    user_id BIGINT NOT NULL,
    partner_id BIGINT NULL,
    partner_listing_id BIGINT NULL,
    trip_id BIGINT NULL,
    type VARCHAR(50) NOT NULL,
    status VARCHAR(30) NOT NULL DEFAULT 'pending',
    total_amount DECIMAL(10,2) NOT NULL DEFAULT 0,
    details JSONB NULL,
    title VARCHAR(255) NULL,
    subtitle VARCHAR(255) NULL,
    date TIMESTAMPTZ NULL,
    price DECIMAL(10,2) NULL,
    ref_code VARCHAR(100) NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT bookings_user_id_foreign FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS bookings_user_id_index ON bookings (user_id);
CREATE INDEX IF NOT EXISTS bookings_partner_id_index ON bookings (partner_id);

CREATE TABLE IF NOT EXISTS transfers (
    id BIGSERIAL PRIMARY KEY,
    user_id BIGINT NOT NULL,
    partner_id BIGINT NULL,
    partner_listing_id BIGINT NULL,
    provider_name VARCHAR(255) NOT NULL,
    vehicle_type VARCHAR(100) NOT NULL,
    pickup_location VARCHAR(255) NOT NULL,
    dropoff_location VARCHAR(255) NOT NULL,
    pickup_time TIMESTAMPTZ NOT NULL,
    price DECIMAL(10,2) NOT NULL DEFAULT 0,
    passengers INTEGER NOT NULL DEFAULT 1,
    status VARCHAR(50) NOT NULL DEFAULT 'confirmed',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT transfers_user_id_foreign FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS transfers_user_id_index ON transfers (user_id);
CREATE INDEX IF NOT EXISTS transfers_partner_id_index ON transfers (partner_id);

CREATE TABLE IF NOT EXISTS transfer_schedules (
    transfer_id BIGINT NOT NULL PRIMARY KEY,
    duration_minutes SMALLINT NOT NULL,
    CONSTRAINT transfer_schedules_transfer_id_foreign
        FOREIGN KEY (transfer_id) REFERENCES transfers(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS api_tokens (
    id BIGSERIAL PRIMARY KEY,
    user_id BIGINT NOT NULL,
    token_hash CHAR(64) NOT NULL UNIQUE,
    expires_at TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT api_tokens_user_id_foreign FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS api_tokens_user_id_index ON api_tokens (user_id);