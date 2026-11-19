import 'dart:convert';
import 'dart:typed_data';

/// ZIP ohne Kompression (wie makeZip() in js/tp.js) – reicht für FIT-Dateien, keine Bibliothek nötig.
/// Dateinamen in UTF-8 (Bit 11), damit Umlaute in Windows, macOS und iOS-„Dateien“ richtig ankommen.

final _crcTable = List<int>.generate(256, (n) {
  var c = n;
  for (var k = 0; k < 8; k++) {
    c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1;
  }
  return c;
});

int crc32(List<int> b) {
  var c = 0xFFFFFFFF;
  for (final x in b) {
    c = _crcTable[(c ^ x) & 0xFF] ^ (c >> 8);
  }
  return (c ^ 0xFFFFFFFF) & 0xFFFFFFFF;
}

Uint8List makeZip(List<(String, List<int>)> files, {DateTime? at}) {
  final now = at ?? DateTime.now();
  final dosT = (now.hour << 11) | (now.minute << 5) | (now.second >> 1);
  final dosD = ((now.year - 1980) << 9) | (now.month << 5) | now.day;
  final out = BytesBuilder(copy: false), central = BytesBuilder(copy: false);
  void u16(BytesBuilder b, int v) => b.add([v & 255, (v >> 8) & 255]);
  void u32(BytesBuilder b, int v) => b.add([v & 255, (v >> 8) & 255, (v >> 16) & 255, (v >> 24) & 255]);
  var off = 0;
  for (final (name, data) in files) {
    final n = utf8.encode(name), crc = crc32(data), len = data.length;
    final head = BytesBuilder(copy: false);
    u32(head, 0x04034b50);
    u16(head, 20);
    u16(head, 0x0800);
    u16(head, 0);
    u16(head, dosT);
    u16(head, dosD);
    u32(head, crc);
    u32(head, len);
    u32(head, len);
    u16(head, n.length);
    u16(head, 0);
    final h = head.takeBytes();
    out
      ..add(h)
      ..add(n)
      ..add(data);
    u32(central, 0x02014b50);
    u16(central, 20);
    u16(central, 20);
    u16(central, 0x0800);
    u16(central, 0);
    u16(central, dosT);
    u16(central, dosD);
    u32(central, crc);
    u32(central, len);
    u32(central, len);
    u16(central, n.length);
    u16(central, 0);
    u16(central, 0);
    u16(central, 0);
    u16(central, 0);
    u32(central, 0);
    u32(central, off);
    central.add(n);
    off += h.length + n.length + len;
  }
  final cd = central.takeBytes();
  out.add(cd);
  final end = BytesBuilder(copy: false);
  u32(end, 0x06054b50);
  u16(end, 0);
  u16(end, 0);
  u16(end, files.length);
  u16(end, files.length);
  u32(end, cd.length);
  u32(end, off);
  u16(end, 0);
  out.add(end.takeBytes());
  return out.takeBytes();
}
