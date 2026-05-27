-- ============================================================
--  Restnutzungsdauer (hanRND) – Supabase SQL Schema
--  Run this in Supabase SQL Editor
-- ============================================================

-- ─────────────────────────────────────────────────────────────
-- 0. Helper: updated_at trigger function
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

-- ─────────────────────────────────────────────────────────────
-- 1. auftraggeber – Client / order-giver table
-- ─────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.auftraggeber (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,

  vorname     TEXT NOT NULL DEFAULT '',
  nachname    TEXT NOT NULL DEFAULT '',
  strasse     TEXT NOT NULL DEFAULT '',
  hausnummer  TEXT NOT NULL DEFAULT '',
  plz         TEXT NOT NULL DEFAULT '',
  ort         TEXT NOT NULL DEFAULT '',
  mobil       TEXT NOT NULL DEFAULT '',
  email       TEXT NOT NULL DEFAULT '',

  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TRIGGER auftraggeber_updated_at
  BEFORE UPDATE ON public.auftraggeber
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- ─────────────────────────────────────────────────────────────
-- 2. immobilien – Property / real-estate records
--    Mirrors every section of the BeMa Antragsformular
-- ─────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.immobilien (
  id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id                 UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,

  -- Meta
  bezeichnung             TEXT NOT NULL DEFAULT '',
  notizen                 TEXT NOT NULL DEFAULT '',

  -- Property address
  strasse                 TEXT NOT NULL DEFAULT '',
  hausnummer              TEXT NOT NULL DEFAULT '',
  wohnungsnummer          TEXT NOT NULL DEFAULT '',
  plz                     TEXT NOT NULL DEFAULT '',
  ort                     TEXT NOT NULL DEFAULT '',

  -- Auftraggeber FK
  auftraggeber_id         UUID REFERENCES public.auftraggeber(id) ON DELETE SET NULL,

  -- ── Abschnitt 1: Art der Immobilie & Basisinfos ──────────────
  art_immobilie           TEXT NOT NULL DEFAULT '',        -- ETW | EFH | MFH | ...
  art_kommentar           TEXT NOT NULL DEFAULT '',
  baujahr                 INT,
  wohnflaeche             NUMERIC(10,2),
  nutzungseinheiten       INT,
  geschossanzahl          INT,
  stellplaetze            INT,
  nebengebaeude           TEXT NOT NULL DEFAULT '',

  -- ── Abschnitt 2: Bauweise & Ausstattung ─────────────────────
  -- 2.1 Bauweise
  bauweise                TEXT NOT NULL DEFAULT '',        -- Massiv | Holzständer | ...
  bauweise_kommentar      TEXT NOT NULL DEFAULT '',

  -- 2.2 Bäder
  baeder                  TEXT NOT NULL DEFAULT '',        -- Einfach | Normal | Gehoben | Luxus

  -- 2.3 Dachart (multiple possible → array)
  dachart                 TEXT[] NOT NULL DEFAULT '{}',   -- Flachdach | Satteldach | ...
  dachart_kommentar       TEXT NOT NULL DEFAULT '',

  -- 2.4 Verglasung / Fenster
  verglasung              TEXT NOT NULL DEFAULT '',        -- Einfach | 2-fach | 3-fach
  fenster_kommentar       TEXT NOT NULL DEFAULT '',

  -- 2.5 Heizung (multiple → array)
  heizung                 TEXT[] NOT NULL DEFAULT '{}',
  heizung_kommentar       TEXT NOT NULL DEFAULT '',

  -- 2.6 Keller
  keller                  TEXT NOT NULL DEFAULT '',        -- Kein Keller | Teilkeller | Vollkeller
  keller_kommentar        TEXT NOT NULL DEFAULT '',

  -- ── Abschnitt 3: Modernisierungen (JSONB per category) ───────
  -- Each JSONB object has shape:
  --   { period: 'nicht'|'letzte5'|'vor5_10'|'vor10_15'|'vor15_20'|'mehr20', anteil: number|null }
  mod_dach                JSONB,
  mod_fenster             JSONB,
  mod_leitungen           JSONB,
  mod_heizung_anlage      JSONB,
  mod_waermedaemmung      JSONB,
  mod_baeder              JSONB,
  mod_innenausbau         JSONB,
  -- 3.8 Grundriss (radio, 5 options)
  grundriss               TEXT NOT NULL DEFAULT '',

  -- ── Abschnitt 4: Unterlagen ──────────────────────────────────
  unterlagen_bilder       BOOLEAN NOT NULL DEFAULT FALSE,
  unterlagen_grundrisse   BOOLEAN NOT NULL DEFAULT FALSE,
  unterlagen_energieausweis BOOLEAN NOT NULL DEFAULT FALSE,
  unterlagen_lageplan     BOOLEAN NOT NULL DEFAULT FALSE,

  -- ── Abschnitt 5: Stichtag ────────────────────────────────────
  stichtag                DATE,

  -- ── Abschnitt 6: Eigentümer (falls abweichend) ───────────────
  eigentuemer_abweichend  BOOLEAN NOT NULL DEFAULT FALSE,
  eigentuemer_name        TEXT NOT NULL DEFAULT '',
  eigentuemer_strasse     TEXT NOT NULL DEFAULT '',
  eigentuemer_hausnummer  TEXT NOT NULL DEFAULT '',
  eigentuemer_plz         TEXT NOT NULL DEFAULT '',
  eigentuemer_ort         TEXT NOT NULL DEFAULT '',

  -- ── Abschnitt 7: Rechnungsempfänger (falls abweichend) ───────
  rechnung_abweichend     BOOLEAN NOT NULL DEFAULT FALSE,
  rechnung_name           TEXT NOT NULL DEFAULT '',
  rechnung_strasse        TEXT NOT NULL DEFAULT '',
  rechnung_hausnummer     TEXT NOT NULL DEFAULT '',
  rechnung_plz            TEXT NOT NULL DEFAULT '',
  rechnung_ort            TEXT NOT NULL DEFAULT '',

  -- ── Gutachten-Typ & Besichtigung ─────────────────────────────
  gutachten_typ           TEXT NOT NULL DEFAULT '',        -- 'ETW_270' | 'MFH_EFH_470' | 'VOR_ORT'
  vor_ort_besichtigung    BOOLEAN NOT NULL DEFAULT FALSE,

  created_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at              TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TRIGGER immobilien_updated_at
  BEFORE UPDATE ON public.immobilien
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- ─────────────────────────────────────────────────────────────
-- 3. immobilien_media – Photos and video URLs per property
-- ─────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.immobilien_media (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  immobilie_id  UUID NOT NULL REFERENCES public.immobilien(id) ON DELETE CASCADE,
  user_id       UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,

  typ           TEXT NOT NULL CHECK (typ IN ('foto', 'video_url')),
  dateiname     TEXT NOT NULL DEFAULT '',
  storage_path  TEXT NOT NULL DEFAULT '',   -- path in Supabase Storage bucket
  url           TEXT NOT NULL DEFAULT '',   -- public URL or video URL
  beschreibung  TEXT NOT NULL DEFAULT '',

  created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ─────────────────────────────────────────────────────────────
-- 4. Row-Level Security (RLS)
-- ─────────────────────────────────────────────────────────────

-- auftraggeber
ALTER TABLE public.auftraggeber ENABLE ROW LEVEL SECURITY;

CREATE POLICY "auftraggeber_select_own" ON public.auftraggeber
  FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "auftraggeber_insert_own" ON public.auftraggeber
  FOR INSERT WITH CHECK (auth.uid() = user_id);

CREATE POLICY "auftraggeber_update_own" ON public.auftraggeber
  FOR UPDATE USING (auth.uid() = user_id);

CREATE POLICY "auftraggeber_delete_own" ON public.auftraggeber
  FOR DELETE USING (auth.uid() = user_id);

-- immobilien
ALTER TABLE public.immobilien ENABLE ROW LEVEL SECURITY;

CREATE POLICY "immobilien_select_own" ON public.immobilien
  FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "immobilien_insert_own" ON public.immobilien
  FOR INSERT WITH CHECK (auth.uid() = user_id);

CREATE POLICY "immobilien_update_own" ON public.immobilien
  FOR UPDATE USING (auth.uid() = user_id);

CREATE POLICY "immobilien_delete_own" ON public.immobilien
  FOR DELETE USING (auth.uid() = user_id);

-- immobilien_media
ALTER TABLE public.immobilien_media ENABLE ROW LEVEL SECURITY;

CREATE POLICY "media_select_own" ON public.immobilien_media
  FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "media_insert_own" ON public.immobilien_media
  FOR INSERT WITH CHECK (auth.uid() = user_id);

CREATE POLICY "media_update_own" ON public.immobilien_media
  FOR UPDATE USING (auth.uid() = user_id);

CREATE POLICY "media_delete_own" ON public.immobilien_media
  FOR DELETE USING (auth.uid() = user_id);

-- ─────────────────────────────────────────────────────────────
-- 5. Storage bucket (create manually in Supabase Dashboard)
-- ─────────────────────────────────────────────────────────────
-- NOTE: Supabase Storage buckets cannot be created via SQL.
-- Please create the bucket manually:
--
--   Dashboard → Storage → New bucket
--   Name:   immobilien-media
--   Public: TRUE  (public bucket – required so uploaded images can be displayed)
--
-- Then add storage policies so authenticated users can manage
-- their own files.  Run these in the SQL Editor:

INSERT INTO storage.buckets (id, name, public)
VALUES ('immobilien-media', 'immobilien-media', true)
ON CONFLICT (id) DO UPDATE SET public = true;

-- Allow authenticated users to upload into their own folder
CREATE POLICY "auth_upload_own" ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (
    bucket_id = 'immobilien-media'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );

-- Allow authenticated users to read/download their own files
CREATE POLICY "auth_select_own" ON storage.objects
  FOR SELECT TO authenticated
  USING (
    bucket_id = 'immobilien-media'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );

-- Allow authenticated users to delete their own files
CREATE POLICY "auth_delete_own" ON storage.objects
  FOR DELETE TO authenticated
  USING (
    bucket_id = 'immobilien-media'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );

-- Storage path convention used by this app:
--   immobilien-media/{user_id}/{immobilie_id}/{filename}
-- ─────────────────────────────────────────────────────────────
