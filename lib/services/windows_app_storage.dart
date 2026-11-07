import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Configure desktop persistence once at startup, before opening any database.
/// Keep old working-directory databases in place rather than silently replacing
/// them with an empty database. No schema/ownership migration happens here.
Future<void> configureWindowsAppStorage({
  Future<Directory> Function()? supportDirectory,
}) async {
  if (!Platform.isWindows) return;
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  final legacyPath = await databaseFactory.getDatabasesPath();
  if (await File(p.join(legacyPath, 'buildify.db')).exists()) return;
  final support = await (supportDirectory ?? getApplicationSupportDirectory)();
  final directory = Directory(p.join(support.path, 'databases'));
  await directory.create(recursive: true);
  await databaseFactory.setDatabasesPath(directory.path);
}
