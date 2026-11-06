import 'account.dart';

abstract final class StandardChartOfAccounts {
  static const accounts = <Account>[
    Account(code: '1', nameAr: 'الأصول', type: AccountType.asset, level: 1, isPosting: false),
    Account(code: '11', nameAr: 'الأصول المتداولة', type: AccountType.asset, level: 2, isPosting: false, parentCode: '1'),
    Account(code: '1101', nameAr: 'الصندوق', type: AccountType.asset, level: 3, isPosting: true, parentCode: '11'),
    Account(code: '1102', nameAr: 'الحسابات البنكية', type: AccountType.asset, level: 3, isPosting: true, parentCode: '11'),
    Account(code: '1103', nameAr: 'العملاء والذمم المدينة', type: AccountType.asset, level: 3, isPosting: true, parentCode: '11'),
    Account(code: '1104', nameAr: 'المخزون', type: AccountType.asset, level: 3, isPosting: true, parentCode: '11'),
    Account(code: '1105', nameAr: 'ضريبة مدخلات قابلة للاسترداد', type: AccountType.asset, level: 3, isPosting: true, parentCode: '11'),
    Account(code: '1106', nameAr: 'العهد والسلف', type: AccountType.asset, level: 3, isPosting: true, parentCode: '11'),
    Account(code: '1107', nameAr: 'مصروفات مدفوعة مقدماً', type: AccountType.asset, level: 3, isPosting: true, parentCode: '11'),
    Account(code: '12', nameAr: 'الأصول غير المتداولة', type: AccountType.asset, level: 2, isPosting: false, parentCode: '1'),
    Account(code: '1201', nameAr: 'الأراضي', type: AccountType.asset, level: 3, isPosting: true, parentCode: '12'),
    Account(code: '1202', nameAr: 'المباني', type: AccountType.asset, level: 3, isPosting: true, parentCode: '12'),
    Account(code: '1203', nameAr: 'السيارات', type: AccountType.asset, level: 3, isPosting: true, parentCode: '12'),
    Account(code: '1204', nameAr: 'الأثاث والتجهيزات', type: AccountType.asset, level: 3, isPosting: true, parentCode: '12'),
    Account(code: '1205', nameAr: 'أجهزة ومعدات', type: AccountType.asset, level: 3, isPosting: true, parentCode: '12'),
    Account(code: '1291', nameAr: 'مجمع الإهلاك', type: AccountType.asset, level: 3, isPosting: true, parentCode: '12'),

    Account(code: '2', nameAr: 'الخصوم والالتزامات', type: AccountType.liability, level: 1, isPosting: false),
    Account(code: '21', nameAr: 'الخصوم المتداولة', type: AccountType.liability, level: 2, isPosting: false, parentCode: '2'),
    Account(code: '2101', nameAr: 'الموردون والذمم الدائنة', type: AccountType.liability, level: 3, isPosting: true, parentCode: '21'),
    Account(code: '2102', nameAr: 'ضريبة القيمة المضافة المستحقة', type: AccountType.liability, level: 3, isPosting: true, parentCode: '21'),
    Account(code: '2103', nameAr: 'رواتب وأجور مستحقة', type: AccountType.liability, level: 3, isPosting: true, parentCode: '21'),
    Account(code: '2104', nameAr: 'مصروفات مستحقة', type: AccountType.liability, level: 3, isPosting: true, parentCode: '21'),
    Account(code: '2105', nameAr: 'دفعات مقدمة من العملاء', type: AccountType.liability, level: 3, isPosting: true, parentCode: '21'),
    Account(code: '22', nameAr: 'الخصوم طويلة الأجل', type: AccountType.liability, level: 2, isPosting: false, parentCode: '2'),
    Account(code: '2201', nameAr: 'قروض طويلة الأجل', type: AccountType.liability, level: 3, isPosting: true, parentCode: '22'),

    Account(code: '3', nameAr: 'حقوق الملكية', type: AccountType.equity, level: 1, isPosting: false),
    Account(code: '3101', nameAr: 'رأس المال', type: AccountType.equity, level: 2, isPosting: true, parentCode: '3'),
    Account(code: '3102', nameAr: 'مسحوبات المالك', type: AccountType.equity, level: 2, isPosting: true, parentCode: '3'),
    Account(code: '3103', nameAr: 'الأرباح المبقاة', type: AccountType.equity, level: 2, isPosting: true, parentCode: '3'),
    Account(code: '3104', nameAr: 'صافي ربح أو خسارة الفترة', type: AccountType.equity, level: 2, isPosting: true, parentCode: '3'),

    Account(code: '4', nameAr: 'الإيرادات', type: AccountType.revenue, level: 1, isPosting: false),
    Account(code: '4101', nameAr: 'إيرادات المبيعات', type: AccountType.revenue, level: 2, isPosting: true, parentCode: '4'),
    Account(code: '4102', nameAr: 'إيرادات الخدمات', type: AccountType.revenue, level: 2, isPosting: true, parentCode: '4'),
    Account(code: '4103', nameAr: 'إيرادات أخرى', type: AccountType.revenue, level: 2, isPosting: true, parentCode: '4'),
    Account(code: '4191', nameAr: 'مردودات ومسموحات المبيعات', type: AccountType.revenue, level: 2, isPosting: true, parentCode: '4'),

    Account(code: '5', nameAr: 'المصروفات', type: AccountType.expense, level: 1, isPosting: false),
    Account(code: '51', nameAr: 'تكلفة المبيعات', type: AccountType.expense, level: 2, isPosting: false, parentCode: '5'),
    Account(code: '5101', nameAr: 'تكلفة البضاعة المباعة', type: AccountType.expense, level: 3, isPosting: true, parentCode: '51'),
    Account(code: '5102', nameAr: 'مصاريف شراء وشحن', type: AccountType.expense, level: 3, isPosting: true, parentCode: '51'),
    Account(code: '52', nameAr: 'المصروفات التشغيلية', type: AccountType.expense, level: 2, isPosting: false, parentCode: '5'),
    Account(code: '5201', nameAr: 'الرواتب والأجور', type: AccountType.expense, level: 3, isPosting: true, parentCode: '52'),
    Account(code: '5202', nameAr: 'الإيجارات', type: AccountType.expense, level: 3, isPosting: true, parentCode: '52'),
    Account(code: '5203', nameAr: 'الكهرباء والمياه والاتصالات', type: AccountType.expense, level: 3, isPosting: true, parentCode: '52'),
    Account(code: '5204', nameAr: 'الصيانة والإصلاح', type: AccountType.expense, level: 3, isPosting: true, parentCode: '52'),
    Account(code: '5205', nameAr: 'التسويق والإعلان', type: AccountType.expense, level: 3, isPosting: true, parentCode: '52'),
    Account(code: '5206', nameAr: 'الإهلاك', type: AccountType.expense, level: 3, isPosting: true, parentCode: '52'),
    Account(code: '5207', nameAr: 'مصروفات إدارية وعمومية', type: AccountType.expense, level: 3, isPosting: true, parentCode: '52'),
    Account(code: '5208', nameAr: 'عمولات ورسوم بنكية', type: AccountType.expense, level: 3, isPosting: true, parentCode: '52'),
  ];

  static bool get isBalancedStructure {
    final codes = accounts.map((e) => e.code).toSet();
    return accounts.every((e) => e.parentCode == null || codes.contains(e.parentCode));
  }
}
