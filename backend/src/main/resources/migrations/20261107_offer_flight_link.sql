BEGIN;

ALTER TABLE public.offers
    ADD COLUMN IF NOT EXISTS flight_listing_id BIGINT NULL;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'offers_flight_listing_id_foreign'
          AND conrelid = 'public.offers'::regclass
    ) THEN
        ALTER TABLE public.offers
            ADD CONSTRAINT offers_flight_listing_id_foreign
            FOREIGN KEY (flight_listing_id)
            REFERENCES public.partner_listings(id)
            ON DELETE SET NULL;
    END IF;
END;
$$;

CREATE INDEX IF NOT EXISTS offers_flight_listing_index
    ON public.offers (flight_listing_id);

ALTER TABLE public.offers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.offer_catalog_metadata ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON public.offers, public.offer_catalog_metadata
    FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT, UPDATE ON public.offers TO zentrip_api_runtime;
GRANT SELECT, INSERT, UPDATE ON public.offer_catalog_metadata
    TO zentrip_api_runtime;

DROP POLICY IF EXISTS offers_public_active_read ON public.offers;
CREATE POLICY offers_public_active_read
    ON public.offers FOR SELECT TO zentrip_api_runtime
    USING (is_active = TRUE);

DROP POLICY IF EXISTS offers_admin_insert ON public.offers;
CREATE POLICY offers_admin_insert
    ON public.offers FOR INSERT TO zentrip_api_runtime
    WITH CHECK (public.zentrip_rls_role() = 'admin');

DROP POLICY IF EXISTS offers_admin_update ON public.offers;
CREATE POLICY offers_admin_update
    ON public.offers FOR UPDATE TO zentrip_api_runtime
    USING (public.zentrip_rls_role() = 'admin')
    WITH CHECK (public.zentrip_rls_role() = 'admin');

DROP POLICY IF EXISTS offer_catalog_metadata_public_read
    ON public.offer_catalog_metadata;
CREATE POLICY offer_catalog_metadata_public_read
    ON public.offer_catalog_metadata FOR SELECT TO zentrip_api_runtime
    USING (EXISTS (
        SELECT 1 FROM public.offers o
        WHERE o.id = offer_id AND o.is_active = TRUE
    ));

DROP POLICY IF EXISTS offer_catalog_metadata_admin_write
    ON public.offer_catalog_metadata;
CREATE POLICY offer_catalog_metadata_admin_write
    ON public.offer_catalog_metadata FOR ALL TO zentrip_api_runtime
    USING (public.zentrip_rls_role() = 'admin')
    WITH CHECK (public.zentrip_rls_role() = 'admin');

INSERT INTO public.schema_migrations (version, name)
VALUES ('20261107_offer_flight_link', 'offer_flight_link')
ON CONFLICT (version) DO NOTHING;

COMMIT;
