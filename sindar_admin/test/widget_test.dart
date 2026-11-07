import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sindar_admin/main.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  testWidgets('admin dashboard renders with SQLite license store', (tester) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const SindarAdminApp());

    final logo = find.byKey(
      const ValueKey<String>('sindar-official-logo'),
    );
    for (var attempt = 0;
        attempt < 30 && logo.evaluate().isEmpty;
        attempt++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(find.text('SINDAR Master Admin'), findsOneWidget);
    expect(find.text('ترخيص جديد'), findsOneWidget);
    expect(logo, findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
