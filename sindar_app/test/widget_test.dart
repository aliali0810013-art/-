import 'package:flutter_test/flutter_test.dart';
import 'package:sindar_app/main.dart';

void main() {
  testWidgets('SINDAR dashboard renders primary sections', (tester) async {
    await tester.pumpWidget(const SindarApp());
    await tester.pumpAndSettle();
    expect(find.text('مدير النظام'), findsOneWidget);
    expect(find.text('فاتورة جديدة'), findsOneWidget);
    expect(find.text('آخر العمليات'), findsOneWidget);
  });
}
