import 'package:flutter/material.dart';

import '../../data/device_calendar_sync.dart';
import '../../data/health_import.dart';
import '../../state/app_state.dart';
import '../theme.dart';
import '../widgets.dart';
import 'login_screen.dart';

/// Erster Start: Einwilligung, Uhr verbinden, Kalender verbinden, fertig.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  int step = 0;
  bool consent = false;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context), c = TriColors.of(context);
    final pages = <Widget>[
      _page(
        c,
        icon: Icons.waving_hand_rounded,
        title: 'Willkommen bei TriCoach',
        text: 'Dein Training an einem Ort: Uhr-Daten kommen automatisch, Trainings landen von selbst im Kalender, und dein Coach sieht alles – auf iPhone, Android und PC.',
        extra: CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          value: consent,
          onChanged: (v) => setState(() => consent = v ?? false),
          title: const Text('Ich willige ein, dass TriCoach meine Trainings- und Gesundheitsdaten (z. B. Puls) speichert und verarbeitet, um mir Analysen anzuzeigen. Widerruf jederzeit in den Einstellungen.'),
          controlAffinity: ListTileControlAffinity.leading,
        ),
      ),
      _page(
        c,
        icon: Icons.watch_rounded,
        title: 'Uhr verbinden',
        text: HealthImport.supported
            ? 'Garmin, Apple Watch, Coros, Polar & Co. schreiben deine Einheiten in ${Theme.of(context).platform == TargetPlatform.iOS ? 'Apple Health' : 'Health Connect'}. TriCoach holt sie dort automatisch ab – mit Puls, Distanz und Dauer.'
            : 'Am PC und im Browser kommen Uhr-Daten über intervals.icu (kostenlos, verbindet sich mit Garmin Connect). Den API-Key trägst du später in den Einstellungen ein.',
        extra: HealthImport.supported
            ? FilledButton.icon(
                onPressed: app.healthOn
                    ? null
                    : () async {
                        final ok = await app.enableHealth();
                        if (!ok && context.mounted) showMsg(context, 'Kein Zugriff – geht auch später in den Einstellungen.');
                      },
                icon: Icon(app.healthOn ? Icons.check_rounded : Icons.link_rounded),
                label: Text(app.healthOn ? 'Verbunden' : 'Jetzt verbinden'),
              )
            : null,
      ),
      _page(
        c,
        icon: Icons.event_available_rounded,
        title: 'Kalender',
        text: DeviceCalendarSync.supported
            ? 'Geplante und erledigte Einheiten erscheinen in einem eigenen Kalender „TriCoach“ – Änderungen werden automatisch nachgezogen.'
            : 'Nach dem Anmelden bekommst du in den Einstellungen einen Abo-Link für Outlook und Google Kalender.',
        extra: DeviceCalendarSync.supported
            ? FilledButton.icon(
                onPressed: app.calendarOn ? null : () => app.enableCalendar(),
                icon: Icon(app.calendarOn ? Icons.check_rounded : Icons.event_rounded),
                label: Text(app.calendarOn ? 'Eingerichtet' : 'Kalender einrichten'),
              )
            : null,
      ),
      _page(
        c,
        icon: Icons.cloud_done_rounded,
        title: app.localOnly ? 'Fertig' : 'Auf allen Geräten',
        text: app.localOnly
            ? 'Alles ist eingerichtet. Los geht\'s!'
            : 'Mit einem Account sind deine Einheiten auf jedem Gerät gleich. Ohne Account bleibt alles nur auf diesem Gerät.',
        extra: app.localOnly || app.signedIn
            ? null
            : FilledButton(onPressed: () => openLogin(context), child: const Text('Anmelden oder registrieren')),
      ),
    ];
    final last = step == pages.length - 1;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(children: [
                Row(children: [
                  for (var i = 0; i < pages.length; i++)
                    Expanded(child: Container(height: 4, margin: const EdgeInsets.symmetric(horizontal: 3), decoration: BoxDecoration(color: i <= step ? c.accent : c.surface2, borderRadius: BorderRadius.circular(4)))),
                ]),
                Expanded(child: SingleChildScrollView(child: pages[step])),
                Row(children: [
                  if (step > 0) TextButton(onPressed: () => setState(() => step--), child: const Text('Zurück')),
                  const Spacer(),
                  FilledButton(
                    onPressed: step == 0 && !consent
                        ? null
                        : () {
                            if (last) {
                              app.finishOnboarding();
                            } else {
                              setState(() => step++);
                            }
                          },
                    child: Text(last ? 'Los geht\'s' : (step == 0 ? 'Weiter' : 'Weiter')),
                  ),
                ]),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  Widget _page(TriColors c, {required IconData icon, required String title, required String text, Widget? extra}) => Padding(
        padding: const EdgeInsets.only(top: 48),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(color: c.accent.withValues(alpha: .15), borderRadius: BorderRadius.circular(18)),
            child: Icon(icon, color: c.accent, size: 34),
          ),
          const SizedBox(height: 20),
          Text(title, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          Text(text, style: TextStyle(fontSize: 16, color: c.muted, height: 1.4)),
          if (extra != null) ...[const SizedBox(height: 20), extra],
        ]),
      );
}
