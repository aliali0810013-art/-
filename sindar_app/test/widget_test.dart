import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sindar_app/main.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  Future<void> pumpDashboard(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    await tester.pumpWidget(const SindarApp());
    await tester.pump(const Duration(milliseconds: 120));
  }

  bool sameRow(WidgetTester tester, List<String> keys) {
    final values = [
      for (final key in keys)
        tester.getTopLeft(find.byKey(ValueKey<String>(key))).dy,
    ];
    final first = values.first;
    return values.every((value) => (value - first).abs() < .5);
  }

  testWidgets('dashboard fixed geometry at 360x800', (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await pumpDashboard(tester, const Size(360, 800));

    expect(
      sameRow(tester, const [
        'kpi-sales',
        'kpi-purchases',
        'kpi-expenses',
        'kpi-profit',
      ]),
      isTrue,
    );
    expect(
      sameRow(tester, const [
        'module-0',
        'module-1',
        'module-2',
        'module-3',
        'module-4',
      ]),
      isTrue,
    );
    expect(find.text('الفرع الرئيسي'), findsOneWidget);
    expect(find.text('نوفمبر 2026'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('dashboard fixed geometry at 390x844', (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await pumpDashboard(tester, const Size(390, 844));

    expect(
      sameRow(tester, const [
        'kpi-sales',
        'kpi-purchases',
        'kpi-expenses',
        'kpi-profit',
      ]),
      isTrue,
    );
    expect(
      sameRow(tester, const [
        'module-0',
        'module-1',
        'module-2',
        'module-3',
        'module-4',
      ]),
      isTrue,
    );
    expect(find.text('الرئيسية'), findsOneWidget);
    expect(find.text('المستندات'), findsOneWidget);
    expect(find.text('الإعدادات'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
