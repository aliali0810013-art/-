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
    'settings': 'الإعدادات والتراخيص',
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

  Map<String, _PermissionDraft> _preset(String role) {
    final result = {
      for (final module in modules.keys) module: _PermissionDraft(),
    };

    void allow(
      String module, {
      bool add = false,
      bool edit = false,
      bool delete = false,
      bool approve = false,
      bool print = false,
      bool profit = false,
    }) {
      result[module] = _PermissionDraft(
        view: true,
        add: add,
        edit: edit,
        delete: delete,
        approve: approve,
        print: print,
        profit: profit,
      );
    }

    switch (role) {
      case 'accountant':
        for (final module in modules.keys) {
          allow(
            module,
            add: true,
            edit: true,
            delete: module == 'journals' || module == 'documents',
            approve: true,
            print: true,
            profit: module == 'reports',
          );
        }
        break;
      case 'cashier':
        allow('sales', add: true, approve: true, print: true);
        allow('customers', add: true, edit: true, print: true);
        allow('documents', add: true, approve: true, print: true);
        allow('inventory');
        break;
      case 'warehouse':
        allow('inventory', add: true, edit: true, print: true);
        allow('purchases', add: true, edit: true, approve: true, print: true);
        allow('suppliers', add: true, edit: true, print: true);
        break;
      case 'sales_rep':
        allow('sales', add: true, print: true);
        allow('customers', add: true, edit: true, print: true);
        allow('documents', add: true, print: true);
        break;
    }
    return result;
  }

  Future<void> _addUser() async {
    if (_users.length >= _maxUsers) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('تم الوصول إلى حد الترخيص: $_maxUsers مستخدمين'),
        ),
      );
      return;
    }

    final name = TextEditingController();
    final code = TextEditingController();
    final pin = TextEditingController();
    var role = 'cashier';
    var permissions = _preset(role);

    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocalState) => AlertDialog(
          title: const Text('إضافة مستخدم وصلاحياته الدقيقة'),
          content: SizedBox(
            width: 560,
            height: MediaQuery.sizeOf(context).height * .72,
            child: ListView(
              children: [
                TextField(
                  controller: name,
                  decoration: const InputDecoration(labelText: 'الاسم'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: code,
                  decoration: const InputDecoration(labelText: 'رقم / اسم الدخول'),
                ),
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
                    if (value == null) return;
                    setLocalState(() {
                      role = value;
                      permissions = _preset(role);
                    });
                  },
                ),
                const SizedBox(height: 12),
                const Text(
                  'الصلاحيات — يمكن تعديل كل صلاحية بعد اختيار الدور',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 6),
                for (final entry in modules.entries)
                  Card(
                    margin: const EdgeInsets.only(bottom: 6),
                    child: ExpansionTile(
                      leading: Checkbox(
                        value: permissions[entry.key]!.view,
                        onChanged: (value) => setLocalState(
                          () => permissions[entry.key]!.view = value == true,
                        ),
                      ),
                      title: Text(
                        entry.value,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      subtitle: Text(
                        permissions[entry.key]!.view
                            ? 'القسم ظاهر — اضبط العمليات المسموحة'
                            : 'القسم مخفي عن المستخدم',
                      ),
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                          child: Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            children: [
                              _PermissionChip(
                                label: 'إضافة',
                                selected: permissions[entry.key]!.add,
                                onChanged: (value) => setLocalState(
                                  () => permissions[entry.key]!.add = value,
                                ),
                              ),
                              _PermissionChip(
                                label: 'تعديل',
                                selected: permissions[entry.key]!.edit,
                                onChanged: (value) => setLocalState(
                                  () => permissions[entry.key]!.edit = value,
                                ),
                              ),
                              _PermissionChip(
                                label: 'حذف',
                                selected: permissions[entry.key]!.delete,
                                onChanged: (value) => setLocalState(
                                  () => permissions[entry.key]!.delete = value,
                                ),
                              ),
                              _PermissionChip(
                                label: 'اعتماد',
                                selected: permissions[entry.key]!.approve,
                                onChanged: (value) => setLocalState(
                                  () => permissions[entry.key]!.approve = value,
                                ),
                              ),
                              _PermissionChip(
                                label: 'طباعة',
                                selected: permissions[entry.key]!.print,
                                onChanged: (value) => setLocalState(
                                  () => permissions[entry.key]!.print = value,
                                ),
                              ),
                              if (entry.key == 'reports')
                                _PermissionChip(
                                  label: 'رؤية الأرباح',
                                  selected: permissions[entry.key]!.profit,
                                  onChanged: (value) => setLocalState(
                                    () => permissions[entry.key]!.profit = value,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('حفظ المستخدم'),
            ),
          ],
        ),
      ),
    );

    if (accepted == true &&
        name.text.trim().isNotEmpty &&
        code.text.trim().isNotEmpty &&
        pin.text.isNotEmpty) {
      try {
        await ErpRepository.instance.createUser(
          name: name.text,
          role: role,
          loginCode: code.text,
          pin: pin.text,
          permissions: [
            for (final entry in permissions.entries)
              PermissionSet(
                module: entry.key,
                canView: entry.value.view,
                canAdd: entry.value.add,
                canEdit: entry.value.edit,
                canDelete: entry.value.delete,
                canApprove: entry.value.approve,
                canPrint: entry.value.print,
                canViewProfit: entry.value.profit,
              ),
          ],
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
                    title: Text('المستخدمون: ${_users.length} / $_maxUsers'),
                    subtitle: Text(
                      _users.length >= _maxUsers
                          ? 'تم الوصول للحد الأقصى المحدد في ترخيص SINDAR.'
                          : 'الحد مفروض مباشرة من LicensePolicy.maxUsers.',
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                for (final user in _users)
                  Card(
                    child: ListTile(
                      leading: CircleAvatar(
                        child: Icon(
                          user.isSystemAdmin
                              ? Icons.admin_panel_settings
                              : Icons.person_outline,
                        ),
                      ),
                      title: Text(
                        user.name,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      subtitle: Text('${user.role} • دخول: ${user.loginCode}'),
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

class _PermissionChip extends StatelessWidget {
  const _PermissionChip({
    required this.label,
    required this.selected,
    required this.onChanged,
  });

  final String label;
  final bool selected;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return FilterChip(
      label: Text(label),
      selected: selected,
      onSelected: onChanged,
    );
  }
}

class _PermissionDraft {
  _PermissionDraft({
    this.view = false,
    this.add = false,
    this.edit = false,
    this.delete = false,
    this.approve = false,
    this.print = false,
    this.profit = false,
  });

  bool view;
  bool add;
  bool edit;
  bool delete;
  bool approve;
  bool print;
  bool profit;
}

class LicenseActivationScreen extends StatefulWidget {
  const LicenseActivationScreen({super.key});

  @override
  State<LicenseActivationScreen> createState() => _LicenseActivationScreenState();
}

class _LicenseActivationScreenState extends State<LicenseActivationScreen> {
  final _token = TextEditingController();
  final _nameAr = TextEditingController();
  final _nameEn = TextEditingController();
  final _commercialRegistration = TextEditingController();
  final _sellerVat = TextEditingController();
  String _status = '';
  LicenseGrant? _grant;
  LicensePolicy _policy = LicensePolicy.lockedDefault;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _token.dispose();
    _nameAr.dispose();
    _nameEn.dispose();
    _commercialRegistration.dispose();
    _sellerVat.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final grant = await ErpRepository.instance.currentLicenseGrant();
    final policy = await SindarDatabase.instance.getLicensePolicy();
    final settings = await ErpRepository.instance.companySettings();
    if (!mounted) return;
    _nameAr.text = settings['company_name_ar'] ?? grant?.organizationName ?? '';
    _nameEn.text = settings['company_name_en'] ?? '';
    _commercialRegistration.text = settings['company_cr'] ?? '';
    _sellerVat.text =
        policy.taxModeEnabled ? (settings['seller_vat_number'] ?? '') : '';
    setState(() {
      _grant = grant;
      _policy = policy;
    });
  }

  Future<void> _saveCompany() async {
    final allowed = await SessionController.instance.can(
      'settings',
      action: 'edit',
    );
    if (!allowed) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ليست لديك صلاحية تعديل بيانات المنشأة')),
        );
      }
      return;
    }
    try {
      await ErpRepository.instance.saveCompanySettings(
        nameAr: _nameAr.text,
        nameEn: _nameEn.text,
        commercialRegistration: _commercialRegistration.text,
        sellerVatNumber: _policy.taxModeEnabled ? _sellerVat.text : null,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم حفظ بيانات المنشأة')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
    }
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
      await _load();
      if (!mounted) return;
      setState(() {
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
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      grant.organizationName,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text('رقم الترخيص: ${grant.licenseNumber}'),
                    Text(
                      'ينتهي: ${grant.expiresAt.toLocal().toString().split(' ').first}',
                    ),
                    Text(
                      'الحالة: ${grant.canOperate ? 'مفعل' : 'موقوف / منتهي'}',
                    ),
                    Text('الحد الأقصى للمستخدمين: ${grant.policy.maxUsers}'),
                    Text(
                      'الضريبة: ${grant.policy.taxModeEnabled ? 'مفعلة' : 'مقفلة'}',
                    ),
                    Text(
                      'الدولة/العملة: ${grant.policy.countryCode} / ${grant.policy.currencyCode} (${grant.policy.currencySymbol})',
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 12),
          const Text(
            'بيانات المنشأة المستخدمة في الفواتير والمستندات',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _nameAr,
            decoration: const InputDecoration(labelText: 'الاسم التجاري بالعربي'),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _nameEn,
            decoration: const InputDecoration(labelText: 'الاسم التجاري بالإنجليزي'),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _commercialRegistration,
            decoration: const InputDecoration(labelText: 'السجل التجاري'),
          ),
          if (_policy.taxModeEnabled) ...[
            const SizedBox(height: 8),
            TextField(
              controller: _sellerVat,
              keyboardType: TextInputType.number,
              maxLength: 15,
              decoration: const InputDecoration(
                labelText: 'الرقم الضريبي للبائع',
                helperText: 'يظهر فقط لأن المالك فعّل الوضع الضريبي',
              ),
            ),
          ] else
            const Card(
              child: ListTile(
                leading: Icon(Icons.lock_outline),
                title: Text('الرقم الضريبي مقفل من SINDAR Master Admin'),
                subtitle: Text('لن يُحفظ أو يظهر في الفواتير التجارية.'),
              ),
            ),
          const SizedBox(height: 8),
          FilledButton.tonalIcon(
            onPressed: _saveCompany,
            icon: const Icon(Icons.save_outlined),
            label: const Text('حفظ بيانات المنشأة'),
          ),
          const SizedBox(height: 20),
          const Text(
            'رقم الترخيص',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _token,
            maxLines: 1,
            textDirection: TextDirection.ltr,
            autocorrect: false,
            enableSuggestions: false,
            decoration: const InputDecoration(
              labelText: 'رقم الترخيص',
              hintText: 'S2...',
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
                  label: const Text('تفعيل الترخيص'),
                ),
              ),
            ],
          ),
          if (_status.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              _status,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
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
          TextField(
            controller: _code,
            decoration: const InputDecoration(labelText: 'رقم / اسم الدخول'),
          ),
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
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('إلغاء'),
        ),
        FilledButton(onPressed: _login, child: const Text('دخول')),
      ],
    );
  }
}
