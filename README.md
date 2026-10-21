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
ios-native/      Native SwiftUI-Version (braucht Mac + Xcode)
```
Deine Trainingsdaten und Schlüssel bleiben nur auf deinen Geräten.
