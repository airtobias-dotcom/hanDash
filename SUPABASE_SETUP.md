# Supabase-Einrichtung für hanRND (Restnutzungsdauer)

Folge diesen Schritten, um das Modul einsatzbereit zu machen.

---

## Schritt 1 – Supabase-Account anlegen

1. Öffne [https://supabase.com](https://supabase.com) in deinem Browser.
2. Klicke auf **Start your project** und registriere dich (GitHub-Login empfohlen).

---

## Schritt 2 – Neues Projekt erstellen

1. Klicke im Dashboard auf **New project**.
2. Wähle eine Organisation (oder lege eine neue an).
3. Vergib einen Projektnamen, z. B. `handash-rnd`.
4. Wähle ein sicheres Datenbank-Passwort (merke dir dieses gut).
5. Wähle eine Region (empfohlen: **Frankfurt – eu-central-1**).
6. Klicke auf **Create new project** und warte, bis das Projekt bereit ist.

---

## Schritt 3 – SQL-Schema einrichten

1. Navigiere im linken Menü zu **SQL Editor**.
2. Klicke auf **+ New query**.
3. Öffne die Datei `restnutzungsdauer-setup.sql` aus diesem Repository.
4. Kopiere den gesamten Inhalt in den SQL-Editor.
5. Klicke auf **Run** (oder Strg+Enter).
6. Prüfe, dass keine Fehler angezeigt werden.

---

## Schritt 4 – Storage-Bucket anlegen

1. Navigiere im linken Menü zu **Storage**.
2. Klicke auf **New bucket**.
3. Name: `immobilien-media`
4. **Public bucket**: deaktiviert lassen (privat).
5. Klicke auf **Save**.
6. Öffne den neu erstellten Bucket und gehe zu **Policies**.
7. Klicke auf **New policy → For full customization**.
8. Erstelle folgende Policy:
   - **Policy name**: Users manage own media
   - **Allowed operations**: SELECT, INSERT, UPDATE, DELETE
   - **Target roles**: authenticated
   - **USING expression**:
     ```sql
     (auth.uid()::text = (storage.foldername(name))[1])
     ```
   - **WITH CHECK expression** (für INSERT):
     ```sql
     (auth.uid()::text = (storage.foldername(name))[1])
     ```

---

## Schritt 5 – API-Zugangsdaten herausfinden

1. Navigiere im linken Menü zu **Settings → API**.
2. Notiere dir:
   - **Project URL** (z. B. `https://xyzxyzxyz.supabase.co`)
   - **anon public** Key (unter *Project API keys*)

---

## Schritt 6 – Zugangsdaten in die App eintragen

1. Öffne die Datei `restnutzungsdauer.html` in einem Texteditor.
2. Suche oben in der `<script>`-Sektion nach:
   ```javascript
   const SUPABASE_URL = 'YOUR_SUPABASE_URL';
   const SUPABASE_ANON_KEY = 'YOUR_SUPABASE_ANON_KEY';
   ```
3. Ersetze die Platzhalter durch deine echten Werte:
   ```javascript
   const SUPABASE_URL = 'https://xyzxyzxyz.supabase.co';
   const SUPABASE_ANON_KEY = 'eyJhbGciOiJIUzI1NiIsInR5...';
   ```
4. Speichere die Datei.
5. Öffne `restnutzungsdauer.html` im Browser – der Setup-Hinweis verschwindet und der Login wird angezeigt.

---

## Fertig!

Du kannst dich jetzt mit deiner E-Mail-Adresse registrieren und mit der Erfassung von Restnutzungsdauer-Gutachten beginnen.

Fragen oder Probleme? Wende dich an den Entwickler.
