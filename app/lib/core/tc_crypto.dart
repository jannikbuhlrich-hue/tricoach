import 'dart:convert';

import 'package:cryptography/cryptography.dart';

/// Ver- und Entschlüsselung im gleichen Format wie tools/untis-sync.mjs und die Web-App (js/school.js):
/// `{"v":1,"salt":…,"iv":…,"ct":…}` (Base64), AES-256-GCM, Schlüssel per PBKDF2-SHA256 mit 120 000 Runden.
/// `ct` enthält – wie bei Web Crypto – am Ende die 16 Byte Prüfsumme (GCM-Tag).
///
/// Damit liest die App den Stundenplan (Branch „schule-daten“) und den TrainingPeaks-Plan (Branch „tp-daten“),
/// die der GitHub-Job verschlüsselt ablegt. Lesen kann sie nur, wer den TriCoach-Schlüssel (Secret TRICOACH_KEY) kennt.
class TcCrypto {
  TcCrypto._();

  static const iterations = 120000;
  static final _pbkdf2 = Pbkdf2(macAlgorithm: Hmac.sha256(), iterations: iterations, bits: 256);
  static final _aes = AesGcm.with256bits();

  /// Abgeleitete Schlüssel je Passwort + Salz. Das Salz ist seit 2.6 fest → die teure Ableitung passiert nur einmal.
  static final Map<String, List<int>> _cache = {};

  static String _ck(String pass, String saltB64) => '$pass|$saltB64';

  /// Schlüssel aus einer früheren Sitzung wieder einsetzen (spart die Ableitung beim App-Start)
  static void remember(String pass, String saltB64, List<int> key) => _cache[_ck(pass, saltB64)] = key;

  static Future<List<int>> deriveKey(String pass, List<int> salt) async {
    final ck = _ck(pass, base64.encode(salt));
    final hit = _cache[ck];
    if (hit != null) return hit;
    final k = await _pbkdf2.deriveKey(secretKey: SecretKey(utf8.encode(pass)), nonce: salt);
    final bytes = await k.extractBytes();
    _cache[ck] = bytes;
    return bytes;
  }

  /// Salz einer verschlüsselten Datei (Base64), z. B. um den abgeleiteten Schlüssel zu speichern
  static String saltOf(String txt) => (jsonDecode(txt) as Map)['salt'] as String;

  /// Entschlüsseln. Wirft [TcKeyError], wenn der Schlüssel nicht passt, und [FormatException] bei kaputten Dateien.
  static Future<Object?> decrypt(String txt, String pass) async {
    final Map o;
    try {
      o = jsonDecode(txt) as Map;
    } catch (_) {
      throw const FormatException('Datei ist nicht im TriCoach-Format');
    }
    final salt = base64.decode(o['salt'] as String), iv = base64.decode(o['iv'] as String), ct = base64.decode(o['ct'] as String);
    if (ct.length < 16) throw const FormatException('Datei ist unvollständig');
    final key = await deriveKey(pass, salt);
    final box = SecretBox(ct.sublist(0, ct.length - 16), nonce: iv, mac: Mac(ct.sublist(ct.length - 16)));
    final List<int> clear;
    try {
      clear = await _aes.decrypt(box, secretKey: SecretKey(key));
    } on SecretBoxAuthenticationError {
      throw const TcKeyError();
    }
    return jsonDecode(utf8.decode(clear));
  }

  /// Verschlüsseln (für Tests und Werkzeuge). Ohne [salt] dasselbe feste Salz wie der GitHub-Job.
  static Future<String> encrypt(Object? obj, String pass, {List<int>? salt, List<int>? iv}) async {
    final s = salt ?? await fixedSalt();
    final key = await deriveKey(pass, s);
    final box = await _aes.encrypt(utf8.encode(jsonEncode(obj)), secretKey: SecretKey(key), nonce: iv ?? _aes.newNonce());
    return jsonEncode({'v': 1, 'salt': base64.encode(s), 'iv': base64.encode(box.nonce), 'ct': base64.encode([...box.cipherText, ...box.mac.bytes])});
  }

  /// SHA-256('TriCoach-Salz-v1'), erste 16 Byte – wie SALT in tools/untis-sync.mjs
  static Future<List<int>> fixedSalt() async => (await Sha256().hash(utf8.encode('TriCoach-Salz-v1'))).bytes.sublist(0, 16);
}

class TcKeyError implements Exception {
  const TcKeyError();
  @override
  String toString() => 'Schlüssel passt nicht zum GitHub-Secret TRICOACH_KEY';
}
