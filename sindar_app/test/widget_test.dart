import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sindar_app/main.dart';
import 'package:sindar_app/src/data/local/sindar_database.dart';
import 'package:sindar_app/src/screens/home_dashboard_screen.dart';
import 'package:sindar_app/src/services/session_controller.dart';
import 'package:sindar_app/src/theme/app_theme.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  Future<void> resetDatabase() async {
    SessionController.instance.currentUser.value = null;
    await SindarDatabase.instance.close();
    final root = await getDatabasesPath();
    await deleteDatabase(p.join(root, 'sindar.db'));
  }

  setUp(resetDatabase);
  tearDown(() async => SindarDatabase.instance.close());

  Future<void> pumpDashboard(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        locale: const Locale('ar'),
        home: const Directionality(
          textDirection: TextDirection.rtl,
          child: HomeDashboardScreen(),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
  }

  bool sameRow(WidgetTester tester, List<String> keys) {
    final values = [
      for (final key in keys)
        tester.getTopLeft(find.byKey(ValueKey<String>(key))).dy,
    ];
    final first = values.first;
    return values.every((value) => (value - first).abs() < .5);
  }

  testWidgets('fresh app is locked behind license number only', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const SindarApp());
    await tester.pump(const Duration(milliseconds: 400));

    expect(
      find.byKey(const ValueKey<String>('license-number-field')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('activate-license-button')),
      findsOneWidget,
    );
    expect(find.text('تفعيل سندار'), findsOneWidget);
    expect(find.text('الرئيسية'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('dashboard fixed geometry at 360x800 without demo data', (
    tester,
  ) async {
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
    expect(
      find.byKey(const ValueKey<String>('sindar-official-logo')),
      findsOneWidget,
    );
    expect(find.textContaining('146,500'), findsNothing);
    expect(find.text('لا توجد عمليات بعد'), findsOneWidget);
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
