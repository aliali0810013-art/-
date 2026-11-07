import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/free_google_drive_sync_service.dart';
import '../theme/app_theme.dart';

class CloudSyncScreen extends StatefulWidget {
  const CloudSyncScreen({super.key});

  @override
  State<CloudSyncScreen> createState() => _CloudSyncScreenState();
}

class _CloudSyncScreenState extends State<CloudSyncScreen> {
  CloudSyncStatus? _status;
  bool _loading = true;
  bool _working = false;

  @override
  void initState() {
    super.initState();
    _refresh(refreshRemote: true);
  }

  Future<void> _refresh({bool refreshRemote = false}) async {
    final status = await FreeGoogleDriveSyncService.instance.status(
      refreshRemote: refreshRemote,
    );
    if (!mounted) return;
    setState(() {
      _status = status;
      _loading = false;
    });
  }

  Future<void> _connect() async {
    await _run(() async {
      final account = await FreeGoogleDriveSyncService.instance.connect();
      if (!mounted) return;
      if (account != null) {
        _message('تم ربط Google Drive بحساب ${account.email}');
      }
      await _refresh(refreshRemote: true);
    });
  }

  Future<void> _disconnect() async {
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('فصل Google Drive'),
        content: const Text(
          'سيتم إيقاف الوصول إلى النسخ السحابية حتى تربط الحساب مرة أخرى. '
          'النسخة الموجودة في Drive لن تُحذف.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('فصل الحساب'),
          ),
        ],
      ),
    );
    if (accepted != true) return;

    await _run(() async {
      await FreeGoogleDriveSyncService.instance.disconnect();
      await _refresh();
      _message('تم فصل حساب Google Drive.');
    });
  }

  Future<void> _backup() async {
    await _run(() async {
      final result = await FreeGoogleDriveSyncService.instance.backupNow();
      if (!mounted) return;
      _message(
        'تم إنشاء ورفع النسخة المشفرة بنجاح '
        '(${_formatBytes(result.size)}).',
      );
      await _refresh(refreshRemote: true);
    });
  }

  Future<void> _restore() async {
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(
          Icons.warning_amber_rounded,
          color: Colors.orange,
          size: 36,
        ),
        title: const Text('استعادة النسخة الاحتياطية'),
        content: const Text(
          'سيتم استبدال قاعدة البيانات والمرفقات الحالية بأحدث نسخة مشفرة '
          'في Google Drive. يحتفظ سندار بنسخة Rollback محلية أثناء العملية '
          'ويعيدها تلقائياً إذا فشل فحص السلامة.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('استعادة الآن'),
          ),
        ],
      ),
    );
    if (accepted != true) return;

    await _run(() async {
      final result =
          await FreeGoogleDriveSyncService.instance.restoreLatest();
      if (!mounted) return;
      await _refresh(refreshRemote: true);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          icon: const Icon(
            Icons.verified_rounded,
            color: AppColors.green,
            size: 40,
          ),
          title: const Text('تمت الاستعادة بنجاح'),
          content: Text(
            'تمت استعادة قاعدة البيانات و'
            '${result.attachmentCount} مرفقات. '
            'تاريخ النسخة: ${_formatDate(result.backupCreatedAt)}. '
            'يفضل إعادة فتح التطبيق بعد الاستعادة لتحديث كل الشاشات المفتوحة.',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('تم'),
            ),
          ],
        ),
      );
    });
  }

  Future<void> _changeSchedule(CloudSyncSchedule schedule) async {
    await _run(() async {
      await FreeGoogleDriveSyncService.instance.setSchedule(schedule);
      await _refresh();
      _message(
        schedule == CloudSyncSchedule.manual
            ? 'تم إيقاف النسخ التلقائي؛ النسخ اليدوي ما زال متاحاً.'
            : 'تم حفظ الجدولة: ${schedule.titleAr}.',
      );
    });
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_working) return;
    setState(() => _working = true);
    try {
      await action();
    } catch (error) {
      if (!mounted) return;
      _message(
        error.toString().replaceFirst('FormatException: ', ''),
        error: true,
      );
      await _refresh();
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  void _message(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? Colors.red.shade700 : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final status = _status;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('النسخ الاحتياطي والمزامنة'),
        actions: [
          IconButton(
            tooltip: 'تحديث الحالة',
            onPressed: _working
                ? null
                : () => _refresh(refreshRemote: true),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _loading || status == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _ConnectionCard(
                  status: status,
                  busy: _working,
                  onConnect: _connect,
                  onDisconnect: _disconnect,
                ),
                const SizedBox(height: 12),
                _BackupStatusCard(status: status),
                const SizedBox(height: 12),
                _ActionPanel(
                  connected: status.connected,
                  busy: _working,
                  onBackup: _backup,
                  onRestore: _restore,
                ),
                const SizedBox(height: 12),
                _ScheduleCard(
                  value: status.schedule,
                  busy: _working,
                  onChanged: _changeSchedule,
                ),
                if (status.lastError != null) ...[
                  const SizedBox(height: 12),
                  Card(
                    color: const Color(0xFFFFEEEE),
                    child: ListTile(
                      leading: const Icon(
                        Icons.error_outline_rounded,
                        color: Colors.red,
                      ),
                      title: const Text(
                        'آخر خطأ مزامنة',
                        style: TextStyle(fontWeight: FontWeight.w900),
                      ),
                      subtitle: Text(status.lastError!),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                const _SecurityCard(),
              ],
            ),
    );
  }

  static String _formatDate(DateTime? value) {
    if (value == null) return 'لا توجد';
    return DateFormat('yyyy-MM-dd  HH:mm', 'en_US')
        .format(value.toLocal());
  }

  static String _formatBytes(int? bytes) {
    if (bytes == null) return 'غير معروف';
    if (bytes < 1024) return '$bytes B';
    final kb = bytes / 1024;
    if (kb < 1024) return '${kb.toStringAsFixed(1)} KB';
    final mb = kb / 1024;
    return '${mb.toStringAsFixed(1)} MB';
  }
}

class _ConnectionCard extends StatelessWidget {
  const _ConnectionCard({
    required this.status,
    required this.busy,
    required this.onConnect,
    required this.onDisconnect,
  });

  final CloudSyncStatus status;
  final bool busy;
  final VoidCallback onConnect;
  final VoidCallback onDisconnect;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.navy,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(
            color: Color(0x240A2540),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: status.connected
                      ? AppColors.gold.withValues(alpha: .18)
                      : Colors.white.withValues(alpha: .08),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  status.connected
                      ? Icons.cloud_done_rounded
                      : Icons.cloud_off_rounded,
                  color: status.connected ? AppColors.gold : Colors.white70,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      status.connected
                          ? 'Google Drive متصل'
                          : 'Google Drive غير متصل',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    if (status.accountEmail != null)
                      Text(
                        status.accountEmail!,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                        ),
                      ),
                  ],
                ),
              ),
              FilledButton.tonal(
                onPressed: busy
                    ? null
                    : (status.connected ? onDisconnect : onConnect),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.gold,
                  foregroundColor: AppColors.navy,
                ),
                child: Text(status.connected ? 'فصل' : 'ربط'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            'يحفظ سندار النسخة داخل App Data المخفي في Drive. '
            'لا يستطيع التطبيق الوصول إلى بقية ملفات العميل.',
            style: TextStyle(
              color: Colors.white70,
              height: 1.5,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _BackupStatusCard extends StatelessWidget {
  const _BackupStatusCard({required this.status});

  final CloudSyncStatus status;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          children: [
            const Row(
              children: [
                Icon(
                  Icons.history_rounded,
                  color: AppColors.gold,
                ),
                SizedBox(width: 8),
                Text(
                  'حالة النسخ',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _StatusLine(
              label: 'آخر نسخة من هذا الجهاز',
              value: _CloudSyncScreenState._formatDate(
                status.lastBackupAt,
              ),
            ),
            _StatusLine(
              label: 'آخر نسخة في Drive',
              value: _CloudSyncScreenState._formatDate(
                status.remoteBackupAt,
              ),
            ),
            _StatusLine(
              label: 'حجم النسخة السحابية',
              value: _CloudSyncScreenState._formatBytes(
                status.remoteBackupSize,
              ),
            ),
            _StatusLine(
              label: 'آخر استعادة',
              value: _CloudSyncScreenState._formatDate(
                status.lastRestoreAt,
              ),
              last: true,
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusLine extends StatelessWidget {
  const _StatusLine({
    required this.label,
    required this.value,
    this.last = false,
  });

  final String label;
  final String value;
  final bool last;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 9),
      decoration: BoxDecoration(
        border: last
            ? null
            : const Border(
                bottom: BorderSide(color: Color(0xFFE8ECF1)),
              ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(color: AppColors.muted),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

class _ActionPanel extends StatelessWidget {
  const _ActionPanel({
    required this.connected,
    required this.busy,
    required this.onBackup,
    required this.onRestore,
  });

  final bool connected;
  final bool busy;
  final VoidCallback onBackup;
  final VoidCallback onRestore;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: SizedBox(
            height: 58,
            child: FilledButton.icon(
              onPressed: busy || !connected ? null : onBackup,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.navy2,
              ),
              icon: busy
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.cloud_upload_outlined),
              label: const Text(
                'نسخ احتياطي الآن',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: SizedBox(
            height: 58,
            child: OutlinedButton.icon(
              onPressed: busy || !connected ? null : onRestore,
              icon: const Icon(Icons.restore_rounded),
              label: const Text(
                'استعادة النسخة',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ScheduleCard extends StatelessWidget {
  const _ScheduleCard({
    required this.value,
    required this.busy,
    required this.onChanged,
  });

  final CloudSyncSchedule value;
  final bool busy;
  final ValueChanged<CloudSyncSchedule> onChanged;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(
                  Icons.schedule_rounded,
                  color: AppColors.navy2,
                ),
                SizedBox(width: 8),
                Text(
                  'جدولة النسخ التلقائي',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'يستخدم Android WorkManager وينفذ النسخ عند توفر الإنترنت. '
              'التوقيت تقريبي لأن النظام يوازن البطارية والاتصال.',
              style: TextStyle(
                color: AppColors.muted,
                height: 1.45,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<CloudSyncSchedule>(
              initialValue: value,
              decoration: const InputDecoration(
                labelText: 'الجدولة',
              ),
              items: [
                for (final item in CloudSyncSchedule.values)
                  DropdownMenuItem(
                    value: item,
                    child: Text(item.titleAr),
                  ),
              ],
              onChanged: busy
                  ? null
                  : (schedule) {
                      if (schedule != null) onChanged(schedule);
                    },
            ),
          ],
        ),
      ),
    );
  }
}

class _SecurityCard extends StatelessWidget {
  const _SecurityCard();

  @override
  Widget build(BuildContext context) {
    return const Card(
      color: Color(0xFFF7F2E6),
      child: Padding(
        padding: EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.enhanced_encryption_outlined,
              color: AppColors.gold,
            ),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'الحماية: قاعدة SQLite والمرفقات تُضغط ثم تُشفّر AES‑256‑GCM. '
                'مفتاح الاستعادة مشتق من هوية الترخيص المفعّل؛ لذلك على الجوال الجديد '
                'فعّل نفس ترخيص سندار ثم اضغط استعادة النسخة.',
                style: TextStyle(
                  height: 1.55,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
