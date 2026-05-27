# hanDash – Projektdokumentation für Claude

Letzte Session: 2026-05-27
Branch: `claude/nice-noether-FwWXS` (noch nicht in `master` gemergt)
Deployed auf: `/home/tobias/hanDash` via `git pull`

---

## Projekt-Übersicht

**hanDash** ist ein internes Tool-Dashboard für "have a nice stay" (Ferienwohnungsvermietung).
Es besteht aus statischen HTML/CSS/JS-Seiten, die per nginx auf einem lokalen NUC-Server gehostet werden.
Kein Build-Prozess. Deploy = `git pull` auf dem NUC.

### Dateien
```
/home/tobias/hanDash/
├── index.html                    # Haupt-Dashboard (Kachelübersicht aller Tools)
├── tools.html                    # Tool-Sammlung
├── restnutzungsdauer.html        # hanRND – NEU (diese Session)
├── restnutzungsdauer-setup.sql   # Supabase DB-Schema – NEU
├── SUPABASE_SETUP.md             # Einrichtungsanleitung – NEU
└── deploy/
    ├── handash-nginx.conf
    └── install.sh
```

### Deploy-Mechanismus
```bash
# Manuell auf dem NUC:
cd /home/tobias/hanDash && git pull origin <branch> --rebase

# Automatisch (cron, jede Minute, nur master):
/usr/local/bin/handash-deploy
# Log: sudo tail -f /var/log/handash-deploy.log
# HINWEIS: Script braucht sudo wegen Logfile-Permissions
```

---

## hanRND – Restnutzungsdauergutachten (diese Session gebaut)

### Was es tut
Web-App zur Verwaltung von Restnutzungsdauer-Gutachten für Immobilien.
- Alle Felder des **BeMa Antragsformulars** (7 Seiten) digital erfassbar
- **Auftraggeber**-Stammdaten (wiederverwendbar)
- **Immobilien** anlegen, bearbeiten, löschen
- **Fotos** hochladen, **Video-URLs** speichern, **Freitextfeld**
- **PDF-Export**: BeMa-Formular wird befüllt, Browser-Print-Dialog
- **Multi-User** mit Login (Supabase Auth)

### Status: FUNKTIONIERT ✅
- Login/Register funktioniert
- Dashboard lädt (leer, noch keine Immobilien)
- Supabase-Verbindung stabil
- Helles Theme aktiv

### Noch nicht getestet
- [ ] Neue Immobilie anlegen (kompletter Wizard, alle 7 Schritte)
- [ ] Auftraggeber anlegen, bearbeiten, löschen
- [ ] Foto-Upload (Supabase Storage)
- [ ] Video-URL speichern
- [ ] PDF-Export / BeMa-Formular drucken
- [ ] Immobilie bearbeiten und löschen
- [ ] Zweiter Nutzer registrieren (Multi-User-Isolation)

---

## Technische Details

### Supabase
```
Projekt-URL:  https://osimhkucprzrrfzjnryo.supabase.co
Anon Key:     eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im9zaW1oa3VjcHJ6cnJmempucnlvIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzk5MDQxMjgsImV4cCI6MjA5NTQ4MDEyOH0.gZ3paVUnQxjnqGnAMsFH0YduulmpR_HBeRHNK590dYk
Dashboard:    https://supabase.com/dashboard/project/osimhkucprzrrfzjnryo
```

### Supabase-Tabellen
| Tabelle | Inhalt |
|---------|--------|
| `auftraggeber` | Kundenstammdaten (FK auf auth.users) |
| `immobilien` | Alle Immobilien-Felder inkl. BeMa-Formular-Abschnitte 1–7 |
| `immobilien_media` | Fotos (Storage-Pfad) + Video-URLs pro Immobilie |

RLS ist aktiviert – jeder Nutzer sieht nur seine eigenen Daten.

### Storage
- Bucket: `immobilien-media` (public)
- Pfad-Schema: `{user_id}/{immobilie_id}/{filename}`
- Policies: auth_upload_own, auth_select_own, auth_delete_own

### Registrierter Nutzer
- `tobias.roebig@gmail.com` (bereits angelegt)
- E-Mail-Bestätigung: ggf. noch in Supabase deaktivieren unter
  Authentication → Providers → Email → Confirm email: OFF

---

## Offene Aufgaben / Nächste Schritte

### Prio 1 – Testen & Bugfixing
1. Den kompletten Wizard einmal durchlaufen (alle 7 Schritte, speichern)
2. PDF-Export testen: sieht der BeMa-Bogen korrekt aus?
3. Foto-Upload testen
4. Bearbeiten & Löschen testen

### Prio 2 – Inhaltliche Verbesserungen (offen aus Session)
- **Bezeichnung**: Soll automatisch aus Adresse generiert werden (z.B. "Musterstr. 1 – Wohnung 3"), oder immer manuell?
- **Stichtag**: Soll automatisch auf heutiges Datum gesetzt werden oder leer bleiben?
- Die Modernisierungs-Optionen im Wizard entsprechen noch nicht 1:1 dem BeMa-PDF (andere Kategorien als im Originalformular) – Abgleich nötig

### Prio 3 – Merge in master
PR #4 ist offen: https://github.com/airtobias-dotcom/hanDash/pull/4
Nach erfolgreichem Test → mergen → automatisches Deployment via cron

### Prio 4 – Weitere Features (aus Gespräch)
- Immobilien für andere Projekte/Formulare wiederverwenden
- Ggf. weitere Gutachten-Typen (BeMa hat ETW 270€ / MFH+EFH 470€ / Vor-Ort ab 330€)

---

## BeMa-Formular Referenz

Das Original-PDF liegt unter:
`/root/.claude/uploads/d9364d30-53e2-4e55-9a82-779f98969a20/8311c389-Antragsformular_Restnutzungsdauer_2026_Bema_Immobilien_V_1_9_Pdf.pdf`

Seiten:
1. Auftraggeber + Gutachten-Typ + Immobilien-Adresse
2. Abschnitt 1: Art der Immobilie (8 Typen) + Basisinfos
3. Abschnitt 2.1–2.4: Bauweise, Bäder, Dachart, Fenster
4. Abschnitt 2.5–2.6: Heizung, Keller + Beginn Modernisierungen
5. Abschnitt 3.1–3.7: Modernisierungen (7 Kategorien × 6 Zeiträume + %)
6. Abschnitt 3.8 + 4–5: Grundriss, Unterlagen, Stichtag
7. Abschnitt 6–7: Eigentümer, Rechnungsempfänger + Zusatzkosten-Info

---

## Git-Commit-History (diese Session)

```
88a49af fix: simplify init() – getSession first, then render, then listener
ccd0892 fix: loading state + CDN fallback (jsdelivr → unpkg)
aca8fc7 style: light modern theme for hanRND
e61a0a5 fix: use public storage bucket for photo display
95c43be config: add Supabase credentials for hanRND
e1aed38 feat: add Restnutzungsdauer module (hanRND)
4d09505 feat: add Supabase setup files for hanRND module
```
