-- ============================================================
--  hanRND – Admin-Berechtigungssystem (Patch)
--  Run this in Supabase SQL Editor AFTER restnutzungsdauer-setup.sql
-- ============================================================

-- ─────────────────────────────────────────────────────────────
-- 1. profiles – minimale Tabelle user_id → email
--    Wird automatisch bei Registrierung befüllt
-- ─────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.profiles (
  id     UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  email  TEXT NOT NULL DEFAULT ''
);

-- Bestehende User eintragen
INSERT INTO public.profiles (id, email)
SELECT id, email FROM auth.users
ON CONFLICT (id) DO NOTHING;

-- Trigger: neue Registrierungen auto-eintragen
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  INSERT INTO public.profiles (id, email)
  VALUES (NEW.id, NEW.email)
  ON CONFLICT (id) DO NOTHING;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- RLS auf profiles
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

-- Admin sieht alle Profile (für E-Mail-Anzeige in der Liste)
CREATE POLICY "profiles_admin_select" ON public.profiles
  FOR SELECT USING (
    (auth.jwt() -> 'app_metadata' ->> 'role') = 'admin'
  );

-- Jeder User sieht sein eigenes Profil
CREATE POLICY "profiles_self_select" ON public.profiles
  FOR SELECT USING (auth.uid() = id);

-- ─────────────────────────────────────────────────────────────
-- 2. Admin-RLS für immobilien
-- ─────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS "immobilien_select_own" ON public.immobilien;
CREATE POLICY "immobilien_select_own" ON public.immobilien
  FOR SELECT USING (
    auth.uid() = user_id
    OR (auth.jwt() -> 'app_metadata' ->> 'role') = 'admin'
  );

DROP POLICY IF EXISTS "immobilien_update_own" ON public.immobilien;
CREATE POLICY "immobilien_update_own" ON public.immobilien
  FOR UPDATE USING (
    auth.uid() = user_id
    OR (auth.jwt() -> 'app_metadata' ->> 'role') = 'admin'
  );

DROP POLICY IF EXISTS "immobilien_delete_own" ON public.immobilien;
CREATE POLICY "immobilien_delete_own" ON public.immobilien
  FOR DELETE USING (
    auth.uid() = user_id
    OR (auth.jwt() -> 'app_metadata' ->> 'role') = 'admin'
  );

-- ─────────────────────────────────────────────────────────────
-- 3. Admin-RLS für auftraggeber
-- ─────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS "auftraggeber_select_own" ON public.auftraggeber;
CREATE POLICY "auftraggeber_select_own" ON public.auftraggeber
  FOR SELECT USING (
    auth.uid() = user_id
    OR (auth.jwt() -> 'app_metadata' ->> 'role') = 'admin'
  );

DROP POLICY IF EXISTS "auftraggeber_update_own" ON public.auftraggeber;
CREATE POLICY "auftraggeber_update_own" ON public.auftraggeber
  FOR UPDATE USING (
    auth.uid() = user_id
    OR (auth.jwt() -> 'app_metadata' ->> 'role') = 'admin'
  );

DROP POLICY IF EXISTS "auftraggeber_delete_own" ON public.auftraggeber;
CREATE POLICY "auftraggeber_delete_own" ON public.auftraggeber
  FOR DELETE USING (
    auth.uid() = user_id
    OR (auth.jwt() -> 'app_metadata' ->> 'role') = 'admin'
  );

-- ─────────────────────────────────────────────────────────────
-- 4. Admin-RLS für immobilien_media
-- ─────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS "media_select_own" ON public.immobilien_media;
CREATE POLICY "media_select_own" ON public.immobilien_media
  FOR SELECT USING (
    auth.uid() = user_id
    OR (auth.jwt() -> 'app_metadata' ->> 'role') = 'admin'
  );

DROP POLICY IF EXISTS "media_update_own" ON public.immobilien_media;
CREATE POLICY "media_update_own" ON public.immobilien_media
  FOR UPDATE USING (
    auth.uid() = user_id
    OR (auth.jwt() -> 'app_metadata' ->> 'role') = 'admin'
  );

DROP POLICY IF EXISTS "media_delete_own" ON public.immobilien_media;
CREATE POLICY "media_delete_own" ON public.immobilien_media
  FOR DELETE USING (
    auth.uid() = user_id
    OR (auth.jwt() -> 'app_metadata' ->> 'role') = 'admin'
  );

-- ─────────────────────────────────────────────────────────────
-- 5. Admin-Rolle setzen
--    Ersetze <USER_UUID> mit der UUID des Admin-Users aus:
--    Supabase Dashboard → Authentication → Users → UUID kopieren
-- ─────────────────────────────────────────────────────────────
-- UPDATE auth.users
-- SET raw_app_meta_data = raw_app_meta_data || '{"role": "admin"}'::jsonb
-- WHERE id = '<USER_UUID>';
