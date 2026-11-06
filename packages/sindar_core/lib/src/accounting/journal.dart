class JournalLineDraft {
  const JournalLineDraft({
    required this.accountCode,
    this.debit = 0,
    this.credit = 0,
    this.memo,
  });

  final String accountCode;
  final double debit;
  final double credit;
  final String? memo;

  bool get isValidSide =>
      debit >= 0 &&
      credit >= 0 &&
      !((debit > 0) && (credit > 0)) &&
      ((debit > 0) || (credit > 0));
}

class JournalDraft {
  const JournalDraft({
    required this.date,
    required this.description,
    required this.lines,
    this.referenceType,
    this.referenceId,
  });

  final DateTime date;
  final String description;
  final List<JournalLineDraft> lines;
  final String? referenceType;
  final int? referenceId;

  double get totalDebit => lines.fold(0, (sum, line) => sum + line.debit);
  double get totalCredit => lines.fold(0, (sum, line) => sum + line.credit);

  bool get isBalanced =>
      lines.length >= 2 &&
      lines.every((line) => line.isValidSide) &&
      (totalDebit - totalCredit).abs() < 0.005;

  void validate() {
    if (description.trim().isEmpty) {
      throw const FormatException('Journal description is required');
    }
    if (!isBalanced) {
      throw const FormatException('Journal entry is not balanced');
    }
  }
}

abstract final class AutomaticPosting {
  static JournalDraft sales({
    required DateTime date,
    required int referenceId,
    required double net,
    required double vat,
    required bool onCredit,
  }) {
    final total = net + vat;
    return JournalDraft(
      date: date,
      description: 'ترحيل فاتورة مبيعات',
      referenceType: 'sales_invoice',
      referenceId: referenceId,
      lines: [
        JournalLineDraft(accountCode: onCredit ? '1103' : '1101', debit: total),
        JournalLineDraft(accountCode: '4101', credit: net),
        if (vat > 0) JournalLineDraft(accountCode: '2102', credit: vat),
      ],
    );
  }

  static JournalDraft purchase({
    required DateTime date,
    required int referenceId,
    required double net,
    required double vat,
    required bool onCredit,
  }) {
    final total = net + vat;
    return JournalDraft(
      date: date,
      description: 'ترحيل فاتورة مشتريات',
      referenceType: 'purchase_invoice',
      referenceId: referenceId,
      lines: [
        JournalLineDraft(accountCode: '1104', debit: net),
        if (vat > 0) JournalLineDraft(accountCode: '1105', debit: vat),
        JournalLineDraft(accountCode: onCredit ? '2101' : '1101', credit: total),
      ],
    );
  }

  static JournalDraft receipt({
    required DateTime date,
    required int referenceId,
    required double amount,
  }) => JournalDraft(
        date: date,
        description: 'سند قبض من عميل',
        referenceType: 'receipt_voucher',
        referenceId: referenceId,
        lines: [
          JournalLineDraft(accountCode: '1101', debit: amount),
          JournalLineDraft(accountCode: '1103', credit: amount),
        ],
      );

  static JournalDraft payment({
    required DateTime date,
    required int referenceId,
    required double amount,
    String debitAccountCode = '2101',
  }) => JournalDraft(
        date: date,
        description: 'سند صرف',
        referenceType: 'payment_voucher',
        referenceId: referenceId,
        lines: [
          JournalLineDraft(accountCode: debitAccountCode, debit: amount),
          JournalLineDraft(accountCode: '1101', credit: amount),
        ],
      );

  static JournalDraft payroll({
    required DateTime date,
    required int referenceId,
    required double grossExpense,
    required double netPaid,
    required double deductions,
  }) => JournalDraft(
        date: date,
        description: 'مسير رواتب',
        referenceType: 'payroll',
        referenceId: referenceId,
        lines: [
          JournalLineDraft(accountCode: '5201', debit: grossExpense),
          JournalLineDraft(accountCode: '1101', credit: netPaid),
          if (deductions > 0) JournalLineDraft(accountCode: '2104', credit: deductions),
        ],
      );
}
