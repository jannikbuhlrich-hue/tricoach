import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tricoach/core/models.dart';
import 'package:tricoach/core/sport.dart';
import 'package:tricoach/data/local_store.dart';
import 'package:tricoach/main.dart';
import 'package:tricoach/state/app_state.dart';

/// Wie pumpAndSettle, bricht aber nach 15 s (Test-Zeit) mit Hinweis auf den Schritt ab statt zu hängen
Future<void> settle(WidgetTester t, String step) async {
  // ignore: avoid_print
  print('Schritt: $step');
  try {
    await t.pumpAndSettle(const Duration(milliseconds: 100), EnginePhase.sendSemanticsUpdate, const Duration(seconds: 15));
  } catch (e) {
    fail('Oberfläche kommt nicht zur Ruhe bei „$step“: $e');
  }
}

/// Oberflächentest im Nur-dieses-Gerät-Modus (ohne Server):
/// Einführung durchklicken, alle Tabs öffnen, eine Einheit eintragen.
void main() {
  testWidgets('Einführung, Tabs und Eintragen funktionieren', (tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final state = AppState(MemoryStore());
    await tester.runAsync(state.init);
    await tester.pumpWidget(TriCoachApp(state: state));
    await settle(tester, 'Schritt 1');

    // Einführung: ohne Einwilligung kein Weiter
    expect(find.text('Willkommen bei TriCoach'), findsOneWidget);
    await tester.tap(find.byType(Checkbox));
    await tester.pump();
    for (var i = 0; i < 3; i++) {
      await tester.tap(find.text('Weiter'));
      await settle(tester, 'Schritt 2');
    }
    await tester.tap(find.text("Los geht's"));
    await settle(tester, 'Schritt 3');

    // Mein Tag
    expect(find.text('Heute'), findsWidgets);
    expect(find.text('Noch keine Einheiten'), findsOneWidget);

    // Eintragen: Schwimmen, 2,35 km in 50 min
    await tester.tap(find.text('Eintragen').last);
    await settle(tester, 'Schritt 4');
    expect(find.text('Einheit eintragen'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, 'Dauer (h:mm)'), '0:50');
    await tester.enterText(find.widgetWithText(TextField, 'Geschwommen (km)'), '2,35');
    await tester.pump();
    expect(find.textContaining('/100m'), findsOneWidget);
    await tester.tap(find.text('Sichern'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await settle(tester, 'Schritt 5');
    expect(state.activities.length, 1);
    expect(state.activities.single.distanceM, 2350);
    expect(state.activities.single.sport, Sport.swim);
    expect(state.activities.single.durationS, 3000);

    // Alle Tabs öffnen
    for (final tab in ['Kalender', 'Fortschritt', 'Einstellungen', 'Heute']) {
      await tester.tap(find.text(tab).last);
      await settle(tester, 'Schritt 6');
    }
    expect(find.text('Schwimmen'), findsWidgets);

    await tester.pumpWidget(const SizedBox());
    state.dispose();
  });

  testWidgets('Fortschritt mit Daten und Design-Wechsel', (tester) async {
    tester.view.physicalSize = const Size(2400, 1600);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    final store = MemoryStore();
    await store.setMeta('onboarded', true);
    final state = AppState(store);
    await tester.runAsync(() async {
      await state.init();
      final now = DateTime.now();
      await state.repo.saveActivities([
        for (var i = 0; i < 60; i++)
          Activity(
            id: 'a$i',
            sport: Sport.values[i % 3],
            start: now.subtract(Duration(days: i, hours: 2)).toUtc(),
            durationS: 3000 + i * 10,
            distanceM: [2000.0, 40000.0, 10000.0][i % 3],
            rpe: 5,
          ),
      ]);
      await state.repo.savePlanned(PlannedSession(id: 'p1', startsAt: now.add(const Duration(days: 1)).toUtc(), sport: Sport.run, title: 'Schwelle 5×1 km', minutes: 60));
    });
    await tester.pumpWidget(TriCoachApp(state: state));
    await settle(tester, 'Schritt 7');

    // Breiter Bildschirm → Navigation links
    expect(find.byType(NavigationRail), findsOneWidget);
    await tester.tap(find.text('Fortschritt'));
    await settle(tester, 'Schritt 8');
    expect(find.text('Form-Kurve'), findsOneWidget);
    expect(find.text('VO2 Max'), findsOneWidget);

    await tester.tap(find.text('Einstellungen'));
    await settle(tester, 'Schritt 9');
    await tester.tap(find.text('Nordsee'));
    await settle(tester, 'Schritt 10');
    expect(state.design.name, 'nordsee');

    await tester.tap(find.text('Kalender'));
    await settle(tester, 'Schritt 11');
    await tester.tap(find.text('Woche'));
    await settle(tester, 'Schritt 12');
    await tester.tap(find.text('Liste'));
    await settle(tester, 'Schritt 13');
    expect(find.text('Schwelle 5×1 km'), findsWidgets);

    await tester.pumpWidget(const SizedBox());
    state.dispose();
  });
}
