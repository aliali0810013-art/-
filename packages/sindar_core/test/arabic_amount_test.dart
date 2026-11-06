import 'package:sindar_core/sindar_core.dart';
import 'package:test/test.dart';

void main() {
  test('Arabic amount spelling includes whole and fractional amount', () {
    expect(
      ArabicAmountInWords.spell(1250.75),
      'ألف ومئتان وخمسون ريال وخمسة وسبعون هللة فقط',
    );
  });
}
