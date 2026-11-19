import 'package:sembast_web/sembast_web.dart';

/// Browser: IndexedDB
Future<Database> openPlatformDb() => databaseFactoryWeb.openDatabase('tricoach');
