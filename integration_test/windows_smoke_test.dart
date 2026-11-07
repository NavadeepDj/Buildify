import 'dart:io';

import 'package:buildify_flutter/main.dart' as app;
import 'package:buildify_flutter/services/database_helper.dart';
import 'package:buildify_flutter/services/desktop_server_bridge.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Windows plugins, account UI and local navigation smoke', (
    tester,
  ) async {
    expect(Platform.isWindows, true);
    // Use a dedicated synthetic key; do not read or overwrite the user's session.
    const storage = FlutterSecureStorage();
    final key =
        'hostany_windows_smoke_${DateTime.now().microsecondsSinceEpoch}';
    await tester.runAsync(() async {
      try {
        await storage.write(key: key, value: 'synthetic-roundtrip');
        expect(await storage.read(key: key), 'synthetic-roundtrip');
      } finally {
        await storage.delete(key: key);
      }
    });
    debugPrint('Windows smoke: secure storage roundtrip passed');

    await tester.runAsync(app.main);
    debugPrint('Windows smoke: application startup passed');
    await tester.pumpAndSettle(const Duration(milliseconds: 300));

    // Query schema only. Do not create, update or delete the user's projects.
    await tester.runAsync(() async {
      final db = await DatabaseHelper.instance.database;
      final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name IN ('projects','deployments')",
      );
      expect(tables.length, 2);
      final metrics = await DesktopServerBridge().getDeviceMetrics();
      expect(metrics?['ramGb'], greaterThan(0));
      expect(metrics?['availRamGb'], greaterThan(0));
      expect(metrics?['freeStorageGb'], greaterThan(0));
      expect(metrics?['cpuLabel'], isNot(contains('ARM')));
    });
    debugPrint('Windows smoke: SQLite and hardware metrics passed');

    expect(tester.takeException(), null);
    expect(find.byType(MaterialApp), findsOneWidget);
    // Window-size rendering checks catch desktop layout overflow.
    final local = find.text('Continue with local hosting');
    if (local.evaluate().isNotEmpty) {
      await tester.tap(local.first);
      // The live hosting dashboard has periodic status updates and need not
      // become idle. Pump a bounded sequence instead of waiting forever.
      for (var frame = 0; frame < 10; frame++) {
        await tester.pump(const Duration(milliseconds: 200));
      }
    }
    expect(tester.takeException(), null);
    // Leave the app mounted for a few frames to catch delayed plugin failures.
    await tester.pump(const Duration(seconds: 2));
    expect(tester.takeException(), null);
  });
}
