// ignore_for_file: prefer_const_constructors

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:sindar_core/sindar_core.dart';

import '../data/local/sindar_database.dart';
import '../services/erp_repository.dart';
import '../services/operational_models.dart';
import '../services/session_controller.dart';
import '../theme/app_theme.dart';
import 'assets_payroll_reports_screens.dart';
import 'chart_of_accounts_screen.dart';
import 'document_studio_screen.dart';
import 'saved_documents_screen.dart';
import 'equipment_rental_screen.dart';
import 'journal_voucher_screens.dart';
import 'party_inventory_screens.dart';
import 'sales_purchase_screens.dart';
import 'settings_hub_screen.dart';
import 'users_license_screens.dart';

class HomeDashboardScreen extends StatefulWidget {
  const HomeDashboardScreen({super.key});

  @override
  State<HomeDashboardScreen> createState() => _HomeDashboardScreenState();
}

class _HomeDashboardScreenState extends State<HomeDashboardScreen> {
  DashboardSnapshot? _snapshot;
  LicensePolicy _policy = LicensePolicy.lockedDefault;
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  String _organizationName = 'المنشأة';
  bool _loading = true;
  int _navIndex = 0;

  static const _modules = <_ModuleData>[
    _ModuleData('customers', 'العملاء', Icons.groups_rounded, Color(0xFF0D3A72), AppColors.gold),
    _ModuleData('suppliers', 'الموردون', Icons.local_shipping_outlined, Color(0xFF0D3A72), AppColors.gold),
    _ModuleData('chart', 'شجرة\nالحسابات', Icons.account_tree_outlined, AppColors.gold, Color(0xFF0D3A72)),
    _ModuleData('journals', 'القيود\nاليومية', Icons.menu_book_rounded, Color(0xFF0D3A72), AppColors.gold),
    _ModuleData('reports', 'التقارير\nوالتحليلات', Icons.query_stats_rounded, Color(0xFF0D3A72), AppColors.gold),
    _ModuleData('purchases', 'المشتريات', Icons.shopping_cart_outlined, Color(0xFF0D3A72), AppColors.gold),
    _ModuleData('saved_documents', 'المستندات المحفوظة', Icons.folder_copy_outlined, Color(0xFF0D3A72), AppColors.gold),
    _ModuleData('equipment', 'بيع وتأجير المعدات', Icons.handyman_outlined, Color(0xFF0D3A72), AppColors.gold),
    _ModuleData('inventory', 'المخزون\nوالأصناف', Icons.inventory_2_outlined, AppColors.gold, Color(0xFF0D3A72)),
    _ModuleData('assets', 'الأصول\nوالعهد', Icons.corporate_fare_rounded, Color(0xFF0D3A72), AppColors.gold),
    _ModuleData('payroll', 'الموظفون\nوالرواتب', Icons.business_center_outlined, Color(0xFF0D3A72), AppColors.gold),
    _ModuleData('users', 'المستخدمون\nوالصلاحيات', Icons.admin_panel_settings_outlined, Color(0xFF0D3A72), AppColors.gold),
  ];

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    await SessionController.instance.initialize();
    final policy = await SindarDatabase.instance.getLicensePolicy();
    final grant = await ErpRepository.instance.currentLicenseGrant();
    final company = await ErpRepository.instance.companySettings();
    final snapshot = await ErpRepository.instance.dashboard(
      year: _month.year,
      month: _month.month,
    );
    final configuredName = company['company_name_ar']?.trim();
    if (!mounted) return;
    setState(() {
      _policy = policy;
      _snapshot = snapshot;
      _organizationName = configuredName?.isNotEmpty == true
          ? configuredName!
          : (grant?.organizationName.trim().isNotEmpty == true
              ? grant!.organizationName.trim()
              : 'المنشأة');
      _loading = false;
    });
  }

  Future<void> _pickMonth() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(_month.year, _month.month, 1),
      firstDate: DateTime(2020),
      lastDate: DateTime(2035, 12, 31),
      helpText: 'اختر أي يوم من الشهر المطلوب',
    );
    if (picked == null) return;
    setState(() {
      _month = DateTime(picked.year, picked.month);
      _loading = true;
    });
    await _refresh();
  }

  Future<void> _showBranch() async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: ListTile(
          leading: const Icon(Icons.storefront_outlined, color: AppColors.navy2),
          title: const Text('الفرع الرئيسي', style: TextStyle(fontWeight: FontWeight.w800)),
          subtitle: const Text('الفرع التشغيلي الحالي'),
          trailing: const Icon(Icons.check_circle, color: AppColors.green),
          onTap: () => Navigator.pop(context),
        ),
      ),
    );
  }

  Future<void> _switchUser() async {
    final changed = await showDialog<bool>(
      context: context,
      builder: (_) => const SwitchUserDialog(),
    );
    if (changed == true && mounted) setState(() {});
  }

  Future<void> _openPage(String permissionModule, Widget page) async {
    final allowed = await SessionController.instance.canOpen(permissionModule);
    if (!mounted) return;
    if (!allowed) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ليس لديك صلاحية لفتح هذا القسم')),
      );
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => page),
    );
    if (mounted) await _refresh();
  }

  Future<void> _openModule(_ModuleData module) async {
    switch (module.id) {
      case 'customers':
        return _openPage('customers', const PartiesScreen(type: 'customer'));
      case 'suppliers':
        return _openPage('suppliers', const PartiesScreen(type: 'supplier'));
      case 'chart':
        return _openPage('journals', const ChartOfAccountsScreen());
      case 'journals':
        return _openPage('journals', const JournalOperationsScreen());
      case 'reports':
        return _openPage('reports', const ReportsScreen());
      case 'purchases':
        return _openPage('purchases', const PurchaseScreen());
      case 'saved_documents':
        return _openPage('documents', const SavedDocumentsScreen());
      case 'equipment':
        return _openPage('assets', const EquipmentRentalScreen());
      case 'inventory':
        return _openPage('inventory', const InventoryScreen());
      case 'assets':
        return _openPage('assets', const AssetsAndCustodyScreen());
      case 'payroll':
        return _openPage('payroll', const PayrollScreen());
      case 'users':
        return _openPage('settings', const UsersPermissionsScreen());
    }
  }

  Future<void> _quickAction(int index) async {
    switch (index) {
      case 0:
        return _openPage('sales', const SalesScreen());
      case 1:
        return _openPage('sales', const SalesScreen());
      case 2:
        return _openPage('documents', const VoucherScreen(receipt: true));
      case 3:
        return _openPage('documents', const VoucherScreen(receipt: false));
      case 4:
        return _openPage('documents', const MoreDocumentsScreen());
    }
  }

  Future<void> _bottomAction(int index) async {
    setState(() => _navIndex = index);
    switch (index) {
      case 0:
        return;
      case 1:
        await _openPage('documents', const DocumentStudioScreen());
        break;
      case 2:
        await _openPage('sales', const SalesScreen());
        break;
      case 3:
        await _openPage('reports', const ReportsScreen());
        break;
      case 4:
        await _openPage('settings', const SettingsHubScreen());
        break;
    }
    if (mounted) setState(() => _navIndex = 0);
  }

  String get _monthLabel {
    const names = <String>[
      'يناير',
      'فبراير',
      'مارس',
      'أبريل',
      'مايو',
      'يونيو',
      'يوليو',
      'أغسطس',
      'سبتمبر',
      'أكتوبر',
      'نوفمبر',
      'ديسمبر',
    ];
    return '${names[_month.month - 1]} ${_month.year}';
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = _snapshot;
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          _TopHeader(companyName: _organizationName),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                children: [
                  _WelcomeFilters(
                    monthLabel: _monthLabel,
                    onMonthTap: _pickMonth,
                    onBranchTap: _showBranch,
                    onUserTap: _switchUser,
                  ),
                  const SizedBox(height: 8),
                  _KpiRow(
                    snapshot: snapshot,
                    currencySymbol: _policy.currencySymbol,
                    loading: _loading,
                  ),
                  const SizedBox(height: 8),
                  _QuickActions(onTap: _quickAction),
                  const SizedBox(height: 8),
                  _ModulesGrid(
                    modules: _modules,
                    onTap: _openModule,
                  ),
                  const SizedBox(height: 8),
                  _RecentTransactions(
                    rows: snapshot?.recent ?? const [],
                    currencySymbol: _policy.currencySymbol,
                    loading: _loading,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: _BottomNav(
        selected: _navIndex,
        onChanged: _bottomAction,
      ),
    );
  }
}

class _TopHeader extends StatelessWidget {
  const _TopHeader({required this.companyName});

  final String companyName;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.navy,
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: 76,
          child: Stack(
            alignment: Alignment.center,
            children: [
              PositionedDirectional(
                start: 8,
                top: 12,
                bottom: 12,
                child: _CompanySelector(companyName: companyName),
              ),
              Center(
                child: Container(
                  key: const ValueKey<String>('sindar-official-logo'),
                  width: 138,
                  height: 60,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: AppColors.gold.withValues(alpha: .70),
                      width: 1.2,
                    ),
                  ),
                  child: Image.asset(
                    'assets/branding/sindar_brand_full.webp',
                    fit: BoxFit.contain,
                    filterQuality: FilterQuality.high,
                  ),
                ),
              ),
              const PositionedDirectional(
                end: 8,
                top: 18,
                bottom: 18,
                child: _HeaderTools(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CompanySelector extends StatelessWidget {
  const _CompanySelector({required this.companyName});

  final String companyName;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 104,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white24),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.apartment_rounded,
            color: Colors.white,
            size: 18,
          ),
          const SizedBox(width: 4),
          Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Text(
                companyName,
                maxLines: 2,
                textAlign: TextAlign.right,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  height: 1.15,
                ),
              ),
            ),
          ),
          const Icon(
            Icons.keyboard_arrow_down_rounded,
            color: Colors.white70,
            size: 15,
          ),
        ],
      ),
    );
  }
}

class _HeaderTools extends StatelessWidget {
  const _HeaderTools();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.search_rounded, color: Colors.white, size: 20),
        const SizedBox(width: 5),
        const Icon(Icons.chat_bubble_outline_rounded, color: Colors.white, size: 19),
        const SizedBox(width: 5),
        Stack(
          clipBehavior: Clip.none,
          children: [
            const Icon(Icons.notifications_none_rounded, color: Colors.white, size: 20),
            Positioned(
              right: 0,
              top: -1,
              child: Container(
                width: 6,
                height: 6,
                decoration: const BoxDecoration(color: Colors.orange, shape: BoxShape.circle),
              ),
            ),
          ],
        ),
        const SizedBox(width: 7),
        Container(width: 1, height: 28, color: Colors.white24),
      ],
    );
  }
}

class _WelcomeFilters extends StatelessWidget {
  const _WelcomeFilters({
    required this.monthLabel,
    required this.onMonthTap,
    required this.onBranchTap,
    required this.onUserTap,
  });

  final String monthLabel;
  final VoidCallback onMonthTap;
  final VoidCallback onBranchTap;
  final VoidCallback onUserTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: Row(
        children: [
          Expanded(
            flex: 12,
            child: InkWell(
              onTap: onUserTap,
              borderRadius: BorderRadius.circular(14),
              child: Padding(
                padding: const EdgeInsetsDirectional.only(end: 2),
                child: Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: const BoxDecoration(color: AppColors.navy2, shape: BoxShape.circle),
                      child: const Icon(Icons.person_rounded, color: Colors.white, size: 20),
                    ),
                    const SizedBox(width: 5),
                    Expanded(
                      child: ValueListenableBuilder<AppUserRecord?>(
                        valueListenable: SessionController.instance.currentUser,
                        builder: (context, user, _) => Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('مرحباً بك', style: TextStyle(fontSize: 10, color: AppColors.muted, height: 1.1)),
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerRight,
                              child: Text(
                                user?.name ?? 'مدير النظام',
                                maxLines: 1,
                                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: AppColors.text, height: 1.15),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 5),
          Expanded(
            flex: 10,
            child: _FilterCapsule(
              icon: Icons.storefront_outlined,
              label: 'الفرع الرئيسي',
              onTap: onBranchTap,
            ),
          ),
          const SizedBox(width: 5),
          Expanded(
            flex: 10,
            child: _FilterCapsule(
              icon: Icons.calendar_month_outlined,
              label: monthLabel,
              onTap: onMonthTap,
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterCapsule extends StatelessWidget {
  const _FilterCapsule({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          height: 38,
          padding: const EdgeInsets.symmetric(horizontal: 5),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFD9E1EA)),
          ),
          child: Row(
            children: [
              Icon(icon, color: AppColors.navy2, size: 16),
              const SizedBox(width: 3),
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.center,
                  child: Text(
                    label,
                    maxLines: 1,
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
                  ),
                ),
              ),
              const Icon(Icons.keyboard_arrow_down_rounded, color: AppColors.navy2, size: 14),
            ],
          ),
        ),
      ),
    );
  }
}

class _KpiRow extends StatelessWidget {
  const _KpiRow({
    required this.snapshot,
    required this.currencySymbol,
    required this.loading,
  });

  final DashboardSnapshot? snapshot;
  final String currencySymbol;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final values = <_KpiData>[
      _KpiData('kpi-sales', 'المبيعات', snapshot?.sales ?? 0, '—', Icons.bar_chart_rounded, AppColors.gold, AppColors.cream, AppColors.muted),
      _KpiData('kpi-purchases', 'المشتريات', snapshot?.purchases ?? 0, '—', Icons.shopping_cart_outlined, AppColors.blue, AppColors.sky, AppColors.muted),
      _KpiData('kpi-expenses', 'المصروفات', snapshot?.expenses ?? 0, '—', Icons.receipt_long_outlined, Color(0xFFC84747), AppColors.rose, AppColors.muted),
      _KpiData('kpi-profit', 'الأرباح', snapshot?.profit ?? 0, '—', Icons.toll_rounded, AppColors.green, AppColors.mint, AppColors.muted),
    ];
    return SizedBox(
      height: 82,
      child: Row(
        children: [
          for (var i = 0; i < values.length; i++) ...[
            Expanded(
              child: _KpiCard(
                key: ValueKey(values[i].keyName),
                data: values[i],
                currencySymbol: currencySymbol,
                loading: loading,
              ),
            ),
            if (i != values.length - 1) const SizedBox(width: 6),
          ],
        ],
      ),
    );
  }
}

class _KpiCard extends StatelessWidget {
  const _KpiCard({
    super.key,
    required this.data,
    required this.currencySymbol,
    required this.loading,
  });

  final _KpiData data;
  final String currencySymbol;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final amount = NumberFormat('#,##0.00', 'en_US').format(data.amount);
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: data.background,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: Colors.white),
        boxShadow: const [BoxShadow(color: Color(0x0D0A2540), blurRadius: 8, offset: Offset(0, 3))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(data.icon, color: data.iconColor, size: 17),
              const SizedBox(width: 3),
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: Text(data.label, maxLines: 1, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800)),
                ),
              ),
            ],
          ),
          const Spacer(),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerRight,
            child: Text(
              loading ? '—' : '$amount $currencySymbol',
              maxLines: 1,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900, height: 1),
            ),
          ),
          const SizedBox(height: 3),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerRight,
            child: Text(
              data.growth,
              maxLines: 1,
              style: TextStyle(color: data.growthColor, fontWeight: FontWeight.w800, fontSize: 9),
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickActions extends StatelessWidget {
  const _QuickActions({required this.onTap});

  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    const actions = <_ActionData>[
      _ActionData('فاتورة جديدة', Icons.note_add_outlined, Colors.white, true),
      _ActionData('عرض سعر', Icons.description_outlined, AppColors.purple, false),
      _ActionData('سند قبض', Icons.receipt_long_outlined, AppColors.green, false),
      _ActionData('سند صرف', Icons.post_add_outlined, Color(0xFFC84747), false),
      _ActionData('المزيد', Icons.more_horiz_rounded, AppColors.navy, false),
    ];
    return Container(
      height: 76,
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: const Color(0xFFE7EBF0)),
      ),
      child: Row(
        children: [
          for (var i = 0; i < actions.length; i++) ...[
            Expanded(
              child: _ActionCard(
                data: actions[i],
                onTap: () => onTap(i),
              ),
            ),
            if (i != actions.length - 1) const SizedBox(width: 6),
          ],
        ],
      ),
    );
  }
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({required this.data, required this.onTap});

  final _ActionData data;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: data.primary ? AppColors.navy2 : Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          height: 64,
          padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 5),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: data.primary ? AppColors.gold : const Color(0xFFE2E7EC),
              width: data.primary ? 1.5 : 1,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(data.icon, color: data.color, size: 24),
              const SizedBox(height: 3),
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.center,
                  child: Text(
                    data.label,
                    maxLines: 1,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: data.primary ? Colors.white : AppColors.text,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ModulesGrid extends StatelessWidget {
  const _ModulesGrid({
    required this.modules,
    required this.onTap,
  });

  final List<_ModuleData> modules;
  final ValueChanged<_ModuleData> onTap;

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 5,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 8,
      crossAxisSpacing: 6,
      childAspectRatio: .88,
      children: [
        for (var i = 0; i < modules.length; i++)
          _ModuleCard(
            key: ValueKey('module-$i'),
            data: modules[i],
            onTap: () => onTap(modules[i]),
          ),
      ],
    );
  }
}

class _ModuleCard extends StatelessWidget {
  const _ModuleCard({
    super.key,
    required this.data,
    required this.onTap,
  });

  final _ModuleData data;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(13),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(13),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 5),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(13),
            border: Border.all(color: const Color(0xFFE3E8EE)),
            boxShadow: const [BoxShadow(color: Color(0x0A0A2540), blurRadius: 7, offset: Offset(0, 3))],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.bottomRight,
                children: [
                  Icon(data.icon, color: data.primary, size: 24),
                  Positioned(
                    right: -2,
                    bottom: -1,
                    child: Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(color: data.accent, shape: BoxShape.circle),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.center,
                  child: Text(
                    data.label,
                    maxLines: 2,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, height: 1.15),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RecentTransactions extends StatelessWidget {
  const _RecentTransactions({
    required this.rows,
    required this.currencySymbol,
    required this.loading,
  });

  final List<RecentOperation> rows;
  final String currencySymbol;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(9, 7, 9, 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: const Color(0xFFE7EBF0)),
      ),
      child: Column(
        children: [
          const SizedBox(
            height: 26,
            child: Row(
              children: [
                Icon(Icons.description_outlined, color: AppColors.gold, size: 18),
                SizedBox(width: 5),
                Text('آخر العمليات', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14)),
                Spacer(),
                Text('عرض الكل', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 10, color: AppColors.navy2)),
              ],
            ),
          ),
          if (loading)
            const SizedBox(height: 54, child: Center(child: CircularProgressIndicator(strokeWidth: 2)))
          else if (rows.isEmpty)
            const SizedBox(
              height: 54,
              child: Center(
                child: Text(
                  'لا توجد عمليات بعد',
                  style: TextStyle(
                    color: AppColors.muted,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            )
          else
            for (var i = 0; i < rows.length; i++) ...[
              _RecentRow(operation: rows[i], currencySymbol: currencySymbol),
              if (i != rows.length - 1) const Divider(height: 1),
            ],
        ],
      ),
    );
  }
}

class _RecentRow extends StatelessWidget {
  const _RecentRow({required this.operation, required this.currencySymbol});

  final RecentOperation operation;
  final String currencySymbol;

  @override
  Widget build(BuildContext context) {
    final meta = _operationMeta(operation.type);
    final amount = NumberFormat('#,##0.00', 'en_US').format(operation.total);
    return SizedBox(
      height: 36,
      child: Row(
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(color: meta.color.withValues(alpha: .1), shape: BoxShape.circle),
            child: Icon(meta.icon, color: meta.color, size: 14),
          ),
          const SizedBox(width: 6),
          Expanded(
            flex: 13,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Text(
                meta.label,
                maxLines: 1,
                style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800),
              ),
            ),
          ),
          const SizedBox(width: 5),
          Expanded(
            flex: 16,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.center,
              child: Text(
                operation.number,
                maxLines: 1,
                style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: AppColors.navy2),
              ),
            ),
          ),
          const SizedBox(width: 5),
          Expanded(
            flex: 16,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                '$amount $currencySymbol',
                maxLines: 1,
                style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w900),
              ),
            ),
          ),
        ],
      ),
    );
  }

  _OperationMeta _operationMeta(String type) => switch (type) {
        'sales_invoice' => const _OperationMeta('فاتورة مبيعات', Icons.receipt_long_outlined, AppColors.blue),
        'quotation' => const _OperationMeta('عرض سعر', Icons.description_outlined, AppColors.purple),
        'receipt_voucher' => const _OperationMeta('سند قبض', Icons.payments_outlined, AppColors.green),
        'purchase_invoice' => const _OperationMeta('مشتريات', Icons.shopping_cart_outlined, Colors.orange),
        _ => const _OperationMeta('عملية', Icons.description_outlined, AppColors.navy2),
      };
}

class _BottomNav extends StatelessWidget {
  const _BottomNav({required this.selected, required this.onChanged});

  final int selected;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.navy,
      child: SafeArea(
        top: false,
        bottom: true,
        minimum: const EdgeInsets.only(bottom: 2),
        child: SizedBox(
          height: 64,
          child: Row(
            children: [
              Expanded(child: _BottomItem(index: 0, label: 'الرئيسية', icon: Icons.home_rounded, selected: selected == 0, onTap: onChanged)),
              Expanded(child: _BottomItem(index: 1, label: 'المستندات', icon: Icons.description_outlined, selected: selected == 1, onTap: onChanged)),
              Expanded(
                child: InkWell(
                  onTap: () => onChanged(2),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Transform.translate(
                        offset: const Offset(0, -5),
                        child: Container(
                          width: 42,
                          height: 42,
                          decoration: const BoxDecoration(color: AppColors.gold2, shape: BoxShape.circle),
                          child: const Icon(Icons.add_rounded, color: AppColors.navy, size: 28),
                        ),
                      ),
                      Transform.translate(
                        offset: const Offset(0, -4),
                        child: const Text('جديد', style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w800)),
                      ),
                    ],
                  ),
                ),
              ),
              Expanded(child: _BottomItem(index: 3, label: 'التقارير', icon: Icons.bar_chart_rounded, selected: selected == 3, onTap: onChanged)),
              Expanded(child: _BottomItem(index: 4, label: 'الإعدادات', icon: Icons.settings_outlined, selected: selected == 4, onTap: onChanged)),
            ],
          ),
        ),
      ),
    );
  }
}

class _BottomItem extends StatelessWidget {
  const _BottomItem({
    required this.index,
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final int index;
  final String label;
  final IconData icon;
  final bool selected;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.gold2 : Colors.white70;
    return InkWell(
      onTap: () => onTap(index),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(label, maxLines: 1, style: TextStyle(color: color, fontSize: 9.5, fontWeight: FontWeight.w800)),
          ),
          const SizedBox(height: 2),
          Container(
            width: 18,
            height: 2,
            decoration: BoxDecoration(
              color: selected ? AppColors.gold2 : Colors.transparent,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ],
      ),
    );
  }
}

class _KpiData {
  const _KpiData(
    this.keyName,
    this.label,
    this.amount,
    this.growth,
    this.icon,
    this.iconColor,
    this.background,
    this.growthColor,
  );

  final String keyName;
  final String label;
  final double amount;
  final String growth;
  final IconData icon;
  final Color iconColor;
  final Color background;
  final Color growthColor;
}

class _ActionData {
  const _ActionData(this.label, this.icon, this.color, this.primary);

  final String label;
  final IconData icon;
  final Color color;
  final bool primary;
}

class _ModuleData {
  const _ModuleData(this.id, this.label, this.icon, this.primary, this.accent);

  final String id;
  final String label;
  final IconData icon;
  final Color primary;
  final Color accent;
}

class _OperationMeta {
  const _OperationMeta(this.label, this.icon, this.color);

  final String label;
  final IconData icon;
  final Color color;
}
