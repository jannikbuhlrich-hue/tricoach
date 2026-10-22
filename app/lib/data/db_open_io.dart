import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sembast/sembast.dart';
import 'package:sembast/sembast_io.dart';

/// iOS, Android, Windows, macOS: Datei im App-Ordner
Future<Database> openPlatformDb() async {
  final dir = await getApplicationSupportDirectory();
  return databaseFactoryIo.openDatabase(p.join(dir.path, 'tricoach.db'));
}
