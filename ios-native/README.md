# TriCoach – Triathlon-App für Garmin Forerunner 265

SwiftUI-App für iPhone & iPad: Garmin-Daten importieren, Swim/Bike/Run analysieren,
Training planen, Siri steuern. Läuft sofort mit realistischen **Demo-Daten**.

## Schnellstart

```bash
brew install xcodegen
cd TriCoach
xcodegen generate
open TriCoach.xcodeproj
```

- Xcode 16 oder neuer, iOS/iPadOS 17+
- In *Signing & Capabilities* dein Team wählen (HealthKit + Push brauchen einen Developer-Account)
- Starten → Dashboard ist mit ~5 Monaten Demo-Training gefüllt
- Tests: `⌘U` (TSS, VDOT, Aero-Modell, PMC, Merger, Mock-Daten)

## Wie kommen die Forerunner-Daten in die App?

| Weg | Aufwand | Was kommt an |
|---|---|---|
| **Garmin-API** (Health + Activity API) | Antrag im Garmin Connect Developer Program + eigenes Backend | alles inkl. Webhook-Live-Sync, Schlaf, Stress, HRV, VO2max, Workouts zur Uhr |
| **FIT-Import** | keiner – Datei aus Garmin Connect exportieren oder per USB von der Uhr (`GARMIN/Activity`) | volle Aktivitätsdetails: SWOLF pro Bahn, Züge, Laufdynamik, Watt, GPS |
| **Apple Health** | Garmin Connect → Apple Health aktivieren | Workouts, HF, Schlaf, Ruhepuls, HRV (Umfang abhängig von Garmin Connect) |
| **Demo-Daten** | keiner | alles simuliert, deterministisch |

Mehrere Quellen gleichzeitig sind möglich – Duplikate werden zusammengeführt (Priorität Garmin > FIT > Health > Demo).

**Ehrlicher Hinweis zur Garmin-API:** Sie ist eine Partner-API, kein öffentlicher Zugang mit
Garmin-Login. Für den privaten Einsatz ist **FIT-Import + Apple Health** der realistische Weg;
die Garmin-Integration ist komplett vorbereitet (OAuth 2.0 PKCE, DTOs, Push-Sync) und wird aktiv,
sobald `Config/Secrets.xcconfig` befüllt ist. Inoffizielle Garmin-Connect-Scraper bewusst nicht
eingebaut (verstößt gegen Garmins Nutzungsbedingungen). Backend-Vertrag: [`Backend/API.md`](Backend/API.md).

Trainingsbereitschaft und Erholungszeit stehen nicht in jeder API-Stufe zur Verfügung –
die App berechnet dann eine eigene Bereitschaft aus Schlaf, HRV-Basis, Ruhepuls und TSB.

## Architektur (Clean Architecture + MVVM)

```
TriCoach/
├─ App/              Einstieg, Navigation (TabView iPhone · NavigationSplitView iPad · Multi-Window)
├─ Core/
│  ├─ Models/        Activity, Wellness, Zonen, Planung, Wettkampf
│  ├─ Data/          TrainingDataSource-Protokoll, TrainingStore (Repository), Persistenz
│  │  ├─ Garmin/     OAuth2 PKCE, API-Client, DTOs, Keychain
│  │  ├─ HealthKit/  Apple-Health-Quelle
│  │  ├─ FIT/        FIT-Decoder + Import
│  │  └─ Mock/       Demo-Daten-Generator
│  ├─ Analytics/     TSS/PMC, Readiness, VDOT, Split-Prognose, Taper, Stärken/Schwächen, Coach, Fueling
│  ├─ Plugin/        AppModule-Protokoll + ModuleRegistry
│  └─ Sync/          Live-Sync (Push, HealthKit-Observer, Background Refresh)
├─ Modules/          ← je Sportart/Feature ein Plugin
│  ├─ Swim/  Bike/  Run/        Analysen + ViewModels + Views
│  └─ Race/  Wellness/  Heatmap/
├─ Features/         Dashboard, Kalender (EventKit), Aktivitätsdetail, Einstellungen
├─ Intents/          Siri / App Intents
└─ UI/               Theme, Kacheln, Karten, Gauges
```

Datenfluss: `DataSource → TrainingStore → ViewModel (@Observable) → SwiftUI View`

### Neue Sportart oder Feature hinzufügen

```swift
struct StrengthModule: AppModule {
    let id = "strength"; let title = "Kraft"; let symbol = "dumbbell.fill"
    let tint = Color.purple; let category = ModuleCategory.sport
    var sport: Sport? { .strength }
    func makeView(store: TrainingStore) -> AnyView { AnyView(StrengthView()) }
}
// ModuleRegistry.registerDefaults(): shared.register(StrengthModule())
```
Sidebar, Analyse-Tab und Kacheln erscheinen automatisch. Neue Datenquelle (Wahoo, Strava …) =
`TrainingDataSource` implementieren und in `TrainingStore.makeSources()` eintragen.

## Features

- **Dashboard:** Bereitschafts-Ring, Fitness/Ermüdung/Form, Swim/Bike/Run-Kacheln (Woche/Monat mit Vergleich),
  Wochenumfang, PMC-Chart, HF-Zonen, Stärken/Schwächen, Wettkampf-Fortschritt, Empfehlungen (1-Tap in den Kalender)
- **Laufen:** Intervallanalyse (Tempoverlust, Konstanz, HF-Drift), Laufökonomie (Efficiency Factor, Entkopplung,
  Running Effectiveness), VDOT-Prognosen 5 km–Marathon, Laufdynamik
- **Rad:** FTP-Schätzung (20/60/8 min), Leistungskurve, Zeit in Coggan-Zonen, CdA-Aerotrend, VI/IF
- **Schwimmen:** CSS-Schätzung, SWOLF-Trend, optimale Zugzahl, Frequenzanalyse (Pace je Zugrate), Technikindikatoren
- **Wettkampf:** Split-Prognose (CSS, Aero-Modell, Hitze, Neo), Live-Modus mit Splits & Zielzeitprognose,
  Fueling-Plan + Tracker, Taper-Optimierung (PMC-Simulation)
- **Schlaf & Stress:** Schlafphasen, HRV vs. Basis, Ruhepuls, Body Battery, VO2max
- **Kalender:** Monatsansicht, Planung, Sync in eigenen Apple-Kalender „TriCoach“
- **Heatmap:** alle GPS-Tracks, gefiltert nach Sport/Zeitraum
- **Siri:** siehe unten · **Dark Mode** Standard · **iPad:** Split View, Stage Manager, Aktivität in neuem Fenster

## Siri

Apple verlangt den App-Namen in jeder mitgelieferten Phrase:

- „Hey Siri, zeige mein heutiges Training in TriCoach“
- „Hey Siri, plane eine Radeinheit für morgen in TriCoach“
- „Hey Siri, wie viele Kilometer bin ich diese Woche in TriCoach gelaufen“

Ohne App-Namen: in der Kurzbefehle-App einen Kurzbefehl mit eigener Phrase anlegen.

## Analyse-Methoden

| Kennzahl | Methode |
|---|---|
| TSS Rad / Lauf / Schwimmen | NP/FTP² · Pace/Schwellenpace² · Speed/CSS³ (je × h × 100), Fallback hrTSS |
| Fitness / Ermüdung / Form | CTL 42 d, ATL 7 d (EWMA), TSB = CTL − ATL (Vortag) |
| Laufprognose | Jack-Daniels-VDOT aus besten 12/20/40-min-Abschnitten |
| FTP | max(0,95 × P20, P60, 0,9 × P8), nur wenn Maximalbelastung erkannt |
| CdA | P = ½ρCdAv³ + CrrMgv (flache, stationäre Abschnitte; Trend, nicht absolut) |
| CSS | (T400 − T200) / 2 aus besten zusammenhängenden Bahnen |
| Taper | Grid-Search 5–21 Tage × 30–60 % Reduktion, Ziel TSB ≈ +15 bei minimalem CTL-Verlust |

## Offene Punkte

- Live-Daten **während** einer Aktivität liefert die Garmin-API nicht (nur nach dem Sync) → Wettkampfmodus mit Tap-Splits; echtes Live-Tracking ginge nur per Connect-IQ-Datenfeld auf der Uhr
- FIT-Decoder liest die benötigten Felder; für alles Weitere das offizielle Garmin FIT SDK einbinden
- Persistenz ist JSON – bei großen Datenmengen auf SwiftData umstellen
- Ernährungswerte sind Richtwerte, keine medizinische Beratung
