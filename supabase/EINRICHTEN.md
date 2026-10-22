# Supabase einrichten (ca. 20 Minuten, einmalig)

Supabase ist der Server hinter TriCoach: Login, Datenbank und Abgleich zwischen den Geräten.
Kostenlos bis 50.000 Nutzer im Monat und 500 MB Datenbank – für Beta und Start reicht das.

## 1. Projekt anlegen

1. <https://supabase.com> → **Start your project** → mit GitHub anmelden.
2. **New project**
   - Name: `tricoach`
   - Datenbank-Passwort: erzeugen lassen und im Passwort-Manager speichern
   - **Region: Central EU (Frankfurt)** ← wichtig für den Datenschutz
3. Warten, bis das Projekt bereit ist (1–2 Minuten).

## 2. Datenbank einrichten

1. Links **SQL Editor** → **New query**.
2. Den kompletten Inhalt von `supabase/migrations/20261022000000_init.sql` hineinkopieren → **Run**.
3. Es muss „Success. No rows returned“ erscheinen.

## 3. Kalender-Abo-Funktion hochladen

Am einfachsten mit der Supabase-CLI am PC:

```bash
npm install -g supabase
supabase login
supabase link --project-ref DEIN-PROJEKT-REF     # steht in der Projekt-URL
supabase functions deploy calendar --no-verify-jwt
```

Alternativ im Dashboard: **Edge Functions** → **Deploy a new function** → Name `calendar` →
Inhalt von `functions/calendar/index.ts` und `functions/calendar/ics.js` einfügen →
unter den Einstellungen der Funktion **Verify JWT** ausschalten.

## 4. Login einstellen

**Authentication → URL Configuration**
- Site URL: vorerst `https://jannikbuhlrich-hue.github.io/tricoach/`
- Redirect URLs hinzufügen: `app.tricoach://login-callback`

**Authentication → Providers**
- Email: an (Standard). „Confirm email“ an lassen.
- Apple und Google: erst wenn die Store-Konten da sind (Woche 7) – braucht jeweils Zugangsdaten aus dem
  Apple- bzw. Google-Entwicklerkonto. Bis dahin funktioniert Login per E-Mail und Login-Link.

## 5. Zugangsdaten in GitHub hinterlegen

**Project Settings → API Keys**: dort stehen `Project URL` und der **Publishable key** (bei älteren Projekten „anon public“).
Dieser Schlüssel ist öffentlich (er steckt in jeder App) – geschützt wird über die Zugriffsregeln in der Datenbank.
Den **Secret key** (früher service_role) niemals weitergeben oder in die App packen.

Im GitHub-Repo: **Settings → Secrets and variables → Actions → Variables → New repository variable**
- `SUPABASE_URL` = Project URL
- `SUPABASE_ANON_KEY` = Publishable key (bzw. anon public)

Ab dem nächsten Push baut GitHub die App automatisch mit Server-Anbindung.

## 6. Kurz testen

- App öffnen → Einstellungen → Anmelden → registrieren → Mail bestätigen.
- Eine Einheit eintragen → in Supabase unter **Table Editor → activities** taucht sie auf.
- Zweites Gerät anmelden → Einheit ist da.
- Einstellungen → Kalender → **Link kopieren** → im Browser öffnen → Kalender-Datei wird geladen.

## Was die Datenbank schützt

- Jeder sieht nur seine eigenen Einheiten und Pläne.
- Ein Coach sieht die Einheiten seiner Athleten erst, nachdem der Athlet den Einladungscode eingelöst hat –
  und kann sie nur lesen, nicht ändern. Planen darf er nur für verbundene Athleten.
- Getestet in `tests/rls_test.sql` (läuft bei jedem Push automatisch).
