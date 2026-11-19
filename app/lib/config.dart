/// Zugangsdaten zum Supabase-Projekt. Werden beim Bauen übergeben, nicht ins Repo geschrieben:
///   flutter run --dart-define=SUPABASE_URL=https://xyz.supabase.co --dart-define=SUPABASE_ANON_KEY=eyJ...
/// Der „anon key“ ist öffentlich (steckt in jeder App) – geschützt wird über die Zugriffsregeln in der Datenbank.
/// Ohne diese Werte läuft TriCoach im Nur-dieses-Gerät-Modus (alles lokal, kein Login).
class AppConfig {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
  static bool get hasBackend => supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;

  /// Rücksprung nach „Mit Apple/Google anmelden“ in die App (iOS/Android)
  static const authRedirect = 'app.tricoach://login-callback';

  /// Kalender-Abo-Link für PC/Outlook/Google
  static String calendarFeedUrl(String token) => '$supabaseUrl/functions/v1/calendar?token=$token';

  /// „Mit Apple/Google anmelden“ erst zeigen, wenn der Anbieter in Supabase eingerichtet ist (braucht die Store-Konten)
  static const appleLogin = bool.fromEnvironment('APPLE_LOGIN');
  static const googleLogin = bool.fromEnvironment('GOOGLE_LOGIN');

  static const appVersion = '3.0.0';
}
