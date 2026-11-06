import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../theme/app_theme.dart';
import 'chart_of_accounts_screen.dart';

class HomeDashboardScreen extends StatefulWidget {
  const HomeDashboardScreen({super.key});

  @override
  State<HomeDashboardScreen> createState() => _HomeDashboardScreenState();
}

class _HomeDashboardScreenState extends State<HomeDashboardScreen> {
  int _navIndex = 0;

  static const _kpis = <_KpiData>[
    _KpiData('المبيعات', '146,500.00', '+15.3%', Icons.bar_chart_rounded, AppColors.gold, AppColors.cream, AppColors.green),
    _KpiData('المشتريات', '68,750.00', '+9.1%', Icons.shopping_cart_outlined, AppColors.blue, AppColors.sky, AppColors.green),
    _KpiData('المصروفات', '17,320.00', '+6.4%', Icons.receipt_long_outlined, Color(0xFFC84747), AppColors.rose, AppColors.red),
    _KpiData('الأرباح', '28,450.00', '+12.8%', Icons.toll_rounded, AppColors.green, AppColors.mint, AppColors.green),
  ];

  static const _modules = <_ModuleData>[
    _ModuleData('العملاء', Icons.groups_rounded, Color(0xFF0D3A72), AppColors.gold),
    _ModuleData('الموردون', Icons.local_shipping_outlined, Color(0xFF0D3A72), AppColors.gold),
    _ModuleData('شجرة\nالحسابات', Icons.account_tree_outlined, AppColors.gold, Color(0xFF0D3A72)),
    _ModuleData('القيود\nاليومية', Icons.menu_book_rounded, Color(0xFF0D3A72), AppColors.gold),
    _ModuleData('التقارير\nوالتحليلات', Icons.query_stats_rounded, Color(0xFF0D3A72), AppColors.gold),
    _ModuleData('المشتريات', Icons.shopping_cart_outlined, Color(0xFF0D3A72), AppColors.gold),
    _ModuleData('المخزون\nوالأصناف', Icons.inventory_2_outlined, AppColors.gold, Color(0xFF0D3A72)),
    _ModuleData('الأصول\nوالعهد', Icons.corporate_fare_rounded, Color(0xFF0D3A72), AppColors.gold),
    _ModuleData('الموظفون\nوالرواتب', Icons.business_center_outlined, Color(0xFF0D3A72), AppColors.gold),
    _ModuleData('المستخدمون\nوالصلاحيات', Icons.admin_panel_settings_outlined, Color(0xFF0D3A72), AppColors.gold),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        top: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final desktop = width >= 900;
            final contentWidth = desktop ? 1180.0 : width;
            return Align(
              alignment: Alignment.topCenter,
              child: SizedBox(
                width: contentWidth,
                child: CustomScrollView(
                  slivers: [
                    SliverToBoxAdapter(child: _TopHeader(desktop: desktop)),
                    SliverPadding(
                      padding: EdgeInsets.fromLTRB(desktop ? 28 : 16, 18, desktop ? 28 : 16, 120),
                      sliver: SliverList(
                        delegate: SliverChildListDelegate([
                          _WelcomeFilters(desktop: desktop),
                          const SizedBox(height: 18),
                          _KpiGrid(desktop: desktop, data: _kpis),
                          const SizedBox(height: 20),
                          _QuickActions(desktop: desktop),
                          const SizedBox(height: 20),
                          _ModulesGrid(
                            desktop: desktop,
                            modules: _modules,
                            onTap: (module) {
                              if (module.label.contains('شجرة')) {
                                Navigator.of(context).push(
                                  MaterialPageRoute<void>(builder: (_) => const ChartOfAccountsScreen()),
                                );
                              }
                            },
                          ),
                          const SizedBox(height: 20),
                          const _RecentTransactions(),
                        ]),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
      bottomNavigationBar: _BottomNav(
        selected: _navIndex,
        onChanged: (value) => setState(() => _navIndex = value),
      ),
    );
  }
}

class _TopHeader extends StatelessWidget {
  const _TopHeader({required this.desktop});
  final bool desktop;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: desktop ? 160 : 198,
      padding: EdgeInsets.fromLTRB(desktop ? 28 : 16, desktop ? 24 : 40, desktop ? 28 : 16, 16),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF061D38), AppColors.navy2, Color(0xFF0B3763)],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(34)),
      ),
      child: desktop
          ? Row(
              children: [
                const _HeaderTools(),
                const Spacer(),
                SizedBox(
                  width: 360,
                  height: 116,
                  child: SvgPicture.asset('assets/branding/sindar_logo.svg', fit: BoxFit.contain),
                ),
                const Spacer(),
                const _CompanySelector(),
              ],
            )
          : Row(
              children: [
                const Expanded(child: _HeaderTools()),
                SizedBox(
                  width: 228,
                  height: 86,
                  child: SvgPicture.asset('assets/branding/sindar_logo.svg', fit: BoxFit.contain),
                ),
                const Expanded(child: Align(alignment: Alignment.centerLeft, child: _CompanySelector(compact: true))),
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
        Stack(
          clipBehavior: Clip.none,
          children: [
            const Icon(Icons.notifications_none_rounded, color: Colors.white, size: 29),
            Positioned(
              right: 1,
              top: -1,
              child: Container(
                width: 10,
                height: 10,
                decoration: const BoxDecoration(color: Colors.orange, shape: BoxShape.circle),
              ),
            ),
          ],
        ),
        const SizedBox(width: 18),
        const Icon(Icons.chat_outlined, color: Colors.white, size: 27),
        const SizedBox(width: 18),
        const Icon(Icons.search_rounded, color: Colors.white, size: 31),
      ],
    );
  }
}

class _CompanySelector extends StatelessWidget {
  const _CompanySelector({this.compact = false});
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          border: Border.all(color: Colors.white24),
          borderRadius: BorderRadius.circular(16),
          color: Colors.white.withValues(alpha: .05),
        ),
        child: const Icon(Icons.apartment_rounded, color: Colors.white, size: 24),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.white24),
        borderRadius: BorderRadius.circular(28),
        color: Colors.white.withValues(alpha: .05),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.apartment_rounded, color: Colors.white, size: 27),
          SizedBox(width: 10),
          Text('مؤسسة سندار\nالتجارية', textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, height: 1.35)),
          SizedBox(width: 8),
          Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white),
        ],
      ),
    );
  }
}

class _WelcomeFilters extends StatelessWidget {
  const _WelcomeFilters({required this.desktop});
  final bool desktop;

  @override
  Widget build(BuildContext context) {
    final welcome = Row(
      children: [
        Container(
          width: 58,
          height: 58,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(colors: [Color(0xFF194F87), AppColors.navy]),
          ),
          child: const Icon(Icons.person_rounded, color: Colors.white, size: 34),
        ),
        const SizedBox(width: 12),
        const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('مرحباً بك', style: TextStyle(fontSize: 14, color: AppColors.muted)),
            Text('مدير النظام', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.text)),
          ],
        ),
      ],
    );

    const filters = Row(
      children: [
        Expanded(child: _FilterBox(icon: Icons.storefront_outlined, label: 'الفرع الرئيسي')),
        SizedBox(width: 12),
        Expanded(child: _FilterBox(icon: Icons.calendar_month_outlined, label: 'نوفمبر 2026')),
      ],
    );

    if (desktop) {
      return Row(
        children: [
          Expanded(child: welcome),
          const SizedBox(width: 26),
          const SizedBox(width: 520, child: filters),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        welcome,
        const SizedBox(height: 16),
        filters,
      ],
    );
  }
}

class _FilterBox extends StatelessWidget {
  const _FilterBox({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 58,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: const Color(0xFFD9E1EA)),
      ),
      child: Row(
        children: [
          Icon(icon, color: AppColors.navy2, size: 24),
          const Spacer(),
          Flexible(child: Text(label, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15))),
          const SizedBox(width: 6),
          const Icon(Icons.keyboard_arrow_down_rounded, color: AppColors.navy),
        ],
      ),
    );
  }
}

class _KpiGrid extends StatelessWidget {
  const _KpiGrid({required this.desktop, required this.data});
  final bool desktop;
  final List<_KpiData> data;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: data.length,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: desktop ? 4 : 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: desktop ? 1.45 : 1.36,
      ),
      itemBuilder: (context, index) => _KpiCard(data: data[index]),
    );
  }
}

class _KpiCard extends StatelessWidget {
  const _KpiCard({required this.data});
  final _KpiData data;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: data.background,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white),
        boxShadow: const [BoxShadow(color: Color(0x120A2540), blurRadius: 18, offset: Offset(0, 8))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(data.icon, color: data.iconColor, size: 31),
          const Spacer(),
          Text(data.label, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Flexible(child: Text(data.amount, maxLines: 1, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w900))),
              const SizedBox(width: 4),
              const Padding(padding: EdgeInsets.only(bottom: 3), child: Text('ر.س', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12))),
            ],
          ),
          const SizedBox(height: 3),
          Text('↗ ${data.growth}', style: TextStyle(color: data.growthColor, fontWeight: FontWeight.w800, fontSize: 13)),
        ],
      ),
    );
  }
}

class _QuickActions extends StatelessWidget {
  const _QuickActions({required this.desktop});
  final bool desktop;

  @override
  Widget build(BuildContext context) {
    const actions = [
      _ActionData('فاتورة جديدة', Icons.note_add_outlined, Colors.white, true),
      _ActionData('عرض سعر', Icons.description_outlined, AppColors.purple, false),
      _ActionData('سند قبض', Icons.receipt_long_outlined, AppColors.green, false),
      _ActionData('سند صرف', Icons.post_add_outlined, Color(0xFFC84747), false),
      _ActionData('المزيد', Icons.more_horiz_rounded, AppColors.navy, false),
    ];
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(25),
        boxShadow: const [BoxShadow(color: Color(0x120A2540), blurRadius: 22, offset: Offset(0, 8))],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final itemWidth = desktop ? (constraints.maxWidth - 48) / 5 : 138.0;
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (var i = 0; i < actions.length; i++) ...[
                  SizedBox(width: itemWidth, child: _ActionCard(data: actions[i])),
                  if (i != actions.length - 1) const SizedBox(width: 12),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({required this.data});
  final _ActionData data;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 118,
      decoration: BoxDecoration(
        gradient: data.primary
            ? const LinearGradient(colors: [Color(0xFF0A315A), Color(0xFF0D457A)])
            : null,
        color: data.primary ? null : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: data.primary ? AppColors.gold2 : const Color(0xFFE5EAF0), width: data.primary ? 3 : 1),
        boxShadow: const [BoxShadow(color: Color(0x180A2540), blurRadius: 14, offset: Offset(0, 6))],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(data.icon, color: data.color, size: 38),
          const SizedBox(height: 8),
          Text(data.label, textAlign: TextAlign.center, style: TextStyle(color: data.primary ? Colors.white : AppColors.text, fontWeight: FontWeight.w800, fontSize: 16)),
        ],
      ),
    );
  }
}

class _ModulesGrid extends StatelessWidget {
  const _ModulesGrid({required this.desktop, required this.modules, required this.onTap});
  final bool desktop;
  final List<_ModuleData> modules;
  final ValueChanged<_ModuleData> onTap;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      itemCount: modules.length,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: desktop ? 5 : 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: desktop ? 1.24 : 1.16,
      ),
      itemBuilder: (context, index) => _ModuleCard(data: modules[index], onTap: () => onTap(modules[index])),
    );
  }
}

class _ModuleCard extends StatelessWidget {
  const _ModuleCard({required this.data, required this.onTap});
  final _ModuleData data;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: const Color(0xFFE6EBF1)),
            boxShadow: const [BoxShadow(color: Color(0x110A2540), blurRadius: 18, offset: Offset(0, 7))],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Stack(
                alignment: Alignment.bottomRight,
                children: [
                  Icon(data.icon, color: data.primary, size: 43),
                  Container(width: 12, height: 12, decoration: BoxDecoration(color: data.accent, shape: BoxShape.circle)),
                ],
              ),
              const SizedBox(height: 10),
              Text(data.label, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, height: 1.25)),
            ],
          ),
        ),
      ),
    );
  }
}

class _RecentTransactions extends StatelessWidget {
  const _RecentTransactions();

  static const _rows = [
    _TransactionData('فاتورة ضريبية', 'شركة النخبة للتوريدات', 'INV-000245', '2026-11-06', '4,600.00', 'معتمدة', AppColors.blue, AppColors.green),
    _TransactionData('عرض سعر', 'مؤسسة الإتقان', 'QUO-000128', '2026-11-06', '7,500.00', 'عرض سعر', AppColors.purple, AppColors.purple),
    _TransactionData('سند قبض', 'العميل: مطاعم السحاب', 'REC-000067', '2026-11-05', '2,000.00', 'سند قبض', AppColors.green, AppColors.green),
    _TransactionData('فاتورة مشتريات', 'مؤسسة المواد الغذائية', 'PUR-000097', '2026-11-04', '1,350.00', 'مشتريات', Colors.orange, Colors.orange),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(26),
        boxShadow: const [BoxShadow(color: Color(0x120A2540), blurRadius: 22, offset: Offset(0, 8))],
      ),
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 8),
      child: Column(
        children: [
          const Row(
            children: [
              Icon(Icons.description_outlined, color: AppColors.gold, size: 27),
              SizedBox(width: 8),
              Text('آخر العمليات', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 22)),
              Spacer(),
              Text('عرض الكل', style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.navy2)),
              SizedBox(width: 4),
              Icon(Icons.arrow_back_ios_new_rounded, size: 14, color: AppColors.navy2),
            ],
          ),
          const SizedBox(height: 10),
          const Divider(height: 1),
          for (final row in _rows) _TransactionRow(data: row),
        ],
      ),
    );
  }
}

class _TransactionRow extends StatelessWidget {
  const _TransactionRow({required this.data});
  final _TransactionData data;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(color: data.iconColor.withValues(alpha: .10), borderRadius: BorderRadius.circular(13)),
            child: Icon(Icons.description_outlined, color: data.iconColor),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(data.title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                Text(data.party, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.muted, fontSize: 12)),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: Column(
              children: [
                Text(data.date, style: const TextStyle(fontSize: 12, color: AppColors.muted)),
                Text(data.number, style: const TextStyle(fontSize: 12, color: AppColors.navy2, fontWeight: FontWeight.w700)),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
            decoration: BoxDecoration(color: data.statusColor.withValues(alpha: .10), borderRadius: BorderRadius.circular(12)),
            child: Text(data.status, style: TextStyle(color: data.statusColor, fontSize: 11, fontWeight: FontWeight.w800)),
          ),
          const SizedBox(width: 8),
          Text('${data.amount} ر.س', style: TextStyle(color: data.statusColor, fontWeight: FontWeight.w900, fontSize: 13)),
          const SizedBox(width: 4),
          const Icon(Icons.more_vert_rounded, color: AppColors.navy, size: 20),
        ],
      ),
    );
  }
}

class _BottomNav extends StatelessWidget {
  const _BottomNav({required this.selected, required this.onChanged});
  final int selected;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final items = const [
      (Icons.home_rounded, 'الرئيسية'),
      (Icons.description_outlined, 'المستندات'),
      (Icons.add_rounded, 'جديد'),
      (Icons.bar_chart_rounded, 'التقارير'),
      (Icons.settings_outlined, 'الإعدادات'),
    ];

    return Container(
      height: 104,
      decoration: const BoxDecoration(
        gradient: LinearGradient(colors: [Color(0xFF061D38), Color(0xFF0A3763)]),
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
        boxShadow: [BoxShadow(color: Color(0x330A2540), blurRadius: 20, offset: Offset(0, -6))],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: List.generate(items.length, (index) {
          if (index == 2) {
            return Transform.translate(
              offset: const Offset(0, -14),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  GestureDetector(
                    onTap: () => onChanged(index),
                    child: Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        color: AppColors.gold2,
                        shape: BoxShape.circle,
                        border: Border.all(color: const Color(0xFFFFD36A), width: 2),
                        boxShadow: const [BoxShadow(color: Color(0x44F5B041), blurRadius: 16, offset: Offset(0, 6))],
                      ),
                      child: const Icon(Icons.add_rounded, color: AppColors.navy, size: 40),
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text('جديد', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                ],
              ),
            );
          }
          final active = selected == index;
          return InkWell(
            onTap: () => onChanged(index),
            child: SizedBox(
              width: 72,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(items[index].$1, color: active ? AppColors.gold2 : Colors.white, size: 29),
                  const SizedBox(height: 4),
                  Text(items[index].$2, style: TextStyle(color: active ? AppColors.gold2 : Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
                  const SizedBox(height: 6),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    width: active ? 44 : 0,
                    height: 3,
                    decoration: BoxDecoration(color: AppColors.gold2, borderRadius: BorderRadius.circular(4)),
                  ),
                ],
              ),
            ),
          );
        }),
      ),
    );
  }
}

class _KpiData {
  const _KpiData(this.label, this.amount, this.growth, this.icon, this.iconColor, this.background, this.growthColor);
  final String label;
  final String amount;
  final String growth;
  final IconData icon;
  final Color iconColor;
  final Color background;
  final Color growthColor;
}

class _ModuleData {
  const _ModuleData(this.label, this.icon, this.primary, this.accent);
  final String label;
  final IconData icon;
  final Color primary;
  final Color accent;
}

class _ActionData {
  const _ActionData(this.label, this.icon, this.color, this.primary);
  final String label;
  final IconData icon;
  final Color color;
  final bool primary;
}

class _TransactionData {
  const _TransactionData(this.title, this.party, this.number, this.date, this.amount, this.status, this.iconColor, this.statusColor);
  final String title;
  final String party;
  final String number;
  final String date;
  final String amount;
  final String status;
  final Color iconColor;
  final Color statusColor;
}
