-- Read-only duplicate report. This deliberately contains no UPDATE or DELETE.
WITH candidate_pairs AS (
    SELECT
        a.id AS left_id,
        b.id AS right_id,
        a.provider_place_id AS left_provider_id,
        b.provider_place_id AS right_provider_id,
        a.wikidata_id AS left_wikidata_id,
        b.wikidata_id AS right_wikidata_id,
        a.payload ->> 'name' AS left_name,
        b.payload ->> 'name' AS right_name,
        a.city AS left_city,
        b.city AS right_city,
        CASE
            WHEN a.wikidata_id IS NOT NULL AND a.wikidata_id = b.wikidata_id
                THEN 0::double precision
            ELSE 6371000 * 2 * ASIN(SQRT(LEAST(1.0,
                POWER(SIN(RADIANS(b.latitude - a.latitude) / 2), 2)
                + COS(RADIANS(a.latitude)) * COS(RADIANS(b.latitude))
                * POWER(SIN(RADIANS(b.longitude - a.longitude) / 2), 2)
            )))
        END AS distance_meters
    FROM public.landmark_places a
    JOIN public.landmark_places b
      ON a.id < b.id
     AND a.canonical_place_id IS NULL
     AND b.canonical_place_id IS NULL
     AND (
        (a.wikidata_id IS NOT NULL AND a.wikidata_id = b.wikidata_id)
        OR (
            b.latitude BETWEEN a.latitude - 0.003 AND a.latitude + 0.003
            AND b.longitude BETWEEN a.longitude - 0.004 AND a.longitude + 0.004
        )
     )
)
SELECT left_id, right_id, left_provider_id, right_provider_id,
       left_wikidata_id, right_wikidata_id, left_name, right_name,
       left_city, right_city, ROUND(distance_meters::numeric, 1) AS distance_meters,
       CASE
           WHEN left_wikidata_id IS NOT NULL
                AND left_wikidata_id = right_wikidata_id
             THEN 'shared Wikidata identifier'
           WHEN distance_meters < 50 THEN 'under 50 m; automatic identity candidate'
           ELSE '50-300 m; manual identity review'
       END AS audit_reason
FROM candidate_pairs
WHERE distance_meters <= 300
ORDER BY CASE
           WHEN left_wikidata_id IS NOT NULL
                AND left_wikidata_id = right_wikidata_id THEN 0
           ELSE 1
         END,
         distance_meters
LIMIT 500;
