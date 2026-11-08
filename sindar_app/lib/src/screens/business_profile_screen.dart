import 'package:flutter/material.dart';

import '../services/business_profile_service.dart';
import '../theme/app_theme.dart';

class BusinessProfileScreen extends StatefulWidget {
  const BusinessProfileScreen({super.key});

  @override
  State<BusinessProfileScreen> createState() => _BusinessProfileScreenState();
}

class _BusinessProfileScreenState extends State<BusinessProfileScreen> {
  final _service = const BusinessProfileService();
  BusinessModuleConfig _config = const BusinessModuleConfig();
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final config = await _service.load();
    if (!mounted) return;
    setState(() {
      _config = config;
      _loading = false;
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    await _service.save(_config);
    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تم حفظ أقسام النشاط. ستتحدث الرئيسية عند الرجوع إليها.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('طبيعة النشاط والأقسام')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                      'فعّل فقط أنواع العمل التي تستخدمها منشأتك. '
                      'المحاسبة والعملاء والتقارير تبقى موحدة، بينما تختفي '
                      'الأقسام التشغيلية غير المناسبة لنشاطك.',
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                _SwitchTile(
                  icon: Icons.point_of_sale_rounded,
                  title: 'البيع والأصناف',
                  subtitle: 'فواتير بيع ومخزون وأسعار شراء وبيع',
                  value: _config.sales,
                  onChanged: (v) => setState(() => _config = _config.copyWith(sales: v)),
                ),
                _SwitchTile(
                  icon: Icons.handyman_rounded,
                  title: 'التأجير والمعدات',
                  subtitle: 'بطاقات معدات وعروض وعقود وتأجير بالمدة',
                  value: _config.rentals,
                  onChanged: (v) => setState(() => _config = _config.copyWith(rentals: v)),
                ),
                _SwitchTile(
                  icon: Icons.design_services_outlined,
                  title: 'الخدمات',
                  subtitle: 'مستندات وفواتير خدمات بدون مخزون',
                  value: _config.services,
                  onChanged: (v) => setState(() => _config = _config.copyWith(services: v)),
                ),
                _SwitchTile(
                  icon: Icons.shopping_cart_checkout_rounded,
                  title: 'المشتريات',
                  subtitle: 'الموردون وفواتير الشراء وتحديث تكلفة الأصناف',
                  value: _config.purchases,
                  onChanged: (v) => setState(() => _config = _config.copyWith(purchases: v)),
                ),
                _SwitchTile(
                  icon: Icons.badge_outlined,
                  title: 'الموظفون والرواتب',
                  subtitle: 'الموظفون والرواتب والعهد وربط مسؤول العملية',
                  value: _config.payroll,
                  onChanged: (v) => setState(() => _config = _config.copyWith(payroll: v)),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: const Icon(Icons.save_outlined),
                  label: Text(_saving ? 'جارٍ الحفظ...' : 'حفظ الإعداد'),
                ),
              ],
            ),
    );
  }
}

class _SwitchTile extends StatelessWidget {
  const _SwitchTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: SwitchListTile(
        secondary: CircleAvatar(
          backgroundColor: AppColors.gold.withValues(alpha: .16),
          child: Icon(icon, color: AppColors.navy2),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
        subtitle: Text(subtitle),
        value: value,
        onChanged: onChanged,
      ),
    );
  }
}
