import 'package:flutter/material.dart';

import '../../config.dart';
import '../theme.dart';
import '../widgets.dart';

Future<void> openLegal(BuildContext context) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const LegalScreen()));

void openLicenses(BuildContext context) => showLicensePage(
      context: context,
      applicationName: 'TriCoach',
      applicationVersion: AppConfig.appVersion,
      applicationLegalese: 'Enthält Open-Source-Software. Die Lizenzen der einzelnen Bausteine stehen unten.',
    );

/// Rechtliches: Lizenzen, Marken, Hinweise zu Schule (Beta), Training und Datenschutz.
class LegalScreen extends StatelessWidget {
  const LegalScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final c = TriColors.of(context);
    Widget p(String t) => Padding(padding: const EdgeInsets.only(bottom: 6), child: Text(t, style: TextStyle(color: c.muted, height: 1.4)));
    return Scaffold(
      appBar: AppBar(title: const Text('Rechtliches & Lizenzen')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 40), children: [
            TriCard(
              title: 'Open-Source-Lizenzen',
              icon: Icons.description_rounded,
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                p('TriCoach baut auf freier Software auf (u. a. Flutter, Supabase, Sembast, die Schrift Roboto). '
                    'Alle Bausteine erlauben die Nutzung in kommerziellen Apps; ihre Lizenzen sind hier vollständig aufgeführt.'),
                Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton.tonalIcon(onPressed: () => openLicenses(context), icon: const Icon(Icons.list_alt_rounded), label: const Text('Lizenzen anzeigen')),
                ),
              ]),
            ),
            const SizedBox(height: 12),
            TriCard(
              title: 'Marken',
              icon: Icons.copyright_rounded,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                p('Garmin, Forerunner und Garmin Connect, TrainingPeaks, WebUntis und Untis, intervals.icu, Apple Health, HealthKit und Siri, '
                    'Health Connect und Android sowie Zwift sind Marken ihrer jeweiligen Inhaber.'),
                p('TriCoach ist ein unabhängiges Projekt und steht mit keinem dieser Unternehmen in Verbindung. '
                    'Die Namen werden nur genannt, um zu beschreiben, womit TriCoach zusammenarbeitet. '
                    'TriCoach verarbeitet dabei ausschließlich Daten, die du selbst freigibst.'),
                p('Daten von Garmin-Geräten sind in der App als „Garmin …“ gekennzeichnet.'),
              ]),
            ),
            const SizedBox(height: 12),
            TriCard(
              title: 'Schule (Beta)',
              icon: Icons.school_rounded,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                p('Die WebUntis-Verbindung meldet sich mit deinen eigenen Zugangsdaten so an wie die Untis-App. '
                    'Sie ist keine offizielle Schnittstelle der Untis GmbH, kann sich ändern oder ausfallen und lässt sich jederzeit trennen.'),
                p('Verbindlich sind immer die Angaben in WebUntis und die Ankündigungen deiner Schule.'),
                p('Dein WebUntis-Passwort wird nicht gespeichert. Gespeichert wird nur der App-Schlüssel – auf dem Server, nicht lesbar für die App, '
                    'und er wird gelöscht, wenn du die Verbindung trennst oder deinen Account löschst. Abrufe sind auf höchstens alle 15 Minuten begrenzt.'),
              ]),
            ),
            const SizedBox(height: 12),
            TriCard(
              title: 'Training & Gesundheit',
              icon: Icons.favorite_rounded,
              child: p('Form, Belastung, Prognosen und Empfehlungen in TriCoach sind Rechenwerte zur Orientierung. '
                  'Sie ersetzen keine ärztliche Untersuchung oder Beratung. Bei Schmerzen, Krankheit oder Unsicherheit: Training anpassen und ärztlich abklären.'),
            ),
            const SizedBox(height: 12),
            TriCard(
              title: 'Datenschutz in Kürze',
              icon: Icons.privacy_tip_rounded,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                p('Deine Daten liegen auf deinem Gerät und – mit Account – auf Servern in der EU (Supabase, Irland). Übertragung immer verschlüsselt.'),
                p('Keine Werbung, kein Tracking, keine Weitergabe. Die App lädt nichts von Google-Servern (Schriften und Programmteile sind eingebaut).'),
                p('Gesundheitsdaten (z. B. Puls) verarbeitet TriCoach nur mit deiner Einwilligung aus der Einführung. '
                    'Du kannst Verbindungen jederzeit trennen und deinen Account samt allen Daten unter Einstellungen › Account löschen.'),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}
