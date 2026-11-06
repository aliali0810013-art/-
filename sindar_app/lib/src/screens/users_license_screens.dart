// ignore_for_file: prefer_interpolation_to_compose_strings

import 'package:flutter/material.dart';
import 'package:sindar_core/sindar_core.dart';

import '../data/local/sindar_database.dart';
import '../services/erp_repository.dart';
import '../services/operational_models.dart';
import '../services/session_controller.dart';
import 'universal_scanner_screen.dart';

class UsersPermissionsScreen extends StatefulWidget {
  const UsersPermissionsScreen({super.key});

  @override
  State<UsersPermissionsScreen> createState() => _UsersPermissionsScreenState();
}

class _UsersPermissionsScreenState extends State<UsersPermissionsScreen> {
  static const modules = <String, String>{
    'sales': 'المبيعات',
    'purchases': 'المشتريات',
    'inventory': 'المخزون',
    'customers': 'العملاء',
    'suppliers': 'الموردون',
    'journals': 'القيود',
    'assets': 'الأصول والعهد',
    'payroll': 'الموظفون والرواتب',
    'reports': 'التقارير',
    'documents': 'المستندات',
    'settings': 'الإعدادات',
  };

  List<AppUserRecord> _users = const [];
  int _maxUsers = 1;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final users = await ErpRepository.instance.listUsers();
    final policy = await SindarDatabase.instance.getLicensePolicy();
    if (!mounted) return;
    setState(() {
      _users = users;
      _maxUsers = policy.maxUsers;
      _loading = false;
    });
  }

  Future<void> _addUser() async {
    final name = TextEditingController();
    final code = TextEditingController();
    final pin = TextEditingController();
    String role = 'cashier';
    final selectedModules = <String>{'sales'};

    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocalState) => AlertDialog(
          title: const Text('إضافة مستخدم وصلاحياته'),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(controller: name, decoration: const InputDecoration(labelText: 'الاسم')),
                  const SizedBox(height: 8),
                  TextField(controller: code, decoration: const InputDecoration(labelText: 'رقم / اسم الدخول')),
                  const SizedBox(height: 8),
                  TextField(
                    controller: pin,
                    obscureText: true,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'PIN'),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    initialValue: role,
                    decoration: const InputDecoration(labelText: 'الدور'),
                    items: const [
                      DropdownMenuItem(value: 'accountant', child: Text('محاسب')),
                      DropdownMenuItem(value: 'cashier', child: Text('كاشير / بائع')),
                      DropdownMenuItem(value: 'warehouse', child: Text('أمين مستودع')),
                      DropdownMenuItem(value: 'sales_rep', child: Text('مندوب')),
                    ],
                    onChanged: (value) {
                      if (value != null) setLocalState(() => role = value);
                    },
                  ),
                  const SizedBox(height: 12),
                  const Align(
                    alignment: Alignment.centerRight,
                    child: Text('الأقسام المسموح بها', style: TextStyle(fontWeight: FontWeight.w900)),
                  ),
                  for (final entry in modules.entries)
                    CheckboxListTile(
                      dense: true,
                      value: selectedModules.contains(entry.key),
                      title: Text(entry.value),
                      onChanged: (value) {
                        setLocalState(() {
                          if (value == true) {
                            selectedModules.add(entry.key);
                          } else {
                            selectedModules.remove(entry.key);
                          }
                        });
                      },
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('حفظ')),
          ],
        ),
      ),
    );

    if (accepted == true &&
        name.text.trim().isNotEmpty &&
        code.text.trim().isNotEmpty &&
        pin.text.isNotEmpty) {
      try {
        final permissions = [
          for (final module in selectedModules)
            PermissionSet(
              module: module,
              canView: true,
              canAdd: true,
              canEdit: role == 'accountant' || role == 'warehouse',
              canDelete: role == 'accountant',
              canApprove: role == 'accountant' || role == 'cashier',
              canPrint: true,
              canViewProfit: role == 'accountant',
            ),
        ];
        await ErpRepository.instance.createUser(
          name: name.text,
          role: role,
          loginCode: code.text,
          pin: pin.text,
          permissions: permissions,
        );
        await _refresh();
      } catch (error) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(error.toString())),
          );
        }
      }
    }

    name.dispose();
    code.dispose();
    pin.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('المستخدمون والصلاحيات')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _users.length >= _maxUsers ? null : _addUser,
        icon: const Icon(Icons.person_add_alt_1),
        label: const Text('مستخدم جديد'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.groups_2_outlined),
                    title: Text('المستخدمون: ' + _users.length.toString() + ' / ' + _maxUsers.toString()),
                    subtitle: Text(
                      _users.length >= _maxUsers
                          ? 'تم الوصول للحد الأقصى المحدد في الترخيص.'
                          : 'يمكن إضافة مستخدمين ضمن حد الترخيص.',
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                for (final user in _users)
                  Card(
                    child: ListTile(
                      leading: CircleAvatar(
                        child: Icon(user.isSystemAdmin ? Icons.admin_panel_settings : Icons.person_outline),
                      ),
                      title: Text(user.name, style: const TextStyle(fontWeight: FontWeight.w800)),
                      subtitle: Text(user.role + ' • دخول: ' + user.loginCode),
                      trailing: user.isSystemAdmin
                          ? const Chip(label: Text('مدير النظام'))
                          : const Icon(Icons.security_outlined),
                    ),
                  ),
              ],
            ),
    );
  }
}

class LicenseActivationScreen extends StatefulWidget {
  const LicenseActivationScreen({super.key});

  @override
  State<LicenseActivationScreen> createState() => _LicenseActivationScreenState();
}

class _LicenseActivationScreenState extends State<LicenseActivationScreen> {
  final _token = TextEditingController();
  String _status = '';
  LicenseGrant? _grant;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _token.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final grant = await ErpRepository.instance.currentLicenseGrant();
    if (!mounted) return;
    setState(() => _grant = grant);
  }

  Future<void> _scan() async {
    final result = await Navigator.of(context).push<UniversalBarcodeResult>(
      MaterialPageRoute(builder: (_) => const UniversalScannerScreen()),
    );
    if (result == null) return;
    _token.text = result.rawValue;
  }

  Future<void> _apply() async {
    try {
      await ErpRepository.instance.applyLicenseToken(_token.text);
      final grant = await ErpRepository.instance.currentLicenseGrant();
      if (!mounted) return;
      setState(() {
        _grant = grant;
        _status = 'تم تطبيق الترخيص والقيود فوراً.';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _status = error.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final grant = _grant;
    return Scaffold(
      appBar: AppBar(title: const Text('تفعيل ترخيص SINDAR')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (grant != null)
            Card(
              child: ListTile(
                leading: Icon(
                  grant.canOperate ? Icons.verified_outlined : Icons.block_outlined,
                  color: grant.canOperate ? Colors.green : Colors.red,
                ),
                title: Text(grant.organizationName),
                subtitle: Text(
                  grant.licenseNumber +
                      ' • انتهاء: ' +
                      grant.expiresAt.toIso8601String().split('T').first +
                      ' • مستخدمون: ' +
                      grant.policy.maxUsers.toString() +
                      ' • ضريبة: ' +
                      (grant.policy.isTaxEnabled ? 'مفعلة' : 'مقفلة'),
                ),
              ),
            ),
          const SizedBox(height: 12),
          TextField(
            controller: _token,
            minLines: 4,
            maxLines: 8,
            decoration: const InputDecoration(
              labelText: 'License Token',
              hintText: 'ألصق مفتاح التفعيل أو امسح QR',
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _scan,
                  icon: const Icon(Icons.qr_code_scanner),
                  label: const Text('مسح QR'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _apply,
                  icon: const Icon(Icons.key_outlined),
                  label: const Text('تطبيق الترخيص'),
                ),
              ),
            ],
          ),
          if (_status.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(_status, style: const TextStyle(fontWeight: FontWeight.w800)),
          ],
        ],
      ),
    );
  }
}

class SwitchUserDialog extends StatefulWidget {
  const SwitchUserDialog({super.key});

  @override
  State<SwitchUserDialog> createState() => _SwitchUserDialogState();
}

class _SwitchUserDialogState extends State<SwitchUserDialog> {
  final _code = TextEditingController();
  final _pin = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    _pin.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    final ok = await SessionController.instance.switchUser(
      _code.text,
      _pin.text,
    );
    if (!mounted) return;
    if (ok) {
      Navigator.pop(context, true);
    } else {
      setState(() => _error = 'بيانات الدخول غير صحيحة');
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('تبديل المستخدم'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(controller: _code, decoration: const InputDecoration(labelText: 'رقم / اسم الدخول')),
          const SizedBox(height: 8),
          TextField(
            controller: _pin,
            obscureText: true,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'PIN'),
            onSubmitted: (_) => _login(),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: const TextStyle(color: Colors.red)),
          ],
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
        FilledButton(onPressed: _login, child: const Text('دخول')),
      ],
    );
  }
}
