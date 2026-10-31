CREATE TABLE IF NOT EXISTS attraction_visit_counts (
    attraction_id VARCHAR(64) NOT NULL PRIMARY KEY,
    visit_count BIGINT NOT NULL DEFAULT 0 CHECK (visit_count >= 0),
    CONSTRAINT attraction_visit_counts_attraction_foreign
        FOREIGN KEY (attraction_id) REFERENCES tourist_monuments(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS attraction_visit_dedup (
    attraction_id VARCHAR(64) NOT NULL,
    visitor_hash CHAR(64) NOT NULL,
    counted_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (attraction_id, visitor_hash),
    CONSTRAINT attraction_visit_dedup_attraction_foreign
        FOREIGN KEY (attraction_id) REFERENCES tourist_monuments(id) ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS attraction_visit_dedup_counted_at_index
    ON attraction_visit_dedup (counted_at);
