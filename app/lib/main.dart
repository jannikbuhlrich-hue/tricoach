import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config.dart';
import 'data/local_store.dart';
import 'state/app_state.dart';
import 'ui/home_shell.dart';
import 'ui/screens/onboarding_screen.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Lizenz der eingebauten Schrift (erscheint unter Einstellungen → Open-Source-Lizenzen)
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks(const ['Roboto (Schrift)'], await rootBundle.loadString('assets/fonts/OFL.txt'));
  });
  if (AppConfig.hasBackend) {
    await Supabase.initialize(url: AppConfig.supabaseUrl, publishableKey: AppConfig.supabaseAnonKey);
  }
  final state = AppState(await SembastStore.open());
  await state.init();
  runApp(TriCoachApp(state: state));
}

class TriCoachApp extends StatelessWidget {
  const TriCoachApp({super.key, required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    return AppScope(
      state: state,
      child: Builder(builder: (context) {
        final app = AppScope.of(context);
        return MaterialApp(
          title: 'TriCoach',
          debugShowCheckedModeBanner: false,
          theme: buildTheme(app.design),
          locale: const Locale('de', 'DE'),
          supportedLocales: const [Locale('de', 'DE'), Locale('en')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: app.onboarded ? const HomeShell() : const OnboardingScreen(),
        );
      }),
    );
  }
}
