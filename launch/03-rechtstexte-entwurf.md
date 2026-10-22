# Rechtstexte – ENTWÜRFE (Plan Woche 10)

> **Wichtig:** Das sind Entwürfe als Startpunkt, keine Rechtsberatung. Vor dem Launch von einer fachkundigen Stelle prüfen lassen
> (z. B. IHK-Gründungsberatung, Datenschutz-Generator wie e-recht24 bzw. Dr. Schwenke, oder Anwalt).
> Platzhalter in [eckigen Klammern] ausfüllen. Wer Betreiber ist (du oder ein Elternteil), hängt von Abschnitt 7 im Plan ab.

---

## Impressum (Vorlage)

Angaben gemäß § 5 DDG

[Vor- und Nachname des Betreibers]
[Straße Hausnummer]
[PLZ Ort]
Deutschland

Kontakt: E-Mail: [kontakt@…] · Telefon: [optional, aber empfohlen]

[Falls Gewerbe mit Umsatzsteuer-ID: Umsatzsteuer-Identifikationsnummer gemäß § 27a UStG: …]
[Falls Kleinunternehmer: kein Ausweis von Umsatzsteuer gemäß § 19 UStG]

Verantwortlich für den Inhalt nach § 18 Abs. 2 MStV: [Name, Adresse wie oben]

Verbraucherstreitbeilegung: Wir sind nicht bereit und nicht verpflichtet, an Streitbeilegungsverfahren vor einer Verbraucherschlichtungsstelle teilzunehmen.

---

## Einwilligung Gesundheitsdaten (steht so schon in der App-Einführung)

> Ich willige ein, dass TriCoach meine Trainings- und Gesundheitsdaten (z. B. Puls) speichert und verarbeitet, um mir Analysen anzuzeigen. Widerruf jederzeit in den Einstellungen.

Rechtsgrundlage: Art. 9 Abs. 2 lit. a DSGVO (ausdrückliche Einwilligung). Zeitpunkt der Einwilligung wird im Profil gespeichert (`health_consent_at`).
**Widerruf:** Einstellungen → Account → „Account löschen“ entfernt Account und alle Daten auf Server und Gerät (eingebaut). Ein reiner Widerruf ohne Löschung (Apple Health/Health Connect ausschalten) geht im Bereich „Uhr“.

---

## Datenschutzerklärung (Entwurf)

### 1. Verantwortlicher
[Name, Adresse, E-Mail wie im Impressum]

### 2. Welche Daten wir verarbeiten
- **Account:** E-Mail-Adresse, Passwort (nur verschlüsselt gespeichert), bei „Mit Apple/Google anmelden“ die von dort übermittelte E-Mail und der Name.
- **Trainingsdaten:** Sportart, Datum, Dauer, Distanz, Anstrengung (RPE), Notizen, Übungen, geplante Einheiten und Termine.
- **Gesundheitsdaten:** Herzfrequenz (Durchschnitt/Maximum), Kalorien, aus Apple Health bzw. Health Connect gelesene Trainingseinheiten, Leistungswerte (Gewicht, FTP, Schwellenpuls, Ruhepuls).
- **Technische Daten:** Gerätetyp und Absturzberichte (ohne Trainingsinhalte), Zeitpunkt des letzten Abgleichs.

### 3. Zwecke und Rechtsgrundlagen
| Zweck | Rechtsgrundlage |
|---|---|
| Account und Abgleich zwischen deinen Geräten | Art. 6 Abs. 1 lit. b DSGVO (Vertrag) |
| Speichern und Auswerten von Gesundheitsdaten | Art. 9 Abs. 2 lit. a DSGVO (ausdrückliche Einwilligung) |
| Weitergabe an deinen Coach | Einwilligung durch Einlösen des Einladungscodes (jederzeit beendbar) |
| Fehleranalyse (Absturzberichte) | Art. 6 Abs. 1 lit. f DSGVO (berechtigtes Interesse an einer funktionierenden App) |
| Abrechnung von Abos | Art. 6 Abs. 1 lit. b DSGVO; Zahlung wickeln Apple bzw. Google ab |

### 4. Empfänger / Auftragsverarbeiter
- **Supabase Inc.** – Datenbank, Login und Server; Speicherort: Frankfurt am Main (EU). Auftragsverarbeitungsvertrag nach Art. 28 DSGVO: [abschließen – Supabase stellt einen DPA bereit].
- **Apple / Google** – nur wenn du Apple Health, Health Connect, „Mit Apple/Google anmelden“ oder In-App-Käufe nutzt; es gelten deren Datenschutzbestimmungen.
- **intervals.icu** – nur wenn du selbst einen API-Key einträgst; TriCoach liest dann deine Einheiten von dort.
- **Sentry** (sobald eingebaut) – Absturzberichte, Server in der EU [prüfen].
- **RevenueCat** (sobald Abos kommen) – Abo-Status, keine Trainingsdaten.
- Dein **Coach** – nur nach Einlösen seines Codes; er sieht deine Einheiten und Pläne, kann Einheiten nicht ändern.

Keine Weitergabe zu Werbezwecken, kein Tracking, kein Verkauf von Daten.

### 5. Kalender
Wenn du den Kalender einschaltest, legt TriCoach auf deinem Gerät einen eigenen Kalender „TriCoach“ an. Über den Abo-Link abgerufene Kalenderdaten enthalten Titel, Zeit, Dauer, Distanz, Puls und Notizen deiner Einheiten. Wer den Link kennt, kann diese Daten lesen – gib ihn nicht weiter; in den Einstellungen kannst du jederzeit einen neuen Link erzeugen.

### 6. Speicherdauer
Solange dein Account besteht. Nach Löschung des Accounts werden alle Trainings- und Gesundheitsdaten innerhalb von 30 Tagen gelöscht (Backups eingeschlossen). [Mit Supabase-Backup-Zeitraum abgleichen.]

### 7. Deine Rechte
Auskunft, Berichtigung, Löschung, Einschränkung, Datenübertragbarkeit (Export als Datei), Widerspruch, Widerruf der Einwilligung mit Wirkung für die Zukunft, Beschwerde bei einer Aufsichtsbehörde (z. B. [Landesdatenschutzbeauftragte deines Bundeslands]).
Kontakt: [E-Mail]

### 8. Minderjährige
[Mindestalter festlegen, z. B. 16 Jahre; darunter nur mit Zustimmung der Eltern – Art. 8 DSGVO.]

### 9. Sicherheit
Übertragung verschlüsselt (TLS). Zugriff auf Daten ist in der Datenbank pro Nutzer abgesichert (Row Level Security).

Stand: [Datum]

---

## Nutzungsbedingungen / AGB (Entwurf – Eckpunkte)

1. **Geltungsbereich:** Nutzung der App TriCoach (iOS, Android, Web, Desktop).
2. **Account:** Wahre Angaben; ein Account pro Person; Zugangsdaten geheim halten.
3. **Kostenlose Version und Premium:** Inhalte der Pläne laut Store-Beschreibung. Abos laufen über Apple bzw. Google; Laufzeit, Verlängerung und Kündigung richten sich nach deren Bedingungen (Kündigung in den Abo-Einstellungen des Stores). Kostenloser Testzeitraum 14 Tage.
4. **Keine medizinische Beratung:** TriCoach liefert Trainings-Analysen und Schätzungen (z. B. VO2 Max, Prognosen). Diese ersetzen keine ärztliche Untersuchung. Bei Beschwerden Training abbrechen und ärztlichen Rat einholen.
5. **Coach-Funktion:** Der Athlet entscheidet, wen er verbindet, und kann die Verbindung jederzeit beenden. Coaches sind für ihre Trainingsempfehlungen selbst verantwortlich.
6. **Verfügbarkeit:** Wir bemühen uns um hohe Verfügbarkeit, garantieren sie aber nicht. Die App funktioniert auch offline; der Abgleich holt nach.
7. **Haftung:** [Standard-Haftungsbeschränkung – unbedingt prüfen lassen.]
8. **Änderungen:** Änderungen werden in der App angekündigt.
9. **Recht:** Deutsches Recht; zwingende Verbraucherschutzvorschriften des Wohnsitzlandes bleiben unberührt.
