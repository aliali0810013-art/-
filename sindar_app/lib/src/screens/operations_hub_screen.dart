import 'package:flutter/material.dart';
import 'package:sindar_core/sindar_core.dart';

import '../services/business_profile_service.dart';
import '../theme/app_theme.dart';
import 'assets_payroll_reports_screens.dart';
import 'document_studio_screen.dart';
import 'equipment_rental_screen.dart';
import 'journal_voucher_screens.dart';
import 'party_inventory_screens.dart';
import 'rental_operations_screen.dart';
import 'sales_purchase_screens.dart';
import 'service_invoice_screen.dart';

class OperationsHubScreen extends StatefulWidget {
  const OperationsHubScreen({super.key});

  @override
  State<OperationsHubScreen> createState() => _OperationsHubScreenState();
}

class _OperationsHubScreenState extends State<OperationsHubScreen> {
  BusinessModuleConfig _config = const BusinessModuleConfig();
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final config = await const BusinessProfileService().load();
    if (!mounted) return;
    setState(() {
      _config = config;
      _loading = false;
    });
  }

  Future<void> _open(Widget page) async {
    await Navigator.push(context, MaterialPageRoute<void>(builder: (_) => page));
    if (mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('مركز العمليات')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text('ماذا تريد أن تنفذ؟',
                          style: TextStyle(
                            fontSize: 21, fontWeight: FontWeight.w900)),
                        SizedBox(height: 5),
                        Text(
                          'اختر نوع العملية فقط. سِندار يفتح الحقول والقيد المناسب '
                          'بدون خلط المخزون بالمعدات أو الخدمات.',
                          style: TextStyle(color: AppColors.muted),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                GridView.count(
                  crossAxisCount: MediaQuery.sizeOf(context).width > 720 ? 3 : 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: 1.35,
                  children: [
                    if (_config.sales)
                      _OperationCard(
                        icon: Icons.point_of_sale_rounded,
                        title: 'بيع',
                        subtitle: 'صنف • كمية • سعر • مخزون',
                        onTap: () => _open(const SalesScreen()),
                      ),
                    if (_config.rentals)
                      _OperationCard(
                        icon: Icons.handyman_rounded,
                        title: 'تأجير',
                        subtitle: 'معدة • مدة • سعر اتفاق • عقد',
                        onTap: () => _open(const RentalOperationsScreen()),
                      ),
                    if (_config.services)
                      _OperationCard(
                        icon: Icons.design_services_rounded,
                        title: 'خدمة',
                        subtitle: 'خدمة بدون مخزون • فاتورة محاسبية',
                        onTap: () => _open(const ServiceInvoiceScreen()),
                      ),
                    if (_config.purchases)
                      _OperationCard(
                        icon: Icons.shopping_cart_checkout_rounded,
                        title: 'شراء',
                        subtitle: 'مورد • أصناف • مخزون',
                        onTap: () => _open(const PurchaseScreen()),
                      ),
                  ],
                ),
                const SizedBox(height: 20),
                const Text('اختصارات المستندات',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                const SizedBox(height: 8),
                _ShortcutTile(
                  icon: Icons.payments_outlined,
                  title: 'سند قبض',
                  subtitle: 'قبض عام أو تسوية ذمة عميل',
                  onTap: () => _open(const VoucherScreen(receipt: true)),
                ),
                _ShortcutTile(
                  icon: Icons.outbox_outlined,
                  title: 'سند صرف',
                  subtitle: 'سداد أو مصروف عام',
                  onTap: () => _open(const VoucherScreen(receipt: false)),
                ),
                _ShortcutTile(
                  icon: Icons.request_quote_outlined,
                  title: 'مطالبة مالية',
                  subtitle: 'إنشاء مطالبة وPDF من نفس هوية سِندار',
                  onTap: () => _open(const DocumentStudioScreen(
                    initialType: DocumentType.financialClaim)),
                ),
                _ShortcutTile(
                  icon: Icons.mail_outline_rounded,
                  title: 'خطاب رسمي',
                  subtitle: 'خطاب جاهز للطباعة والمشاركة',
                  onTap: () => _open(const DocumentStudioScreen(
                    initialType: DocumentType.officialLetter)),
                ),
                const SizedBox(height: 20),
                const Text('البيانات المرتبطة',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ActionChip(
                      avatar: const Icon(Icons.groups_outlined, size: 18),
                      label: const Text('العملاء'),
                      onPressed: () => _open(const PartiesScreen(type: 'customer')),
                    ),
                    if (_config.sales)
                      ActionChip(
                        avatar: const Icon(Icons.inventory_2_outlined, size: 18),
                        label: const Text('الأصناف'),
                        onPressed: () => _open(const InventoryScreen()),
                      ),
                    if (_config.rentals)
                      ActionChip(
                        avatar: const Icon(Icons.precision_manufacturing_outlined,
                          size: 18),
                        label: const Text('المعدات'),
                        onPressed: () => _open(const EquipmentRentalScreen()),
                      ),
                    if (_config.payroll)
                      ActionChip(
                        avatar: const Icon(Icons.badge_outlined, size: 18),
                        label: const Text('الموظفون'),
                        onPressed: () => _open(const PayrollScreen()),
                      ),
                  ],
                ),
                const SizedBox(height: 30),
              ],
            ),
    );
  }
}

class _OperationCard extends StatelessWidget {
  const _OperationCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white,
    borderRadius: BorderRadius.circular(20),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppColors.gold.withValues(alpha: .16),
                borderRadius: BorderRadius.circular(13),
              ),
              child: Icon(icon, color: AppColors.navy2),
            ),
            const SizedBox(height: 8),
            Text(title,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
            const SizedBox(height: 2),
            Text(subtitle,
              maxLines: 2,
              style: const TextStyle(color: AppColors.muted, fontSize: 12)),
          ],
        ),
      ),
    ),
  );
}

class _ShortcutTile extends StatelessWidget {
  const _ShortcutTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(
      leading: CircleAvatar(
        backgroundColor: AppColors.sky,
        child: Icon(icon, color: AppColors.navy2)),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_left_rounded),
      onTap: onTap,
    ),
  );
}
