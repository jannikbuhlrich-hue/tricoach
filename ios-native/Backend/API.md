# TriCoach Backend – API-Vertrag

Die App spricht **nie direkt** mit Garmin. Grund: Die Garmin Connect Developer Program APIs
(Health API, Activity API, Training API) sind Partner-APIs – der Token-Tausch braucht das
`client_secret`, und Garmin liefert neue Daten per **Push/Ping-Webhook an einen Server**.

Ein kleines Backend (z. B. Vapor, FastAPI, Node, Cloudflare Workers) übernimmt:

1. OAuth 2.0 + PKCE Token-Tausch mit Garmin (`client_secret` bleibt serverseitig)
2. Speicherung von Access/Refresh-Token pro Nutzer
3. Empfang der Garmin-Webhooks (Activity, Activity Details, Dailies, Sleep, HRV, User Metrics)
4. Abruf der FIT-Datei pro Aktivität (Activity Files)
5. Stille APNs-Push an die App → „Live-Sync“ direkt nach dem Uhr-Sync
6. Optional: KI-Coach-Endpunkt (LLM-Aufruf, API-Key bleibt serverseitig)

Alle App-Requests tragen `Authorization: Bearer <sessionToken>`.

## Endpunkte

| Methode | Pfad | Zweck |
|---|---|---|
| POST | `/v1/garmin/oauth/exchange` | Body `{code, codeVerifier, redirectUri}` → tauscht bei Garmin, Antwort `{sessionToken}` |
| DELETE | `/v1/garmin/registration` | Nutzer bei Garmin abmelden (Garmin: `DELETE /wellness-api/rest/user/registration`) |
| GET | `/v1/garmin/activities?from=<unix>&to=<unix>` | `[GarminActivityDTO]` – Activity-Summaries inkl. `samples` + `laps` aus Activity Details, `hasFitFile` |
| GET | `/v1/garmin/activities/{summaryId}/fit` | Rohe `.fit`-Datei (für SWOLF/Bahnen, Laufdynamik, volle Auflösung) |
| GET | `/v1/garmin/wellness?from=<unix>&to=<unix>` | `[GarminDailyBundleDTO]` – pro `calendarDate`: `daily`, `sleep`, `hrv`, `userMetrics`, optional `readiness` |
| POST | `/v1/garmin/workouts` | Geplante Einheit → Garmin Training API → erscheint auf der Forerunner |
| POST | `/v1/devices` | `{apnsToken}` für Push registrieren |
| POST | `/v1/coach` | Trainingszusammenfassung → `{recommendations:[{sport,title,detail,priority,durationMinutes}]}` |

Feldnamen der DTOs entsprechen den Garmin-Summaries (siehe `GarminAPIClient.swift`),
damit das Backend die Garmin-JSONs weitgehend durchreichen kann.

## Garmin-Eckdaten

- Zugang: Antrag im Garmin Connect Developer Program (developerportal.garmin.com), App muss freigegeben werden
- Auth: OAuth 2.0 mit PKCE (S256); Consent-Seite `https://connect.garmin.com/oauth2Confirm`,
  Token-Endpunkt laut aktueller Garmin-Doku (`…/di-oauth2-service/oauth/token`)
- Keine Scopes im Request – Berechtigungen wählt der Nutzer auf der Consent-Seite
- Pull-Abfragen sind auf 24 h **Upload-Zeit** pro Request begrenzt → Backend sammelt per Webhook

## Silent Push nach Garmin-Webhook

```json
{ "aps": { "content-available": 1 }, "type": "garmin.activity" }
```
