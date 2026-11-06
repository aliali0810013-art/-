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
      builder: (context, child) => Directionality(textDirection: TextDirection.rtl, child: child ?? const SizedBox.shrink()),
      home: const AdminDashboard(),
    );
  }
}

class AdminDashboard extends StatelessWidget {
  const AdminDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    const navy = Color(0xFF0A2540);
    const gold = Color(0xFFE5A93C);
    const cards = [
      ('العملاء النشطون', '128', Icons.verified_user_outlined),
      ('تراخيص تنتهي قريباً', '9', Icons.event_busy_outlined),
      ('إجمالي المستخدمين', '374', Icons.groups_2_outlined),
      ('طلبات التفعيل', '6', Icons.key_outlined),
    ];
    return Scaffold(
      appBar: AppBar(
        backgroundColor: navy,
        foregroundColor: Colors.white,
        title: const Text('SINDAR Master Admin'),
        actions: const [Padding(padding: EdgeInsets.all(12), child: Icon(Icons.notifications_none_rounded))],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Center(child: SizedBox(height: 120, child: SvgPicture.asset('assets/branding/sindar_logo.svg'))),
          const SizedBox(height: 18),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final card in cards)
                SizedBox(
                  width: 260,
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Row(
                        children: [
                          CircleAvatar(backgroundColor: gold.withValues(alpha: .18), child: Icon(card.$3, color: navy)),
                          const SizedBox(width: 14),
                          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(card.$1, style: const TextStyle(fontWeight: FontWeight.w700)),
                            Text(card.$2, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 24, color: navy)),
                          ]),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 22),
          Card(
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
          ),
        ],
      ),
    );
  }
}
