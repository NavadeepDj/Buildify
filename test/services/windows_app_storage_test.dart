import 'dart:io';

import 'package:buildify_flutter/services/windows_app_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  test(
    'fresh Windows installation uses application data; existing database stays in place',
    () async {
      final root = await Directory.systemTemp.createTemp('hostany storage ');
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      final oldPath = await databaseFactory.getDatabasesPath();
      final legacy = Directory(p.join(root.path, 'legacy'));
      final support = Directory(p.join(root.path, 'application-data'));
      await legacy.create();
      try {
        await databaseFactory.setDatabasesPath(legacy.path);
        await configureWindowsAppStorage(supportDirectory: () async => support);
        expect(
          await databaseFactory.getDatabasesPath(),
          p.join(support.path, 'databases'),
        );
        expect(
          await Directory(p.join(support.path, 'databases')).exists(),
          true,
        );

        await databaseFactory.setDatabasesPath(legacy.path);
        final oldDb = File(p.join(legacy.path, 'buildify.db'));
        await oldDb.writeAsString('synthetic existing data');
        await configureWindowsAppStorage(
          supportDirectory:
              () async => throw StateError('must preserve legacy'),
        );
        expect(await databaseFactory.getDatabasesPath(), legacy.path);
        expect(await oldDb.readAsString(), 'synthetic existing data');
      } finally {
        await databaseFactory.setDatabasesPath(oldPath);
        await root.delete(recursive: true);
      }
    },
    skip: !Platform.isWindows,
  );
}
