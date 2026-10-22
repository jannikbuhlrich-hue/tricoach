# TriCoach

Triathlon-App für die Garmin Forerunner 265 – läuft auf iPhone, iPad und PC als installierbare Web-App.

**App öffnen:** https://jannikbuhlrich-hue.github.io/tricoach/

## Installieren
- **iPhone/iPad:** Link in Safari öffnen → Teilen → „Zum Home-Bildschirm“
- **PC:** Link in Edge oder Chrome öffnen → in der Adressleiste „App installieren“
- **Android:** Chrome-Menü → „App installieren“

## Uhrdaten
- **Automatisch:** Forerunner → Garmin Connect (Bluetooth) → intervals.icu → TriCoach. API-Key in den Einstellungen eintragen.
- **USB (PC):** Uhr anstecken, Ordner `GARMIN/Activity` wählen.
- **Live-Puls:** Uhr auf „HF übertragen“, in TriCoach „Live-Puls“ → verbinden (Chrome/Edge/Android).

## Neu in 2.6.2
- **In TrainingPeaks nachtragen – alles auf einmal:** Hinweis in „Mein Tag“ und in den Einstellungen, wenn Einheiten in TrainingPeaks fehlen (eigene Einträge, per Siri eingetragene, auf Wunsch auch Uhr-Einheiten). Am PC/iPad: eine ZIP mit FIT-Dateien (Uhr-Einheiten als Originaldatei aus intervals.icu, geprüft mit dem Garmin FIT SDK) – alle zusammen auf den TrainingPeaks-Kalender ziehen. Am iPhone: alle Einheiten der letzten 7 Tage in einem Rutsch an Apple Health (Kurzbefehl im Listen-Modus).
- Einstellungen wie „auf allen Geräten“ und Siri-Status bleiben jetzt auch nach dem Neustart gespeichert.

## Neu in 2.6
- **Siri, Kurzbefehle & Widget, die wirklich funktionieren:** Apple lässt Kurzbefehle keine Web-App öffnen („URL öffnen“ landet in Safari ohne deine Daten). Darum läuft Siri jetzt über das Skript `siri/TriCoach.js` in der kostenlosen App **Scriptable**: „Hey Siri, Frag TriCoach“ → „Was steht morgen an?“, „Wie ist meine Form?“, „Trag 45 Minuten Lauf 9 km ein“ … plus Widget „Mein Tag“ (Schule mit Entfall/Vertretung, Training, Prüfungen, Hausaufgaben). Einrichtung in 3 Schritten unter Einstellungen → Siri & Kurzbefehle. Das Skript entschlüsselt Schule/Trainingsplan selbst und aktualisiert sich automatisch.
- **Auf allen Geräten:** Eigene Einheiten werden (wenn intervals.icu verbunden ist) zusätzlich in intervals.icu gespeichert und erscheinen so auf iPhone, iPad und PC – und für Siri. Per Siri eingetragene Einheiten kommen mit Notiz, RPE und Sportart (z. B. Kitesurfen) in TriCoach an.
- **Aufruf-Links** für PC/Android/Verknüpfungen: `#today`, `#log`, `?do=log&sport=run&min=45&km=9&rpe=4`, `?do=plan&sport=bike&min=90&date=morgen`, `?do=hw`, `?do=sync` – auch bei schon offener App.
- **Sicherung laden:** Kalender, eigene Einheiten und Hausaufgaben per Datei von einem Gerät aufs andere übertragen (wird zusammengeführt).
- Hausaufgaben zeigen den richtigen Fachnamen (z. B. „MatL1“ → Mathematik); keine falsche „Job hat nicht aktualisiert“-Warnung mehr nachts.
- Verschlüsselung mit festem Salz → Schlüssel muss nur einmal abgeleitet werden (schneller, nötig für Siri/Widget).
- Native iOS-Version: zusätzliche Siri-Befehle (Morgen, Form, Wettkampf, Öffnen) und Athletik/Sonstiges als Sportart.

## Neu in 2.5

- **TrainingPeaks-Plan automatisch:** GitHub-Job `TrainingPeaks-Plan` (.github/workflows/tp.yml) holt stündlich den privaten iCal-Link, verschlüsselt ihn mit `TRICOACH_KEY` (Branch `tp-daten`). TriCoach lädt ihn beim Öffnen und alle 30 Minuten, übernimmt Änderungen deiner Trainerin, entfernt gelöschte Einheiten und liest die geplante Dauer aus dem Titel. Kein TrainingPeaks-Passwort nötig.
- Link hinterlegen: `TRICOACH_KEY=… node tools/tp-sync.mjs --set "webcal://…"` (schreibt `tools/tp-zugang.enc`) oder Secret `TP_ICAL`.

## Neu in 2.4
- **Schule per WebUntis-App-Schlüssel:** Anmeldung wie die Untis-App (Server, Schule, Benutzer, Schlüssel aus *Profil → Freigaben → Zugriff über Untis Mobile*) – klappt auch bei Microsoft-Login. Zugang entweder verschlüsselt im Repo (`tools/untis-zugang.enc`, dann nur Secret `TRICOACH_KEY`) oder als Secret `UNTIS_ZUGANG`.
- **Wettkampf auf Sprint ausgelegt:** Sprint als Standard, Umschalter Volksdistanz/Sprint/Olympisch, Taper passend zur Distanz, neue Karte „Wettkampf simulieren“ (Koppeltraining, Renntempo-Schwimmen, Generalprobe, Rennpace).
- **Schwimmen: 25-m-Bahn, 50-m-Bahn oder Freiwasser** beim Eintragen; von der Uhr erkannt und korrigierbar; in FIT-Datei und TrainingPeaks-Übergabe enthalten.
- **Empfehlungen nach deinen Gewohnheiten:** übliche Trainingstage und -dauer, Lieblings-Schlüsseleinheiten deiner Trainerin aus dem TrainingPeaks-Plan; ihr Plan hat Vorrang, Vorschläge landen nur auf freien Tagen.

## Neu in 2.3
- **Mein Tag** (Start-Tab „Heute“): Schule, Training, Termine, Hausaufgaben und Prüfungen in einem Tagesablauf, ab 17 Uhr automatisch der nächste Tag.
- **Schule (WebUntis):** Stundenplan mit Entfall/Vertretung/Raumänderung, Infos der Lehrkräfte, Nachrichten des Tages, Hausaufgaben (abhaken, eigene ergänzen), Prüfungen. Auch als Ebene „Schule“ im Kalender.
  Abruf über den GitHub-Job `.github/workflows/schule.yml` (`tools/untis-sync.mjs`) alle 30 min, Daten AES-verschlüsselt im Branch `schule-daten` – lesbar nur mit deinem Schlüssel. Einrichtung: App → Einstellungen → Schule.
- Apple Kalender: Stundenplan per WebUntis-iCal-Abo, Hausaufgaben/Prüfungen per .ics mit Erinnerung.
- Eintragen ohne Schnellwahl – km werden immer selbst eingetippt; Athletik ohne Schwerpunkt-Auswahl.

## Neu in 2.2
- **Kalender wie Apple Kalender:** Tag · Woche · Monat (mit KW) · Jahr · Liste, ganztägig/mehrtägig, Wiederholungen (auch eigene Wochentage, Ende nach Datum/Anzahl, „nur dieser Termin“), zwei Hinweise, Ort, URL, Notizen, Kalender ein-/ausblenden, Suche, Drag & Drop, Duplizieren, Plan-Ampel wie TrainingPeaks, .ics-Export (mit Wiederholung + Erinnerung) und -Import.
- **Einheiten eintragen:** Schwimmen in km (oder Bahnen × Becken), Rad, Laufen, **Athletik** (Schwerpunkt + Übungen mit Sätzen/Wdh/kg), **Sonstiges** (z. B. Kitesurfen), RPE, Notizen. Uhr-Einheiten korrigieren (bleibt nach jedem Sync).
- **TrainingPeaks:** Kurzbefehl → Apple Health → TrainingPeaks-App, FIT-Datei (geprüft mit dem Garmin FIT SDK), Wettkampf-Übergabe als Event (A/B/C), TP-Plan per iCal-Link importieren.
- **Fortschritt:** Wochenringe, Serien, Trends 90 vs. 365 Tage, Bestleistungen, Jahresziele mit Hochrechnung, Auszeichnungen, **VO2 Max**.

## Updates
Neue Version = Dateien ändern, `VERSION` in `sw.js` und `APP_VERSION` in `js/core.js` erhöhen, pushen.
Installierte Apps zeigen dann „Neue Version verfügbar“.

## Aufbau
```
index.html, manifest.webmanifest, sw.js   App-Hülle, Installation, Offline & Updates
css/app.css                               Layout + 4 Designs (Nacht, Gletscher, Asphalt, Nordsee)
js/core.js       Hilfen, Diagramme, Icons
js/analytics.js  TSS/PMC, VDOT, FTP, CSS, Aero, Taper, Fueling, Empfehlungen
js/fit.js        FIT-Decoder (auch Multisport)
js/data.js       IndexedDB, intervals.icu-Sync, FIT-Import, Kalender-Export
js/ble.js        Live-Herzfrequenz per Web Bluetooth
js/views.js      Ansichten · js/settings.js Einstellungen · js/app.js Steuerung
js/calendar.js   Kalender (Ansichten, Editor, Wiederholungen, .ics)
js/log.js        Einheiten eintragen/bearbeiten
js/tp.js         TrainingPeaks-Brücke (Apple Health, FIT-Writer, Übergabe)
js/progress.js   Fortschritt (Ringe, Trends, Bestleistungen, VO2 Max)
js/school.js     Mein Tag + Schule (WebUntis-Daten entschlüsseln, Stundenplan, Hausaufgaben)
js/siri.js       Siri/Kurzbefehle/Widget-Einrichtung, Aufruf-Links
siri/TriCoach.js Scriptable-Skript für Siri, Kurzbefehle und Widget (Tests: node siri/test/cmds.test.mjs)
tools/           untis-sync.mjs für den GitHub-Job
ios-native/      Native SwiftUI-Version (braucht Mac + Xcode)
```
Deine Trainingsdaten und Schlüssel bleiben nur auf deinen Geräten.
