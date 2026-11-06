class PartyRecord {
  const PartyRecord({
    required this.id,
    required this.type,
    required this.name,
    this.vatNumber,
    this.commercialRegistration,
    this.phone,
    this.creditLimit = 0,
    this.openingBalance = 0,
  });

  final int id;
  final String type;
  final String name;
  final String? vatNumber;
  final String? commercialRegistration;
  final String? phone;
  final double creditLimit;
  final double openingBalance;

  factory PartyRecord.fromMap(Map<String, Object?> map) => PartyRecord(
        id: map['id']! as int,
        type: map['type']! as String,
        name: map['name']! as String,
        vatNumber: map['vat_number'] as String?,
        commercialRegistration: map['commercial_registration'] as String?,
        phone: map['phone'] as String?,
        creditLimit: (map['credit_limit'] as num?)?.toDouble() ?? 0,
        openingBalance: (map['opening_balance'] as num?)?.toDouble() ?? 0,
      );
}

class ItemRecord {
  const ItemRecord({
    required this.id,
    required this.code,
    required this.name,
    required this.purchasePrice,
    required this.salePrice,
    required this.quantity,
    required this.reorderLevel,
    this.barcode,
  });

  final int id;
  final String code;
  final String? barcode;
  final String name;
  final double purchasePrice;
  final double salePrice;
  final double quantity;
  final double reorderLevel;

  factory ItemRecord.fromMap(Map<String, Object?> map) => ItemRecord(
        id: map['id']! as int,
        code: map['code']! as String,
        barcode: map['barcode'] as String?,
        name: map['name']! as String,
        purchasePrice: (map['purchase_price'] as num).toDouble(),
        salePrice: (map['sale_price'] as num).toDouble(),
        quantity: (map['quantity'] as num).toDouble(),
        reorderLevel: (map['reorder_level'] as num).toDouble(),
      );
}

class InvoiceLineInput {
  const InvoiceLineInput({
    required this.description,
    required this.quantity,
    required this.unitPrice,
    this.itemId,
    this.vatRate = 0,
  });

  final int? itemId;
  final String description;
  final double quantity;
  final double unitPrice;
  final double vatRate;

  double get net => quantity * unitPrice;
  double get vat => net * vatRate;
  double get total => net + vat;
}

class DashboardSnapshot {
  const DashboardSnapshot({
    required this.sales,
    required this.purchases,
    required this.expenses,
    required this.profit,
    required this.recent,
  });

  final double sales;
  final double purchases;
  final double expenses;
  final double profit;
  final List<RecentOperation> recent;
}

class RecentOperation {
  const RecentOperation({
    required this.type,
    required this.number,
    required this.date,
    required this.partyName,
    required this.total,
    required this.status,
  });

  final String type;
  final String number;
  final DateTime date;
  final String partyName;
  final double total;
  final String status;
}

class StatementRow {
  const StatementRow({
    required this.date,
    required this.reference,
    required this.operationType,
    required this.debit,
    required this.credit,
    required this.balance,
  });

  final DateTime date;
  final String reference;
  final String operationType;
  final double debit;
  final double credit;
  final double balance;
}

class FinancialReportSnapshot {
  const FinancialReportSnapshot({
    required this.revenue,
    required this.costOfSales,
    required this.operatingExpenses,
    required this.netProfit,
    required this.receivables,
    required this.payables,
    required this.salesVat,
    required this.purchaseVat,
    required this.cashBalance,
    required this.bankBalance,
    required this.trialBalance,
  });

  final double revenue;
  final double costOfSales;
  final double operatingExpenses;
  final double netProfit;
  final double receivables;
  final double payables;
  final double salesVat;
  final double purchaseVat;
  final double cashBalance;
  final double bankBalance;
  final List<TrialBalanceRow> trialBalance;

  double get netVat => salesVat - purchaseVat;
}

class TrialBalanceRow {
  const TrialBalanceRow({
    required this.code,
    required this.name,
    required this.debit,
    required this.credit,
  });

  final String code;
  final String name;
  final double debit;
  final double credit;
}

class AppUserRecord {
  const AppUserRecord({
    required this.id,
    required this.name,
    required this.role,
    required this.loginCode,
    required this.active,
    required this.isSystemAdmin,
  });

  final int id;
  final String name;
  final String role;
  final String loginCode;
  final bool active;
  final bool isSystemAdmin;

  factory AppUserRecord.fromMap(Map<String, Object?> map) => AppUserRecord(
        id: map['id']! as int,
        name: map['name']! as String,
        role: map['role']! as String,
        loginCode: map['login_code']! as String,
        active: (map['active'] as int) == 1,
        isSystemAdmin: (map['is_system_admin'] as int) == 1,
      );
}

class PermissionSet {
  const PermissionSet({
    required this.module,
    this.canView = true,
    this.canAdd = false,
    this.canEdit = false,
    this.canDelete = false,
    this.canApprove = false,
    this.canPrint = false,
    this.canViewProfit = false,
  });

  final String module;
  final bool canView;
  final bool canAdd;
  final bool canEdit;
  final bool canDelete;
  final bool canApprove;
  final bool canPrint;
  final bool canViewProfit;
}
