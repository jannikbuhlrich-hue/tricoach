/// Sportarten wie in der Web-App: die drei Triathlon-Disziplinen plus Athletik und Sonstiges.
enum Sport {
  swim('Schwimmen', 'Schwimmen'),
  bike('Rad', 'Radfahrt'),
  run('Laufen', 'Lauf'),
  strength('Athletik', 'Athletik'),
  other('Sonstiges', 'Training');

  const Sport(this.label, this.defaultTitle);

  /// Anzeigename (z. B. „Rad“)
  final String label;

  /// Standard-Titel einer neuen Einheit (z. B. „Radfahrt“)
  final String defaultTitle;

  bool get hasDistance => this == swim || this == bike || this == run;
  bool get isTriathlon => this == swim || this == bike || this == run;

  static Sport parse(String? s) => Sport.values.firstWhere((x) => x.name == s, orElse: () => Sport.other);
}

/// Wo geschwommen wurde: 25-m-Bahn, 50-m-Bahn oder Freiwasser.
enum SwimWhere {
  pool25('25', '25-m-Bahn', 25),
  pool50('50', '50-m-Bahn', 50),
  openWater('ow', 'Freiwasser', null);

  const SwimWhere(this.code, this.label, this.poolLength);
  final String code;
  final String label;
  final int? poolLength;

  static SwimWhere? parse(Object? v) {
    final s = v?.toString();
    for (final w in SwimWhere.values) {
      if (w.code == s) return w;
    }
    return null;
  }
}

/// Vorschläge für „Sonstiges“ (wie in der Web-App)
const otherTypes = [
  'Kitesurfen', 'Windsurfen', 'Surfen', 'SUP', 'Wandern', 'Spaziergang', 'Rudern', 'Klettern',
  'Yoga', 'Ski', 'Fußball', 'Tennis', 'Inlineskaten', 'Kanu', 'Segeln', 'Koppeltraining',
];

const rpeText = ['', 'sehr leicht', 'leicht', 'leicht', 'moderat', 'moderat', 'etwas hart', 'hart', 'sehr hart', 'extrem hart', 'maximal'];
