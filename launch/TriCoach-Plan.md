---
tags: [tricoach, projekt, plan]
erstellt: 2026-10-22
start: 2026-10-26
launch: 2027-01-17
status: aktiv
---

# TriCoach – 12-Wochen-Plan bis zum Store-Launch

**Ziel:** Mitte Januar 2027 ist TriCoach als echte App im **App Store, Google Play Store und im Web (PC)** – ein Account, alle Geräte synchron, Trainings automatisch im Kalender.

**Zeitraum:** Mo 26.10.2026 – So 17.01.2027 (12 Wochen + Startwoche jetzt)

---

## Stand 22.10.2026 – Vorarbeit erledigt

Claude hat die Claude-Aufgaben aus W0–W7 und die Texte aus W10–W11 vorgezogen. Code liegt im Branch **`flutter-app`** (deine Web-App auf `main` bleibt unverändert). GitHub baut und testet bei jedem Push automatisch.

**Erledigt am 22.10. nachmittags:** Supabase eingerichtet (Datenbank, Kalender-Abo, Login, GitHub-Variablen) · Schule-Modul (WebUntis) · TrainingPeaks-Plan der Trainerin in der App · fehlende Einheiten auf einmal nachtragen (ZIP/FIT, Apple Health) · Web-Version unter <https://jannikbuhlrich-hue.github.io/tricoach/v3/>.
**Noch offen bei Claude:** Abos (RevenueCat) · Store-Einreichung – beides braucht die Store-Konten.
**Jetzt bei dir:** Web-Version öffnen, Account anlegen, alte Sicherung laden · iCal-Link der Trainerin als Secret `TP_ICAL` · Eltern wegen Store-Konten fragen · Ideal-Kunde · Tester-Liste.

---

## 1. Rollen – wer macht was

| Claude | Du (Jannik) |
|---|---|
| Schreibt den Code (App + Backend) und pusht ihn in dein GitHub-Repo | Testest jede Woche auf iPhone, Android und PC |
| Plant Architektur, Datenbank, Sync | Triffst Entscheidungen (Design, Features, Preise) |
| Schreibt Texte: Store-Einträge, Landing Page, Datenschutz-Entwurf | Legst Konten an (Supabase, Apple, Google, Domain) |
| Findet Fehler, baut Tests | Holst Beta-Tester + Trainerin-Feedback |
| Bereitet Social-Media-Skripte vor | Drehst und schneidest den Content |

**Dein Zeitbudget:** 6–8 h/Woche (passt zu 35 h Schule + 10–15 h Training + Fahrten).
**Fester Rhythmus:** 2 × 1,5 h unter der Woche (Testen + Feedback) und 3 h am Wochenende (Entscheiden, Konten, Content).

---

## 2. Technik-Entscheidung (final)

| Baustein | Lösung | Warum |
|---|---|---|
| App | **Flutter** | Ein Code → iOS, Android, Web, Windows/Mac |
| Backend | **Supabase** (Server in Frankfurt) | Login, Datenbank, Echtzeit-Sync fertig dabei – kein eigener Server nötig, DSGVO-freundlich |
| Offline | Lokale Datenbank auf dem Gerät + Sync | App läuft ohne Netz, gleicht später ab |
| Uhr-Daten | **Apple Health** (iOS) + **Health Connect** (Android), dazu intervals.icu und FIT-Import | Funktioniert mit Garmin, Apple Watch, Coros usw. – nicht nur Forerunner |
| Kalender | Direkt in den Geräte-Kalender (iPhone → Apple Kalender, Android → Google Kalender) **plus** Abo-Link (.ics) für PC und alle anderen | Kein Nutzer muss etwas manuell übertragen |
| Abos/Bezahlen | **RevenueCat** + In-App-Abos von Apple/Google | Abo-Logik für alle Stores an einem Ort |
| App-Builds | GitHub Actions / Codemagic (Cloud) | iOS-Builds ohne eigenen Mac |
| Fehler-Tracking | Sentry | Abstürze sehen, bevor Nutzer sich beschweren |

**Die bestehende Web-App bleibt das Vorbild:** Designs (Nacht, Gletscher, Asphalt, Nordsee), Analysen (TSS/Form, VO2 Max, VDOT, FTP), Log-Formular, Kalender – alles wird nach Flutter übertragen, nicht neu erfunden.

**Was bewusst NICHT zum Start gehört:** Ironman-Programm, Ernährungsplan, KI-Coach, Fußball. → stehen in der Ideen-Liste (Abschnitt 9).

---

## 3. Meilensteine

| # | Datum | Was steht |
|---|---|---|
| M0 | So 25.10. | Konten + Repo bereit, Entscheidungen getroffen |
| M1 | So 22.11. | **Alpha** – läuft bei dir auf allen Geräten, Sync + Kalender funktionieren |
| M2 | So 13.12. | **Beta 1** – 5–10 Tester haben die App (TestFlight / Play-Test / Web) |
| M3 | So 03.01. | Abos, Datenschutz, Impressum fertig |
| M4 | So 17.01. | **Store-Einreichung + Public Launch** |

---

## 4. Woche für Woche

### Woche 0 – Startwoche (Do 22.10. – So 25.10.)
**Ziel:** Alles vorbereitet, damit Montag gecodet werden kann.
- [x] **Du:** Supabase-Konto anlegen (kostenlos) ✅ 22.10. (Region Irland, auch EU)
- [ ] **Du:** Klären, ob du für Gründung/Store-Konten jemanden über 18 brauchst (siehe Abschnitt 7) – mit Eltern sprechen (30 min)
- [ ] **Du:** Ideal-Kunde auf 1 Seite: wer, Alter, Level, Coach ja/nein, was nervt ihn (45 min)
- [ ] **Du:** Liste mit 5–10 Beta-Testern (Namen, Handy iOS/Android) (20 min)
- [x] **Claude:** Neuen Ordner `app/` im Repo anlegen, Flutter-Grundgerüst, Supabase verbinden ✅ 22.10. – Branch `flutter-app`; Verbindung wird aktiv, sobald dein Supabase-Projekt steht (Anleitung: `supabase/EINRICHTEN.md`)
**Zeit Du:** ~2,5 h

### Woche 1 (26.10. – 01.11.) – Fundament
- [x] **Claude:** Datenmodell: Nutzer, Einheiten, geplante Einheiten, Kalender, Coach-Verbindungen ✅ inkl. Zugriffsregeln, getestet
- [x] **Claude:** Login mit E-Mail, „Mit Apple anmelden", „Mit Google anmelden" ✅ Code fertig; Apple/Google brauchen noch die Zugangsdaten aus den Store-Konten (W7)
- [x] **Claude:** App-Gerüst mit Tabs (Heute · Kalender · Eintragen · Fortschritt · Einstellungen) + 4 Designs übernehmen ✅
- [ ] **Du:** Web-Version auf PC + Handy öffnen, Account anlegen, Design-Feedback (1,5 h)
- [ ] **Du:** Entscheiden: App-Name bleibt „TriCoach"? Domain prüfen + sichern (30 min)
**Zeit Du:** ~4 h

### Woche 2 (02.11. – 08.11.) – Trainings eintragen + Sync
- [x] **Claude:** Log-Formular: Schwimmen (25 m / 50 m / Freiwasser, km selbst eintippen), Rad, Lauf, Athletik (Übungen, Sätze, Wdh, kg), Sonstiges (z. B. Kitesurfen), RPE, Notizen ✅
- [x] **Claude:** Offline-Speicher + automatischer Abgleich zwischen Geräten (Konflikte, Wiederholversuche) ✅ mit Tests für offline, Konflikte, 450 Einträge
- [x] **Claude:** Import deiner alten Daten aus der Web-App (Sicherungsdatei) ✅ ohne Doppelte, inkl. Korrekturen und Profilwerte
- [ ] **Du:** Einheit am Handy eintragen → am PC prüfen → am iPad bearbeiten → Handy prüfen. Flugmodus-Test. (1,5 h)
**Zeit Du:** ~5 h

### Woche 3 (09.11. – 15.11.) – Uhr-Daten automatisch
- [x] **Claude:** Apple Health (iOS) + Health Connect (Android): Einheiten mit Puls, Distanz, Dauer automatisch holen ✅ Code + Berechtigungen; Praxistest am Handy durch dich
- [x] **Claude:** intervals.icu-Anbindung übernehmen + FIT-Datei-Import (Decoder aus `fit.js` portieren) ✅ getestet mit Dateien der Web-App
- [x] **Claude:** Doppelte Einheiten erkennen und zusammenführen ✅
- [ ] **Du:** Garmin Connect → Apple Health / Health Connect freigeben, 1 Woche normal trainieren und prüfen, ob alles ankommt (1 h + nebenbei)
**Zeit Du:** ~4 h

### Woche 4 (16.11. – 22.11.) – Kalender-Sync ⭐ (Killer-Feature)
- [x] **Claude:** Trainings automatisch in Geräte-Kalender schreiben (Apple Kalender / Google Kalender), Änderungen + Löschungen werden mitgezogen ✅
- [x] **Claude:** Persönlicher Abo-Link (.ics) für PC/Outlook/alle anderen ✅ Server-Funktion + „Neuen Link erzeugen“
- [x] **Claude:** Kalender-Ansichten Tag/Woche/Monat aus der Web-App übertragen ✅ Monat (mit KW) · Woche · Liste
- [ ] **Du:** Auf iPhone UND einem Android-Handy (Familie/Freunde) testen (2 h)
- [ ] 🏁 **M1 Alpha erreicht**
**Zeit Du:** ~5 h

### Woche 5 (23.11. – 29.11.) – Analysen & Fortschritt
- [x] **Claude:** Form-Kurve (TSS/PMC), VO2 Max, Wochenringe, Serien, Trends, Bestleistungen, Jahresziele ✅
- [x] **Claude:** „Mein Tag"-Startseite (Training + Termine des Tages) ✅
- [ ] **Du:** Zahlen mit Garmin Connect / TrainingPeaks vergleichen – stimmen sie? (1,5 h)
**Zeit Du:** ~4 h

### Woche 6 (30.11. – 06.12.) – Coach-Funktion
- [x] **Claude:** Trainer laden Athleten per Link ein, sehen deren Einheiten, tragen Plan-Einheiten ein ✅ per Einladungscode
- [x] **Claude:** Trainer-Ansicht (alle Athleten auf einen Blick, Ampel: erledigt / verpasst) ✅
- [x] **Claude:** TrainingPeaks-Brücke: FIT-Export ✅ (byte-gleich mit der Web-App) + Sammel-ZIP + Apple-Health-Weg ✅ 22.10. · Plan der Trainerin automatisch in der App ✅
- [ ] **Du:** 30 min mit deiner Trainerin: Was braucht sie? Was nervt sie an TrainingPeaks? Notizen machen (1 h)
**Zeit Du:** ~4 h

### Woche 7 (07.12. – 13.12.) – Beta raus 🚀
- [ ] **Du:** Apple Developer Account + Google Play Developer Account anlegen (siehe Abschnitt 7) (1,5 h)
- [ ] **Claude:** Cloud-Builds einrichten ✅ (GitHub baut Web, Android und iOS bei jedem Push) · TestFlight + Play-Test-Spur + Web veröffentlichen ⏳ braucht deine Store-Konten
- [x] **Claude:** Einladungstext für Tester + kurzer Feedback-Fragebogen (5 Fragen) ✅ `launch/01-…`
- [ ] **Du:** Beta-Tester einladen und beim Installieren helfen (2 h)
- [ ] 🏁 **M2 Beta 1 erreicht**
**Zeit Du:** ~5 h

### Woche 8 (14.12. – 20.12.) – Feedback-Runde 1
- [ ] **Du:** Mit jedem Tester 10 min sprechen: Was war nervig? Was fehlt? Würdest du dafür zahlen? (2 h)
- [ ] **Claude:** Top-5-Probleme fixen, Fehler-Tracking (Sentry) auswerten, Sync-Robustheit
- [ ] **Du:** Entscheiden, was in Version 1.0 kommt und was warten muss (30 min)
**Zeit Du:** ~4 h

### Woche 9 (21.12. – 27.12.) – Puffer (Weihnachten) 🎄
- [ ] Liegengebliebenes aufholen
- [x] **Optional:** Schule-Modul (WebUntis) als freiwilliges Extra für Schüler ✅ 22.10. vorgezogen
- [ ] **Du:** Wenn Zeit: erste 3 Social-Media-Clips drehen (Training + App im Einsatz)
**Zeit Du:** flexibel

### Woche 10 (28.12. – 03.01.) – Geld & Recht
- [ ] **Claude:** Abo-System (Free / Premium / Coach), Bezahl-Seite, 14 Tage gratis testen
- [x] **Claude:** Entwürfe für Datenschutzerklärung, Impressum, AGB, Einwilligung für Gesundheitsdaten ✅ `launch/03-…` + „Account löschen“ in der App
- [ ] **Du:** Entwürfe mit Eltern durchgehen; prüfen lassen (z. B. IHK-Gründungsberatung, kostenlos) (2 h)
- [ ] **Du:** Bankkonto/Auszahlungskonto für Store-Einnahmen klären (1 h)
- [ ] 🏁 **M3 erreicht**
**Zeit Du:** ~5 h

### Woche 11 (04.01. – 10.01.) – Launch vorbereiten
- [x] **Claude:** Einführung beim ersten Öffnen (Onboarding: Uhr verbinden, Kalender verbinden, fertig) ✅ inkl. Einwilligung
- [x] **Claude:** Landing Page (Problem → Lösung → Download) + Store-Texte (DE/EN) ✅ `launch/landing/`, `launch/02-…`
- [ ] **Du:** Store-Screenshots machen, 5 Reels/TikToks schneiden (siehe Abschnitt 6) (3 h)
- [ ] **Du:** Testimonials: Trainerin + 2 Athleten (kurzes Video oder Zitat) (1 h)
**Zeit Du:** ~5 h

### Woche 12 (11.01. – 17.01.) – Launch 🏁
- [ ] **Claude:** Letzte Fehler fixen, Release-Builds, Store-Einreichung
- [ ] **Du:** Go/No-Go-Check (Abschnitt 8), Beta-Tester bitten, Bewertungen zu schreiben
- [ ] **Du:** Launch-Post auf Instagram + TikTok, Club + Trainerin informieren
- [ ] 🏁 **M4 Launch**
**Zeit Du:** ~5 h

> **Hinweis:** Apple prüft Apps meist in 1–3 Tagen, kann aber ablehnen (z. B. wegen Gesundheitsdaten-Texten). Darum ist Woche 9 Puffer – nicht verplanen.

---

## 5. Preise (Start-Modell)

| Plan | Preis | Inhalt |
|---|---|---|
| **Free** | 0 € | Eintragen, Uhr-Sync, Kalender-Sync, Basis-Verlauf |
| **Premium** | 4,99 €/Monat oder 39,99 €/Jahr | Form-Kurve, VO2-Max-Trend, Belastungs-Warnung, Bestleistungen, Jahresziele |
| **Coach** | 14,99 €/Monat | Unbegrenzt Athleten, Trainer-Ansicht, Plan eintragen |
| **Club** | später | Ab Version 1.x, wenn Coach-Plan läuft |

- Beta-Tester: Premium 6 Monate gratis (Dankeschön + Bewertungen)
- Apple/Google behalten 15 % (Kleinunternehmer-Programm) – in der Rechnung mitdenken

---

## 6. Social Media (startet Woche 9, läuft ab Launch) – 10 fertige Skripte: `launch/04-social-media-skripte.md`

**Plattformen:** Instagram Reels + TikTok · **Takt:** 3 Clips/Woche, 15–30 Sek.

| Säule | Beispiel |
|---|---|
| **Problem** | „Wenn dein Training wieder nicht synchronisiert …" (Frust-Moment, dann TriCoach) |
| **Behind the Build** | „Ich bin Schüler und baue eine Triathlon-App" – Woche für Woche |
| **Daten-Story** | Deine Form-Kurve vor einem Wettkampf, VO2 Max über Monate |
| **Feature in 15 Sek** | Training beendet → 10 Sek später im Kalender |
| **Community** | Beta-Tester zeigen ihre Woche |

„Behind the Build" ist dein stärkster Hook: junger Athlet + eigene App = Geschichte, die Leute verfolgen wollen.

---

## 7. Rechtliches & Konten (wichtig – nicht überspringen)

- **Alter:** Apple Developer Program, Google Play Console und Zahlungsdienste verlangen Volljährigkeit. Falls du unter 18 bist: Konten und ggf. Gewerbe laufen über ein Elternteil, oder du brauchst die Zustimmung der Eltern + Genehmigung vom Familiengericht für ein eigenes Gewerbe. → In Woche 0 klären.
- **Kosten (ca., beim Anlegen prüfen):** Apple Developer ~99 $/Jahr · Google Play ~25 $ einmalig · Domain ~10 €/Jahr · Supabase, RevenueCat, Sentry: kostenlos im Startumfang
- **Gewerbe:** Spätestens vor dem ersten Euro Einnahmen anmelden (Gewerbeamt, ~20–40 €). Kleinunternehmerregelung prüfen.
- **Datenschutz:** Puls- und Trainingsdaten sind **Gesundheitsdaten** (DSGVO). Pflicht: Einwilligung beim Start, Datenschutzerklärung, Server in der EU, Daten löschbar.
- **Impressum** auf Landing Page und im Store.
- **Abhängigkeiten:** TrainingPeaks hat keine offene Schnittstelle, WebUntis-Zugang ist inoffiziell → beides als „Brücke/Extra" behandeln, nicht als Kern.

---

## 8. Go/No-Go-Check vor dem Launch

- [ ] Einheit auf Gerät A eingetragen erscheint in < 10 Sek auf Gerät B
- [ ] Uhr-Einheit kommt automatisch an (iOS + Android getestet)
- [ ] Training erscheint automatisch im Apple- und Google-Kalender
- [ ] App läuft offline und gleicht danach korrekt ab
- [ ] Keine Abstürze in den letzten 7 Tagen (Sentry)
- [ ] Mind. 5 Beta-Tester nutzen die App 3×/Woche
- [ ] Abo kaufen + kündigen funktioniert (Test-Käufe)
- [ ] Datenschutz, Impressum, AGB online
- [ ] Store-Einträge + Screenshots fertig

---

## 9. Ideen-Parkplatz (nach dem Launch)

1. Ironman-/Wettkampf-Programm mit Weg zum Ziel
2. Ernährungsplan (Fueling ist in der Web-App schon angelegt)
3. KI-Coach in der App (Claude-Anbindung)
4. Club-Plan mit Admin-Ansicht
5. Garmin-Direktanbindung über das offizielle Garmin-Entwicklerprogramm (braucht Gewerbe)
6. Englische Version / internationale Stores
7. Fußball- oder andere Sportarten-Module

**Regel:** Neue Idee? → hier eintragen, nicht in die laufende Woche.

---

## 10. Wöchentlicher Ablauf mit Claude

Jeden Sonntag (15 min):
1. „Claude, TriCoach Woche X – was steht an?"
2. Kurz berichten: was getestet, was kaputt, was Tester gesagt haben
3. Claude baut die Woche, du testest unter der Woche
4. Haken im Plan setzen ✅

## Kennzahlen

| Phase | Ziel |
|---|---|
| Beta (Dez) | 5–10 Tester, 3× Nutzung/Woche, Sync-Fehler < 1 % |
| Launch + 4 Wochen | 100 Downloads, 10 zahlende Nutzer |
| Launch + 6 Monate | 500 Nutzer, 50 zahlende, 3 Trainer im Coach-Plan |
