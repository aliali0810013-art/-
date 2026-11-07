// ignore_for_file: prefer_interpolation_to_compose_strings

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'license_store.dart';

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
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
      builder: (context, child) => Directionality(
        textDirection: TextDirection.rtl,
        child: child ?? const SizedBox.shrink(),
      ),
      home: const AdminDashboard(),
    );
  }
}

class AdminDashboard extends StatefulWidget {
  const AdminDashboard({super.key});

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  List<AdminLicenseRecord> _licenses = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final rows = await AdminLicenseStore.instance.list();
    if (!mounted) return;
    setState(() {
      _licenses = rows;
      _loading = false;
    });
  }

  Future<void> _edit([AdminLicenseRecord? existing]) async {
    final result = await showDialog<AdminLicenseRecord>(
      context: context,
      builder: (_) => _LicenseEditor(existing: existing),
    );
    if (result != null) await _refresh();
  }

  void _showToken(AdminLicenseRecord license) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('مفتاح التفعيل — ' + license.licenseNumber),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              QrImageView(
                data: license.token,
                size: 240,
                backgroundColor: Colors.white,
              ),
              const SizedBox(height: 12),
              SelectableText(
                license.token,
                maxLines: 5,
                style: const TextStyle(fontSize: 11),
              ),
            ],
          ),
        ),
        actions: [
          TextButton.icon(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: license.token));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('تم نسخ مفتاح التفعيل')),
              );
            },
            icon: const Icon(Icons.copy),
            label: const Text('نسخ'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إغلاق'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const navy = Color(0xFF0A2540);
    final active = _licenses.where((e) => e.isActive && e.expiresAt.isAfter(DateTime.now().toUtc())).length;
    final taxEnabled = _licenses.where((e) => e.isTaxEnabled).length;
    final users = _licenses.fold<int>(0, (sum, e) => sum + e.maxAllowedUsers);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: navy,
        foregroundColor: Colors.white,
        title: const Text('SINDAR Master Admin'),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(),
        icon: const Icon(Icons.add),
        label: const Text('ترخيص جديد'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  Center(
                    child: Container(
                      key: const ValueKey<String>('sindar-official-logo'),
                      width: 360,
                      constraints: const BoxConstraints(maxWidth: 360),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: const Color(0x33E5A93C),
                        ),
                      ),
                      child: Image.asset(
                        'assets/branding/sindar_brand_full.webp',
                        height: 92,
                        fit: BoxFit.contain,
                        filterQuality: FilterQuality.high,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final count = constraints.maxWidth >= 900 ? 4 : 2;
                      final metrics = [
                        ('العملاء', _licenses.length.toString(), Icons.apartment),
                        ('النشطون', active.toString(), Icons.verified_user_outlined),
                        ('سعات المستخدمين', users.toString(), Icons.groups_outlined),
                        ('الضريبة مفعلة', taxEnabled.toString(), Icons.receipt_long_outlined),
                      ];
                      return GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: metrics.length,
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: count,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                          childAspectRatio: count == 4 ? 1.8 : 1.6,
                        ),
                        itemBuilder: (_, i) => Card(
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Row(
                              children: [
                                CircleAvatar(child: Icon(metrics[i].$3)),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(metrics[i].$1, style: const TextStyle(fontWeight: FontWeight.w700)),
                                      Text(metrics[i].$2, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    'التراخيص',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 8),
                  if (_licenses.isEmpty)
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(28),
                        child: Center(child: Text('لا توجد تراخيص بعد')),
                      ),
                    ),
                  for (final license in _licenses)
                    Card(
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: license.isActive
                              ? Colors.green.withValues(alpha: .12)
                              : Colors.red.withValues(alpha: .12),
                          child: Icon(
                            license.isActive ? Icons.verified_outlined : Icons.block_outlined,
                            color: license.isActive ? Colors.green : Colors.red,
                          ),
                        ),
                        title: Text(
                          license.organizationName,
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                        subtitle: Text(
                          license.licenseNumber +
                              ' • ' +
                              license.currencyCode +
                              ' • مستخدمون ' +
                              license.maxAllowedUsers.toString() +
                              ' • ضريبة ' +
                              (license.isTaxEnabled ? 'مفعلة' : 'مقفلة') +
                              ' • ينتهي ' +
                              license.expiresAt.toIso8601String().split('T').first,
                        ),
                        trailing: Wrap(
                          spacing: 4,
                          children: [
                            IconButton(
                              tooltip: 'QR / Token',
                              onPressed: () => _showToken(license),
                              icon: const Icon(Icons.qr_code_2),
                            ),
                            IconButton(
                              tooltip: 'تعديل',
                              onPressed: () => _edit(license),
                              icon: const Icon(Icons.edit_outlined),
                            ),
                          ],
                        ),
                      ),
                    ),
                  const SizedBox(height: 90),
                ],
              ),
            ),
    );
  }
}

class _LicenseEditor extends StatefulWidget {
  const _LicenseEditor({this.existing});

  final AdminLicenseRecord? existing;

  @override
  State<_LicenseEditor> createState() => _LicenseEditorState();
}

class _LicenseEditorState extends State<_LicenseEditor> {
  late final TextEditingController _organization;
  late final TextEditingController _number;
  late final TextEditingController _maxUsers;
  late DateTime _expiresAt;
  late bool _active;
  late bool _tax;
  late String _country;
  late String _currency;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _organization = TextEditingController(text: e?.organizationName ?? '');
    _number = TextEditingController(
      text: e?.licenseNumber ??
          'LIC-' + DateTime.now().millisecondsSinceEpoch.toString().substring(7),
    );
    _maxUsers = TextEditingController(text: (e?.maxAllowedUsers ?? 3).toString());
    _expiresAt = e?.expiresAt ?? DateTime.now().toUtc().add(const Duration(days: 365));
    _active = e?.isActive ?? true;
    _tax = e?.isTaxEnabled ?? true;
    _country = e?.countryCode ?? 'SA';
    _currency = e?.currencyCode ?? 'SAR';
  }

  @override
  void dispose() {
    _organization.dispose();
    _number.dispose();
    _maxUsers.dispose();
    super.dispose();
  }

  String get _symbol => switch (_currency) {
        'SAR' => 'ر.س',
        'YER' => 'ر.ي',
        'USD' => r'$',
        _ => _currency,
      };

  Future<void> _pickDate() async {
    final selected = await showDatePicker(
      context: context,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 3650)),
      initialDate: _expiresAt,
    );
    if (selected != null) {
      setState(() => _expiresAt = DateTime.utc(selected.year, selected.month, selected.day, 23, 59, 59));
    }
  }

  Future<void> _save() async {
    try {
      final record = await AdminLicenseStore.instance.save(
        id: widget.existing?.id,
        organizationName: _organization.text,
        licenseNumber: _number.text,
        expiresAt: _expiresAt,
        isActive: _active,
        isTaxEnabled: _tax,
        countryCode: _country,
        currencyCode: _currency,
        currencySymbol: _symbol,
        maxAllowedUsers: int.tryParse(_maxUsers.text) ?? 1,
      );
      if (mounted) Navigator.pop(context, record);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.existing == null ? 'إنشاء ترخيص عميل' : 'تعديل الترخيص'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: _organization, decoration: const InputDecoration(labelText: 'اسم المنشأة')),
              const SizedBox(height: 8),
              TextField(controller: _number, decoration: const InputDecoration(labelText: 'رقم الترخيص')),
              const SizedBox(height: 8),
              TextField(
                controller: _maxUsers,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'maxAllowedUsers'),
              ),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('الحساب مفعل'),
                value: _active,
                onChanged: (v) => setState(() => _active = v),
              ),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('isTaxEnabled'),
                subtitle: const Text('إذا قفلته تختفي حقول الضريبة من تطبيق العميل'),
                value: _tax,
                onChanged: (v) => setState(() => _tax = v),
              ),
              DropdownButtonFormField<String>(
                initialValue: _country,
                decoration: const InputDecoration(labelText: 'الدولة'),
                items: const [
                  DropdownMenuItem(value: 'SA', child: Text('السعودية')),
                  DropdownMenuItem(value: 'YE', child: Text('اليمن')),
                  DropdownMenuItem(value: 'OTHER', child: Text('دولة أخرى')),
                ],
                onChanged: (value) {
                  if (value == null) return;
                  setState(() {
                    _country = value;
                    if (value == 'SA') _currency = 'SAR';
                    if (value == 'YE') _currency = 'YER';
                  });
                },
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                key: ValueKey(_currency),
                initialValue: _currency,
                decoration: const InputDecoration(labelText: 'العملة'),
                items: const [
                  DropdownMenuItem(value: 'SAR', child: Text('ريال سعودي')),
                  DropdownMenuItem(value: 'YER', child: Text('ريال يمني')),
                  DropdownMenuItem(value: 'USD', child: Text('دولار أمريكي')),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => _currency = value);
                },
              ),
              const SizedBox(height: 8),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('تاريخ الانتهاء'),
                subtitle: Text(_expiresAt.toIso8601String().split('T').first),
                trailing: const Icon(Icons.calendar_month_outlined),
                onTap: _pickDate,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
        FilledButton.icon(
          onPressed: _save,
          icon: const Icon(Icons.save_outlined),
          label: const Text('حفظ وتوليد Token/QR'),
        ),
      ],
    );
  }
}
