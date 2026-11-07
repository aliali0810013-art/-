import 'package:flutter/material.dart';
import 'package:sindar_core/sindar_core.dart';

import '../services/erp_repository.dart';
import '../services/free_google_drive_sync_service.dart';
import '../services/session_controller.dart';
import '../theme/app_theme.dart';
import 'home_dashboard_screen.dart';

class LicenseGateScreen extends StatefulWidget {
  const LicenseGateScreen({super.key});

  @override
  State<LicenseGateScreen> createState() => _LicenseGateScreenState();
}

class _LicenseGateScreenState extends State<LicenseGateScreen> {
  final _licenseNumber = TextEditingController();
  bool _checking = true;
  bool _activating = false;
  bool _unlocked = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    _checkExistingLicense();
  }

  @override
  void dispose() {
    _licenseNumber.dispose();
    super.dispose();
  }

  Future<void> _checkExistingLicense() async {
    try {
      final grant = await ErpRepository.instance.currentLicenseGrant();
      if (grant?.canOperate == true) {
        await _unlock();
        return;
      }
      if (!mounted) return;
      setState(() {
        _checking = false;
        if (grant != null) {
          _message = grant.isExpired
              ? 'انتهت صلاحية الترخيص. أدخل رقم ترخيص مجدد.'
              : 'الترخيص موقوف. أدخل رقم ترخيص فعال.';
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _checking = false);
    }
  }

  Future<void> _unlock() async {
    await ErpRepository.instance.initialize();
    await SessionController.instance.initialize();
    await CloudSyncScheduler.restoreRegistration();
    if (!mounted) return;
    setState(() {
      _checking = false;
      _unlocked = true;
      _message = null;
    });
  }

  Future<void> _activate() async {
    if (_activating) return;
    final code = _licenseNumber.text.replaceAll(RegExp(r'\s+'), '');
    if (code.isEmpty) {
      setState(() => _message = 'أدخل رقم الترخيص.');
      return;
    }

    setState(() {
      _activating = true;
      _message = null;
    });
    try {
      await ErpRepository.instance.applyLicenseToken(code);
      await _unlock();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _message = error
            .toString()
            .replaceFirst('FormatException: ', '')
            .replaceFirst('Exception: ', '');
      });
    } finally {
      if (mounted) setState(() => _activating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_unlocked) {
      return const HomeDashboardScreen();
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 430),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 230,
                    height: 122,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: AppColors.gold.withValues(alpha: .55),
                      ),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x160A2540),
                          blurRadius: 24,
                          offset: Offset(0, 10),
                        ),
                      ],
                    ),
                    child: Image.asset(
                      'assets/branding/sindar_brand_full.webp',
                      fit: BoxFit.contain,
                      filterQuality: FilterQuality.high,
                    ),
                  ),
                  const SizedBox(height: 26),
                  const Text(
                    'تفعيل سندار',
                    style: TextStyle(
                      color: AppColors.navy,
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 7),
                  const Text(
                    'أدخل رقم الترخيص الصادر من إدارة سندار لفتح النظام.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppColors.muted,
                      fontSize: 13,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 22),
                  if (_checking)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: CircularProgressIndicator(),
                    )
                  else ...[
                    TextField(
                      key: const ValueKey<String>('license-number-field'),
                      controller: _licenseNumber,
                      enabled: !_activating,
                      textDirection: TextDirection.ltr,
                      textAlign: TextAlign.center,
                      autocorrect: false,
                      enableSuggestions: false,
                      maxLines: 1,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        letterSpacing: .2,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'رقم الترخيص',
                        hintText: 'S2...',
                        prefixIcon: Icon(Icons.key_rounded),
                      ),
                      onSubmitted: (_) => _activate(),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: FilledButton.icon(
                        key: const ValueKey<String>('activate-license-button'),
                        onPressed: _activating ? null : _activate,
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.navy,
                          foregroundColor: Colors.white,
                        ),
                        icon: _activating
                            ? const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.lock_open_rounded),
                        label: const Text(
                          'فتح النظام',
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 15,
                          ),
                        ),
                      ),
                    ),
                  ],
                  if (_message != null) ...[
                    const SizedBox(height: 14),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFEEEE),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Text(
                        _message!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Color(0xFFB3261E),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 18),
                  const Text(
                    'لا يمكن الوصول إلى البيانات أو الأقسام قبل تفعيل الترخيص.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppColors.muted,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
