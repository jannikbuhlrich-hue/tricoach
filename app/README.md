# TriCoach 3 – App für iPhone, Android, Web und PC

Flutter-App + Supabase-Backend. Ein Account, alle Geräte synchron, Trainings automatisch im Kalender.
Die bisherige Web-App (Ordner `../js`, `../index.html`) bleibt unverändert und läuft weiter.

## Was schon drin ist

| Bereich | Stand |
|---|---|
| Mein Tag | Heute/Morgen (ab 17 Uhr), Form, Fitness, Wochenziel, Serie, letzte Einheiten |
| Eintragen | Schwimmen (25 m / 50 m / Freiwasser, km selbst tippen oder Bahnen), Rad, Lauf, Athletik (Übungen, Sätze, Wdh, kg), Sonstiges (z. B. Kitesurfen), RPE, Puls, Kalorien, Notizen |
| Kalender | Monat (mit KW), Woche, Liste; Training, Termin, Wettkampf (A/B/C); Ampel erledigt/verpasst |
| Fortschritt | Form-Kurve (CTL/ATL/TSB), Wochenumfang je Sportart, VO2-Max-Schätzung, 5/10 km, Prognosen, Jahressummen, Jahresziel |
| Uhr | Apple Health (iOS), Health Connect (Android), intervals.icu (alle Geräte inkl. PC) – Doppelte werden zusammengeführt |
| Kalender-Sync | Eigener Kalender „TriCoach“ im Handy (Apple/Google), Abo-Link (.ics) für PC/Outlook/Google, .ics-Export |
| Abgleich | Offline zuerst, Warteschlange, „neuere Änderung gewinnt“, Echtzeit zwischen Geräten |
| Coach | Einladungscode, Trainer-Ansicht mit Ampel, Einheiten für Athleten planen |
| Import | Sicherung aus der Web-App 2.x (Einheiten, Korrekturen, Kalender, Profil) – ohne Doppelte; FIT-Dateien von der Uhr (USB/Garmin Connect) |
| Export | Jede Einheit als FIT-Datei (byte-gleich mit der Web-App, die mit dem Garmin FIT SDK geprüft ist) – z. B. für TrainingPeaks |
| Designs | Nacht, Gletscher, Asphalt, Nordsee |
| Einführung | Einwilligung Gesundheitsdaten (DSGVO), Uhr, Kalender, Account |

Noch offen (laut Plan später): TrainingPeaks über Apple Health, Schule (WebUntis) als Extra, Abos/Bezahlen, Siri.

## Ordner

```
lib/core/    Modelle, Analysen (TSS, Form, VDOT), Kalender-Datei, Import der Web-App-Sicherung
lib/data/    lokale Datenbank (Sembast), Abgleich (SyncEngine), Supabase, Apple Health/Health Connect,
             intervals.icu, Handy-Kalender
lib/state/   App-Zustand
lib/ui/      Designs, Bausteine, Diagramme, Bildschirme
test/        Tests für Analysen, Abgleich (inkl. Konflikte/offline), Import, Kalender, Oberfläche
../supabase/ Datenbank (Tabellen + Zugriffsregeln), Kalender-Abo-Funktion, Tests
```

## Starten

Ohne Server (alles nur auf dem Gerät):

```bash
flutter run
```

Mit Server (nach der Einrichtung in `../supabase/EINRICHTEN.md`):

```bash
flutter run --dart-define=SUPABASE_URL=https://DEIN-PROJEKT.supabase.co --dart-define=SUPABASE_ANON_KEY=DEIN_ANON_KEY
```

Tests: `flutter test` · Datenbank-Tests: `bash ../supabase/tests/run.sh` (braucht ein lokales Postgres)

## Automatische Prüfung

Jeder Push auf den Branch `flutter-app` startet `.github/workflows/app.yml`:
Backend-Tests, Code-Analyse, App-Tests, Web-Build, Android-APK und iOS-Build (ohne Signatur).
Die fertige Web-Version und die Android-Test-App liegen danach unter *Actions → Lauf → Artifacts*.
Berichte zum Nachlesen landen in den Branches `ci-bericht-app`, `ci-bericht-android`, `ci-bericht-ios`.
