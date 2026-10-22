import 'package:http/http.dart' as http;

/// Verschlüsselte Dateien, die die GitHub-Jobs im Repo ablegen:
/// Branch „schule-daten“ (WebUntis, .github/workflows/schule.yml) und „tp-daten“ (TrainingPeaks, tp.yml).
/// raw.githubusercontent.com erlaubt Abrufe aus dem Browser (CORS) – klappt also auch in der Web-Version.
class GithubFeeds {
  GithubFeeds(this.repo, {http.Client? client}) : _client = client ?? http.Client();

  static const defaultRepo = 'jannikbuhlrich-hue/tricoach';
  static final _slug = RegExp(r'^[\w.-]+/[\w.-]+$');
  static bool validRepo(String s) => _slug.hasMatch(s.trim());

  final String repo;
  final http.Client _client;

  /// Inhalt der Datei, oder null, wenn es sie (noch) nicht gibt
  Future<String?> get(String branch, String file) async {
    // Minuten-Stempel gegen Zwischenspeicher – wie in der Web-App
    final u = Uri.parse('https://raw.githubusercontent.com/$repo/$branch/$file?t=${DateTime.now().millisecondsSinceEpoch ~/ 60000}');
    final r = await _client.get(u).timeout(const Duration(seconds: 20));
    if (r.statusCode == 404) return null;
    if (r.statusCode != 200) throw http.ClientException('GitHub antwortet mit ${r.statusCode}', u);
    return r.body;
  }

  Future<String?> school() => get('schule-daten', 'schule.enc');
  Future<String?> trainingPeaks() => get('tp-daten', 'tp.enc');
}
