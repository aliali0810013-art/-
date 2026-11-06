import 'package:sindar_core/sindar_core.dart';
import 'package:test/test.dart';

void main() {
  test('automatic sales posting is balanced with VAT and bank settlement', () {
    final journal = AutomaticPosting.sales(
      date: DateTime.utc(2026, 11, 7),
      referenceId: 10,
      net: 100,
      vat: 15,
      onCredit: false,
      settlementAccountCode: '1102',
    );

    expect(journal.isBalanced, isTrue);
    expect(journal.totalDebit, closeTo(115, .001));
    expect(journal.totalCredit, closeTo(115, .001));
    expect(journal.lines.first.accountCode, '1102');
    expect(journal.lines.last.accountCode, '2102');
  });

  test('automatic purchase posting is balanced with input VAT', () {
    final journal = AutomaticPosting.purchase(
      date: DateTime.utc(2026, 11, 7),
      referenceId: 20,
      net: 200,
      vat: 30,
      onCredit: true,
    );

    expect(journal.isBalanced, isTrue);
    expect(journal.totalDebit, closeTo(230, .001));
    expect(journal.totalCredit, closeTo(230, .001));
    expect(journal.lines.first.accountCode, '1104');
    expect(journal.lines[1].accountCode, '1105');
    expect(journal.lines.last.accountCode, '2101');
  });

  test('compound journal rejects an unbalanced entry', () {
    final journal = JournalDraft(
      date: DateTime.utc(2026, 11, 7),
      description: 'اختبار عدم التوازن',
      lines: const [
        JournalLineDraft(accountCode: '1101', debit: 100),
        JournalLineDraft(accountCode: '4101', credit: 90),
      ],
    );

    expect(journal.isBalanced, isFalse);
    expect(() => journal.validate(), throwsFormatException);
  });
}
