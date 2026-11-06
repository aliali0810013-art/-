import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sindar_app/main.dart';

void main() {
  testWidgets('SINDAR dashboard renders without overflow', (tester) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const SindarApp());
    await tester.pumpAndSettle();

    expect(find.text('مدير النظام'), findsOneWidget);
    expect(find.text('المبيعات'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
