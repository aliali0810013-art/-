import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sindar_admin/main.dart';

void main() {
  testWidgets('admin dashboard renders responsively', (tester) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const SindarAdminApp());
    await tester.pumpAndSettle();

    expect(find.text('SINDAR Master Admin'), findsOneWidget);
    expect(find.text('إدارة التفعيل'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
