import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';

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
