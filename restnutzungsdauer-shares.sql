-- ============================================================
--  hanRND – Pro-Objekt-Freigabe (Patch)
--  Run in Supabase SQL Editor AFTER restnutzungsdauer-setup.sql
--  und restnutzungsdauer-admin.sql. Idempotent – mehrfach ausführbar.
-- ============================================================

-- ─────────────────────────────────────────────────────────────
-- 0. Admin-Helfer (kapselt den JWT-Rollen-Check)
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.is_admin()
RETURNS BOOLEAN LANGUAGE sql STABLE AS $$
  SELECT COALESCE(
    (auth.jwt() -> 'app_metadata' ->> 'role') = 'admin', false
  );
$$;

-- ─────────────────────────────────────────────────────────────
-- 1. Tabelle immobilien_shares
-- ─────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.immobilien_shares (
  id                   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  immobilie_id         UUID NOT NULL REFERENCES public.immobilien(id) ON DELETE CASCADE,
  invited_email        TEXT NOT NULL,
  shared_with_user_id  UUID REFERENCES auth.users(id) ON DELETE CASCADE,
  permission           TEXT NOT NULL DEFAULT 'view' CHECK (permission IN ('view','edit')),
  shared_by            UUID NOT NULL REFERENCES auth.users(id),
  created_at           TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (immobilie_id, invited_email)
);

CREATE INDEX IF NOT EXISTS idx_shares_user  ON public.immobilien_shares(shared_with_user_id);
CREATE INDEX IF NOT EXISTS idx_shares_email ON public.immobilien_shares(lower(invited_email));
CREATE INDEX IF NOT EXISTS idx_shares_obj   ON public.immobilien_shares(immobilie_id);

-- ─────────────────────────────────────────────────────────────
-- 2. Pending-Einladung → Auto-Aktivierung bei Registrierung
--    (erweitert den bestehenden handle_new_user-Trigger)
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  INSERT INTO public.profiles (id, email)
  VALUES (NEW.id, NEW.email)
  ON CONFLICT (id) DO NOTHING;

  -- Offene Freigaben an diese E-Mail dem neuen Konto zuordnen
  UPDATE public.immobilien_shares
     SET shared_with_user_id = NEW.id
   WHERE lower(invited_email) = lower(NEW.email)
     AND shared_with_user_id IS NULL;

  RETURN NEW;
END;
$$;

-- Trigger neu setzen (falls schon vorhanden, ersetzt DROP+CREATE ihn sauber)
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- ─────────────────────────────────────────────────────────────
-- 3. Zugriffs-Helfer (SECURITY DEFINER → lösen KEINE RLS aus,
--    verhindern damit die gegenseitige Policy-Rekursion)
-- ─────────────────────────────────────────────────────────────
-- Hat der aktuelle User Zugriff auf ein Objekt? p_need = 'view' | 'edit'
CREATE OR REPLACE FUNCTION public.has_immobilie_access(p_obj UUID, p_need TEXT)
RETURNS BOOLEAN LANGUAGE sql SECURITY DEFINER STABLE AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.immobilien_shares s
    WHERE s.immobilie_id = p_obj
      AND s.shared_with_user_id = auth.uid()
      AND (p_need = 'view' OR s.permission = 'edit')
  );
$$;

-- Hat der aktuelle User über irgendein freigegebenes Objekt Zugriff auf
-- diesen Auftraggeber? p_need = 'view' | 'edit'
CREATE OR REPLACE FUNCTION public.has_auftraggeber_access(p_ag UUID, p_need TEXT)
RETURNS BOOLEAN LANGUAGE sql SECURITY DEFINER STABLE AS $$
  SELECT EXISTS (
    SELECT 1
      FROM public.immobilien i
      JOIN public.immobilien_shares s ON s.immobilie_id = i.id
     WHERE i.auftraggeber_id = p_ag
       AND s.shared_with_user_id = auth.uid()
       AND (p_need = 'view' OR s.permission = 'edit')
  );
$$;

-- ─────────────────────────────────────────────────────────────
-- 4. RLS immobilien – Freigabe-Zweig ergänzen
-- ─────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS "immobilien_select_own" ON public.immobilien;
CREATE POLICY "immobilien_select_own" ON public.immobilien
  FOR SELECT USING (
    auth.uid() = user_id
    OR public.is_admin()
    OR public.has_immobilie_access(id, 'view')
  );

DROP POLICY IF EXISTS "immobilien_update_own" ON public.immobilien;
CREATE POLICY "immobilien_update_own" ON public.immobilien
  FOR UPDATE USING (
    auth.uid() = user_id
    OR public.is_admin()
    OR public.has_immobilie_access(id, 'edit')
  );
-- INSERT/DELETE bleiben Eigentümer/Admin (Sharees legen nicht an / löschen nicht).
-- Die bestehenden immobilien_insert_own / immobilien_delete_own aus admin.sql gelten weiter.

-- ─────────────────────────────────────────────────────────────
-- 5. RLS auftraggeber – Freigabe-Zweig (view sichtbar, edit änderbar)
-- ─────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS "auftraggeber_select_own" ON public.auftraggeber;
CREATE POLICY "auftraggeber_select_own" ON public.auftraggeber
  FOR SELECT USING (
    auth.uid() = user_id
    OR public.is_admin()
    OR public.has_auftraggeber_access(id, 'view')
  );

DROP POLICY IF EXISTS "auftraggeber_update_own" ON public.auftraggeber;
CREATE POLICY "auftraggeber_update_own" ON public.auftraggeber
  FOR UPDATE USING (
    auth.uid() = user_id
    OR public.is_admin()
    OR public.has_auftraggeber_access(id, 'edit')
  );

-- ─────────────────────────────────────────────────────────────
-- 6. RLS immobilien_media – über Eltern-Objekt
-- ─────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS "media_select_own" ON public.immobilien_media;
CREATE POLICY "media_select_own" ON public.immobilien_media
  FOR SELECT USING (
    auth.uid() = user_id
    OR public.is_admin()
    OR public.has_immobilie_access(immobilie_id, 'view')
  );

DROP POLICY IF EXISTS "media_insert_own" ON public.immobilien_media;
CREATE POLICY "media_insert_own" ON public.immobilien_media
  FOR INSERT WITH CHECK (
    auth.uid() = user_id
    OR public.is_admin()
    OR public.has_immobilie_access(immobilie_id, 'edit')
  );

DROP POLICY IF EXISTS "media_update_own" ON public.immobilien_media;
CREATE POLICY "media_update_own" ON public.immobilien_media
  FOR UPDATE USING (
    auth.uid() = user_id
    OR public.is_admin()
    OR public.has_immobilie_access(immobilie_id, 'edit')
  );

DROP POLICY IF EXISTS "media_delete_own" ON public.immobilien_media;
CREATE POLICY "media_delete_own" ON public.immobilien_media
  FOR DELETE USING (
    auth.uid() = user_id
    OR public.is_admin()
    OR public.has_immobilie_access(immobilie_id, 'edit')
  );

-- ─────────────────────────────────────────────────────────────
-- 7. RLS immobilien_shares (die Freigabe-Zeilen selbst)
--    SELECT: Sharer (shared_by), Sharee (shared_with_user_id), Admin.
--    Kein Join auf immobilien → keine Rekursion.
--    Direkte Schreibzugriffe verweigert – nur über die RPCs (Punkt 8).
-- ─────────────────────────────────────────────────────────────
ALTER TABLE public.immobilien_shares ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "shares_select" ON public.immobilien_shares;
CREATE POLICY "shares_select" ON public.immobilien_shares
  FOR SELECT USING (
    shared_by = auth.uid()
    OR shared_with_user_id = auth.uid()
    OR public.is_admin()
  );
-- Bewusst KEINE INSERT/UPDATE/DELETE-Policy → direkte Client-Schreibzugriffe
-- schlagen fehl; Verwaltung läuft ausschließlich über die SECURITY-DEFINER-RPCs.

-- ─────────────────────────────────────────────────────────────
-- 8. RPCs zur Freigabe-Verwaltung (prüfen Eigentümerschaft selbst)
-- ─────────────────────────────────────────────────────────────
-- Internes Guard: darf der Aufrufer dieses Objekt teilen?
CREATE OR REPLACE FUNCTION public._may_manage_share(p_obj UUID)
RETURNS BOOLEAN LANGUAGE sql SECURITY DEFINER STABLE AS $$
  SELECT public.is_admin()
      OR EXISTS (SELECT 1 FROM public.immobilien i
                  WHERE i.id = p_obj AND i.user_id = auth.uid());
$$;

-- Freigeben / Stufe aktualisieren (UPSERT)
CREATE OR REPLACE FUNCTION public.share_immobilie(p_obj UUID, p_email TEXT, p_perm TEXT)
RETURNS public.immobilien_shares
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_email TEXT := lower(trim(p_email));
  v_uid   UUID;
  v_row   public.immobilien_shares;
BEGIN
  IF NOT public._may_manage_share(p_obj) THEN
    RAISE EXCEPTION 'Keine Berechtigung, dieses Objekt zu teilen';
  END IF;
  IF p_perm NOT IN ('view','edit') THEN
    RAISE EXCEPTION 'Ungültige Berechtigungsstufe: %', p_perm;
  END IF;
  IF v_email IS NULL OR v_email = '' OR position('@' in v_email) = 0 THEN
    RAISE EXCEPTION 'Ungültige E-Mail-Adresse';
  END IF;

  SELECT id INTO v_uid FROM auth.users WHERE lower(email) = v_email;

  INSERT INTO public.immobilien_shares
    (immobilie_id, invited_email, shared_with_user_id, permission, shared_by)
  VALUES (p_obj, v_email, v_uid, p_perm, auth.uid())
  ON CONFLICT (immobilie_id, invited_email) DO UPDATE
    SET permission          = EXCLUDED.permission,
        shared_with_user_id = COALESCE(EXCLUDED.shared_with_user_id,
                                       public.immobilien_shares.shared_with_user_id)
  RETURNING * INTO v_row;

  RETURN v_row;
END;
$$;

-- Freigaben eines Objekts auflisten (mit Status)
CREATE OR REPLACE FUNCTION public.list_shares(p_obj UUID)
RETURNS TABLE (
  id UUID, invited_email TEXT, permission TEXT, status TEXT, created_at TIMESTAMPTZ
)
LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  IF NOT public._may_manage_share(p_obj) THEN
    RAISE EXCEPTION 'Keine Berechtigung';
  END IF;
  RETURN QUERY
    SELECT s.id, s.invited_email, s.permission,
           CASE WHEN s.shared_with_user_id IS NULL THEN 'eingeladen' ELSE 'aktiv' END,
           s.created_at
      FROM public.immobilien_shares s
     WHERE s.immobilie_id = p_obj
     ORDER BY s.created_at;
END;
$$;

-- Stufe einer Freigabe ändern
CREATE OR REPLACE FUNCTION public.update_share(p_id UUID, p_perm TEXT)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE v_obj UUID;
BEGIN
  SELECT immobilie_id INTO v_obj FROM public.immobilien_shares WHERE id = p_id;
  IF v_obj IS NULL THEN RAISE EXCEPTION 'Freigabe nicht gefunden'; END IF;
  IF NOT public._may_manage_share(v_obj) THEN RAISE EXCEPTION 'Keine Berechtigung'; END IF;
  IF p_perm NOT IN ('view','edit') THEN RAISE EXCEPTION 'Ungültige Berechtigungsstufe'; END IF;
  UPDATE public.immobilien_shares SET permission = p_perm WHERE id = p_id;
END;
$$;

-- Freigabe widerrufen
CREATE OR REPLACE FUNCTION public.revoke_share(p_id UUID)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE v_obj UUID;
BEGIN
  SELECT immobilie_id INTO v_obj FROM public.immobilien_shares WHERE id = p_id;
  IF v_obj IS NULL THEN RETURN; END IF;
  IF NOT public._may_manage_share(v_obj) THEN RAISE EXCEPTION 'Keine Berechtigung'; END IF;
  DELETE FROM public.immobilien_shares WHERE id = p_id;
END;
$$;

-- Ausführungsrechte
GRANT EXECUTE ON FUNCTION public.share_immobilie(UUID,TEXT,TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.list_shares(UUID)              TO authenticated;
GRANT EXECUTE ON FUNCTION public.update_share(UUID,TEXT)        TO authenticated;
GRANT EXECUTE ON FUNCTION public.revoke_share(UUID)            TO authenticated;

-- ─────────────────────────────────────────────────────────────
-- 9. Storage: Sharee mit 'edit' darf auch fremde Fotos des Objekts löschen
--    Pfad-Konvention: ${uploader_uid}/${immobilie_id}/${datei}
--    → foldername[2] = immobilie_id
-- ─────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS "share_delete_edit" ON storage.objects;
CREATE POLICY "share_delete_edit" ON storage.objects
  FOR DELETE TO authenticated USING (
    bucket_id = 'immobilien-media'
    AND array_length(storage.foldername(name), 1) >= 2
    AND public.has_immobilie_access(
          NULLIF((storage.foldername(name))[2], '')::uuid, 'edit')
  );

-- Optional (nur nötig, falls der Bucket später NICHT mehr public ist):
-- DROP POLICY IF EXISTS "share_select_view" ON storage.objects;
-- CREATE POLICY "share_select_view" ON storage.objects
--   FOR SELECT TO authenticated USING (
--     bucket_id = 'immobilien-media'
--     AND array_length(storage.foldername(name), 1) >= 2
--     AND public.has_immobilie_access(
--           NULLIF((storage.foldername(name))[2], '')::uuid, 'view')
--   );
