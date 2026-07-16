# Spezifikation: Pro-Objekt-Freigabe (hanRND)

Stand: 2026-07-16 · App: `restnutzungsdauer.html` (Single-File, Supabase-Auth+DB+Storage)

## Ziel
Ein Eigentümer (oder Admin) kann **eine einzelne Immobilie** gezielt für eine andere
Person freigeben — pro Freigabe wählbar als **Ansehen** oder **Bearbeiten**. Die
freigegebene Person sieht **nur die freigegebenen Objekte**, nicht den restlichen
Bestand. Freigabe funktioniert auch für E-Mail-Adressen **ohne bestehendes Konto**
(Pending-Einladung, aktiviert sich bei Registrierung).

## Entscheidungen (vom Nutzer bestätigt 2026-07-16)
1. **Berechtigung:** pro Freigabe wählbar — `view` oder `edit`.
2. **Auftraggeber des Objekts:** bei `edit` **mitbearbeitbar** (nicht nur sichtbar).
3. **Identifikation:** per E-Mail; **Einladung auch an Konto-lose** Adressen möglich.
4. **Kein E-Mail-Versand** der Einladung — die Person weiß Bescheid und registriert
   sich selbst. (Mailer optional als spätere Erweiterung.)
5. **Objekt löschen → Freigaben kaskadieren mit** (ON DELETE CASCADE).
6. Sharees können **nicht weiter-teilen** (nur Eigentümer/Admin).

## Architektur-Grundsatz
Zugriff wird **serverseitig per RLS** entschieden. Die App fragt weiter `select('*')`;
Postgres liefert genau die erlaubten Zeilen. Frontend-Abfragen für Immobilien/
Auftraggeber/Medien bleiben unverändert — nur UI (Teilen-Dialog, Badges) kommt hinzu.

---

## 1. Datenmodell

### Neue Tabelle `public.immobilien_shares`
| Spalte | Typ | Constraints |
|---|---|---|
| `id` | UUID | PK, default `gen_random_uuid()` |
| `immobilie_id` | UUID | NOT NULL, FK → `immobilien(id)` **ON DELETE CASCADE** |
| `invited_email` | TEXT | NOT NULL, immer lowercase gespeichert |
| `shared_with_user_id` | UUID | NULL, FK → `auth.users(id)` ON DELETE CASCADE |
| `permission` | TEXT | NOT NULL, CHECK in (`'view'`,`'edit'`) |
| `shared_by` | UUID | NOT NULL, FK → `auth.users(id)` |
| `created_at` | TIMESTAMPTZ | NOT NULL default `now()` |

- **UNIQUE** `(immobilie_id, invited_email)` — keine Doppel-Freigaben.
- Index auf `shared_with_user_id` und auf `invited_email` (Trigger-Lookup).

### Pending-Einladung → Auto-Aktivierung
Bestehende Funktion `handle_new_user()` (SECURITY DEFINER, feuert bei Registrierung)
wird erweitert:
```sql
UPDATE public.immobilien_shares
   SET shared_with_user_id = NEW.id
 WHERE lower(invited_email) = lower(NEW.email)
   AND shared_with_user_id IS NULL;
```
Damit greift jede vorher ausgesprochene Freigabe automatisch, sobald die Person ein
Konto anlegt.

---

## 2. Zugriffslogik (RLS) — rekursionssicher

**Problem:** Würde die `immobilien`-Policy direkt auf `immobilien_shares` joinen und die
`immobilien_shares`-Policy zurück auf `immobilien`, entsteht gegenseitige RLS-Rekursion.

**Lösung:** eine `SECURITY DEFINER`-Hilfsfunktion, die die Freigabe prüft, **ohne**
selbst RLS auszulösen:
```sql
CREATE OR REPLACE FUNCTION public.has_immobilie_access(p_obj UUID, p_need TEXT)
RETURNS BOOLEAN LANGUAGE sql SECURITY DEFINER STABLE AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.immobilien_shares s
    WHERE s.immobilie_id = p_obj
      AND s.shared_with_user_id = auth.uid()
      AND (p_need = 'view' OR s.permission = 'edit')
  );
$$;
```
`p_need='view'` → jede Freigabe reicht; `p_need='edit'` → nur `edit`-Freigaben.

### Policies (jeweils zusätzlich zu Eigentümer- und Admin-Zweig)
- **immobilien**
  - SELECT: `auth.uid()=user_id OR is_admin() OR has_immobilie_access(id,'view')`
  - UPDATE: `… OR has_immobilie_access(id,'edit')`
  - INSERT/DELETE: unverändert (nur Eigentümer/Admin — Sharees legen nicht an/löschen nicht)
- **auftraggeber** (Objekt verweist per `auftraggeber_id`)
  - SELECT: sichtbar, wenn ein `view`-oder-`edit`-freigegebenes Objekt darauf verweist
  - UPDATE: änderbar, wenn ein `edit`-freigegebenes Objekt darauf verweist
  - Umsetzung über Schwester-Helfer `has_auftraggeber_access(p_ag, p_need)` (SECURITY
    DEFINER), der `immobilien` × `immobilien_shares` joint.
- **immobilien_media** (`immobilie_id` → Eltern-Objekt)
  - SELECT: `… OR has_immobilie_access(immobilie_id,'view')`
  - INSERT/UPDATE/DELETE: `… OR has_immobilie_access(immobilie_id,'edit')`
- **immobilien_shares** (die Freigabe-Zeilen selbst)
  - SELECT: sichtbar für Objekt-Eigentümer, Admin und die eingeladene Person
    (`shared_with_user_id = auth.uid()`).
  - INSERT/UPDATE/DELETE: **nicht** direkt vom Client — ausschließlich über die RPCs
    unten (Policies verweigern direkten Schreibzugriff; RPCs sind SECURITY DEFINER).

`is_admin()` kapselt den bestehenden Check `(auth.jwt()->'app_metadata'->>'role')='admin'`.

---

## 3. Freigabe-Verwaltung (RPC, SECURITY DEFINER)
Grund: Ein Client darf E-Mails/IDs anderer Nutzer **nicht** frei aus der DB lesen.
Die RPCs prüfen selbst, ob der Aufrufer Eigentümer/Admin des Objekts ist.

- `share_immobilie(p_obj UUID, p_email TEXT, p_perm TEXT) RETURNS immobilien_shares`
  - Prüft: Aufrufer = Eigentümer von `p_obj` **oder** Admin, sonst `RAISE EXCEPTION`.
  - Normalisiert E-Mail (lower/trim), validiert `p_perm`.
  - Sucht bestehendes Konto in `auth.users` → setzt `shared_with_user_id` sofort,
    sonst NULL (pending).
  - UPSERT auf `(immobilie_id, invited_email)` — erneutes Teilen aktualisiert die Stufe.
- `list_shares(p_obj UUID) RETURNS TABLE(id, invited_email, permission, status, created_at)`
  - `status` = `'aktiv'` wenn `shared_with_user_id` gesetzt, sonst `'eingeladen'`.
  - Nur Eigentümer/Admin.
- `update_share(p_id UUID, p_perm TEXT)` — Stufe ändern; nur Eigentümer/Admin.
- `revoke_share(p_id UUID)` — Freigabe löschen; nur Eigentümer/Admin.

---

## 4. Storage (Fotos)
Pfad-Konvention: `${uploader_uid}/${immobilie_id}/${datei}`. Storage-Policies keyen auf
`foldername[1] = auth.uid()`.
- **Upload durch Sharee:** funktioniert unverändert (schreibt in eigenen Ordner).
- **Anzeige:** Bucket ist public → `getPublicUrl` zeigt Bilder ohne Auth. Unverändert.
- **Löschen fremder Fotos (Eigentümer-Uploads) durch Sharee:** von `auth_delete_own`
  blockiert. **Fix:** zusätzliche Delete-Policy, die den zweiten Pfadsegment als
  `immobilie_id` interpretiert und `has_immobilie_access(<seg2>::uuid,'edit')` prüft:
  ```sql
  CREATE POLICY "share_delete_edit" ON storage.objects
    FOR DELETE TO authenticated USING (
      bucket_id='immobilien-media'
      AND public.has_immobilie_access(((storage.foldername(name))[2])::uuid,'edit')
    );
  ```
  Analog optional eine SELECT-Policy, falls später nicht-public gestellt wird.

---

## 5. Frontend (`restnutzungsdauer.html`)
Kein Build-Schritt, kein Test-Framework — reine Inline-JS-Ergänzungen.

### Datenladung
- `loadShares()`: lädt eigene ausgesprochene + empfangene Freigaben (für Badges).
  Empfangene erkennt der Client an `user_id !== session.user.id` bei sichtbaren Objekten.
- Kein Query-Umbau bei `loadImmobilien`/`loadAuftraggeber`/`loadMedia` nötig.

### UI-Elemente
- **Teilen-Button** (Icon) in der Aktionsspalte der Dashboard-Tabelle und im Detail-
  Header. Nur sichtbar, wenn Aufrufer Eigentümer oder Admin des Objekts ist.
- **Teilen-Dialog** (Modal):
  - E-Mail-Feld + Stufen-Auswahl (Ansehen/Bearbeiten) + „Freigeben" → `share_immobilie`.
  - Liste bestehender Freigaben (`list_shares`) mit Status-Badge (`aktiv`/`eingeladen`),
    Stufen-Umschalter (`update_share`) und Entfernen (`revoke_share`).
  - Fehlerfälle als Toast (bestehende `toast()`-Infrastruktur).
- **Listen-Kennzeichnung:**
  - Objekt mir freigegeben → Badge „geteilt von …" (E-Mail des Eigentümers, sofern
    Admin-Profilzugriff; sonst neutrales „geteilt mit mir").
  - Objekt von mir geteilt → Badge „geteilt".
- **View-only-Erlebnis:** Bei `view`-Freigabe wird in Detail/Liste der Bearbeiten-Button
  für dieses Objekt ausgeblendet. (Zusätzlich hart durch RLS abgesichert — UI ist nur
  Komfort.)

### Nicht-Ziele (bewusst offen)
- Kein E-Mail-Versand.
- Kein Weiter-Teilen durch Sharees.
- Keine Team-/Gruppenfreigabe (nur 1:1 pro E-Mail).

---

## 6. Verifikation (statt klassischem TDD — hanDash hat kein Test-Framework)
1. **SQL-RLS-Checks** im Supabase-SQL-Editor mit `set role`/`request.jwt.claims`-
   Simulation: als Nicht-Sharee → 0 Zeilen; als view-Sharee → sichtbar aber UPDATE
   verweigert; als edit-Sharee → UPDATE ok; Auftraggeber/Media analog. Ein
   wiederholbares `docs/verify-freigabe.sql` liefert den Beweis.
2. **Pending→aktiv:** Freigabe an neue E-Mail, dann Registrierung → `shared_with_user_id`
   wird gesetzt, Objekt taucht auf.
3. **Cascade:** Objekt löschen → zugehörige `immobilien_shares` weg.
4. **UI-Smoke** (zwei Browser/zwei Konten): Teilen, Stufe wechseln, widerrufen; view =
   kein Bearbeiten-Button; edit = Wizard + Foto-Upload + Auftraggeber-Edit funktionieren.
5. **Regressions-Schnellcheck:** eigener Bestand unverändert; Admin sieht weiter alles.

## 7. Migrations-/Deploy-Hinweise
- **DB zuerst:** SQL-Patch (`restnutzungsdauer-shares.sql`) im Supabase-SQL-Editor
  ausführen **vor** dem Frontend-Deploy — sonst rufen neue UI-Buttons fehlende RPCs auf.
- SQL idempotent halten (`CREATE TABLE IF NOT EXISTS`, `DROP POLICY IF EXISTS` vor
  `CREATE POLICY`, `CREATE OR REPLACE FUNCTION`).
- Frontend-Deploy wie gehabt: Commit auf `master` → NUC-Poller (~60 s) → hartes Reload.
- **Reihenfolge nicht umdrehen** (Frontend ohne DB-Patch = Laufzeitfehler beim Teilen).
