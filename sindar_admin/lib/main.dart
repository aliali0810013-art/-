import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:sindar_core/sindar_core.dart';

void main() => runApp(const SindarAdminApp());

class SindarAdminApp extends StatelessWidget {
  const SindarAdminApp({super.key});

  @override
  Widget build(BuildContext context) {
    const navy = Color(0xFF0A2540);
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'SINDAR Master Admin',
      locale: const Locale('ar'),
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF4F7FA),
        colorScheme: ColorScheme.fromSeed(seedColor: navy),
        textTheme: GoogleFonts.cairoTextTheme(),
      ),
      builder: (context, child) => Directionality(
        textDirection: TextDirection.rtl,
        child: child ?? const SizedBox.shrink(),
      ),
      home: const AdminDashboard(),
    );
  }
}

class AdminDashboard extends StatelessWidget {
  const AdminDashboard({super.key});

  static const _cards = <_AdminMetric>[
    _AdminMetric('العملاء النشطون', '128', Icons.verified_user_outlined),
    _AdminMetric('تراخيص تنتهي قريباً', '9', Icons.event_busy_outlined),
    _AdminMetric('إجمالي المستخدمين', '374', Icons.groups_2_outlined),
    _AdminMetric('طلبات التفعيل', '6', Icons.key_outlined),
  ];

  @override
  Widget build(BuildContext context) {
    const navy = Color(0xFF0A2540);
    return Scaffold(
      appBar: AppBar(
        backgroundColor: navy,
        foregroundColor: Colors.white,
        title: const Text('SINDAR Master Admin'),
        actions: const [
          Padding(
            padding: EdgeInsetsDirectional.only(end: 16),
            child: Icon(Icons.notifications_none_rounded),
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final columns = constraints.maxWidth >= 1000 ? 4 : constraints.maxWidth >= 620 ? 2 : 1;
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 430),
                  child: SizedBox(
                    height: 118,
                    child: SvgPicture.asset('assets/branding/sindar_logo.svg', fit: BoxFit.contain),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              GridView.builder(
                itemCount: _cards.length,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: columns == 1 ? 3.0 : 2.15,
                ),
                itemBuilder: (context, index) => _MetricCard(metric: _cards[index]),
              ),
              const SizedBox(height: 22),
              const _ActivationPanel(),
              const SizedBox(height: 18),
              const _TaxLicensePanel(),
            ],
          );
        },
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.metric});
  final _AdminMetric metric;

  @override
  Widget build(BuildContext context) {
    const navy = Color(0xFF0A2540);
    const gold = Color(0xFFE5A93C);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: gold.withValues(alpha: .18),
              child: Icon(metric.icon, color: navy),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(metric.label, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                  Text(metric.value, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 24, color: navy)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActivationPanel extends StatelessWidget {
  const _ActivationPanel();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('إدارة التفعيل', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
            const SizedBox(height: 16),
            FilledButton.icon(onPressed: () {}, icon: const Icon(Icons.person_add_alt_1), label: const Text('إنشاء عميل وإصدار كود تفعيل')),
            const SizedBox(height: 10),
            OutlinedButton.icon(onPressed: () {}, icon: const Icon(Icons.manage_accounts_outlined), label: const Text('إدارة عدد المستخدمين والباقات')),
            const SizedBox(height: 10),
            OutlinedButton.icon(onPressed: () {}, icon: const Icon(Icons.toggle_on_outlined), label: const Text('إيقاف أو إعادة تفعيل اشتراك')),
          ],
        ),
      ),
    );
  }
}

class _AdminMetric {
  const _AdminMetric(this.label, this.value, this.icon);
  final String label;
  final String value;
  final IconData icon;
}


class _TaxLicensePanel extends StatefulWidget {
  const _TaxLicensePanel();

  @override
  State<_TaxLicensePanel> createState() => _TaxLicensePanelState();
}

class _TaxLicensePanelState extends State<_TaxLicensePanel> {
  bool _isTaxEnabled = true;
  String _countryCode = 'SA';
  String _currencyCode = 'SAR';
  int _maxUsers = 3;

  String get _currencySymbol => switch (_currencyCode) {
        'SAR' => 'ر.س',
        'YER' => 'ر.ي',
        'USD' => r'$',
        _ => _currencyCode,
      };

  LicensePolicy get _policy => LicensePolicy(
        customerId: 'selected-client',
        isTaxEnabled: _isTaxEnabled,
        countryCode: _countryCode,
        currencyCode: _currencyCode,
        currencySymbol: _currencySymbol,
        maxUsers: _maxUsers,
      );

  @override
  Widget build(BuildContext context) {
    const navy = Color(0xFF0A2540);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'سياسة الترخيص والضريبة',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: const Text(
                'تفعيل النظام الضريبي والرقم الضريبي',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              subtitle: Text(
                _isTaxEnabled
                    ? 'Enabled — يسمح بالفواتير الضريبية وZATCA والرقم الضريبي.'
                    : 'Locked — يخفي حقول الضريبة ويحوّل الفواتير إلى تجارية.',
              ),
              value: _isTaxEnabled,
              onChanged: (value) => setState(() => _isTaxEnabled = value),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                SizedBox(
                  width: 240,
                  child: DropdownButtonFormField<String>(
                    value: _countryCode,
                    decoration: const InputDecoration(labelText: 'الدولة'),
                    items: const [
                      DropdownMenuItem(value: 'SA', child: Text('السعودية')),
                      DropdownMenuItem(value: 'YE', child: Text('اليمن')),
                      DropdownMenuItem(value: 'US', child: Text('دولة أخرى')),
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() {
                        _countryCode = value;
                        if (value == 'SA') _currencyCode = 'SAR';
                        if (value == 'YE') _currencyCode = 'YER';
                      });
                    },
                  ),
                ),
                SizedBox(
                  width: 240,
                  child: DropdownButtonFormField<String>(
                    value: _currencyCode,
                    decoration: const InputDecoration(labelText: 'العملة'),
                    items: const [
                      DropdownMenuItem(value: 'SAR', child: Text('ريال سعودي ر.س')),
                      DropdownMenuItem(value: 'YER', child: Text('ريال يمني ر.ي')),
                      DropdownMenuItem(value: 'USD', child: Text('دولار $')),
                    ],
                    onChanged: (value) {
                      if (value != null) setState(() => _currencyCode = value);
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'الحد الأقصى للمستخدمين',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                IconButton(
                  onPressed: _maxUsers > 1 ? () => setState(() => _maxUsers--) : null,
                  icon: const Icon(Icons.remove_circle_outline),
                ),
                Text('$_maxUsers', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
                IconButton(
                  onPressed: () => setState(() => _maxUsers++),
                  icon: const Icon(Icons.add_circle_outline),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF4F7FA),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                'السياسة الحالية: tax=${_policy.isTaxEnabled} • ${_policy.countryCode} • ${_policy.currencyCode} • maxUsers=${_policy.maxUsers}',
                style: const TextStyle(color: navy, fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: () {
                final policy = _policy;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      'تم تجهيز سياسة الترخيص: ${policy.isTaxEnabled ? "ضريبي" : "غير ضريبي"} — ${policy.currencyCode}',
                    ),
                  ),
                );
              },
              icon: const Icon(Icons.save_outlined),
              label: const Text('حفظ سياسة الترخيص للعميل المحدد'),
            ),
          ],
        ),
      ),
    );
  }
}
