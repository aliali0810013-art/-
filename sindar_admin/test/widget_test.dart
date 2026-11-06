import 'package:flutter_test/flutter_test.dart';
import 'package:sindar_admin/main.dart';

void main() {
  testWidgets('admin dashboard renders', (tester) async {
    await tester.pumpWidget(const SindarAdminApp());
    await tester.pumpAndSettle();
    expect(find.text('إدارة التفعيل'), findsOneWidget);
  });
}
