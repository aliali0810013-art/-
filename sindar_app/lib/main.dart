import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'src/screens/license_gate_screen.dart';
import 'src/services/free_google_drive_sync_service.dart';
import 'src/theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setEnabledSystemUIMode(
    SystemUiMode.manual,
    overlays: SystemUiOverlay.values,
  );
  await CloudSyncScheduler.initialize();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: AppColors.navy,
      statusBarIconBrightness: Brightness.light,
      statusBarBrightness: Brightness.dark,
      systemNavigationBarColor: AppColors.navy,
      systemNavigationBarIconBrightness: Brightness.light,
      systemNavigationBarDividerColor: AppColors.navy,
    ),
  );
  runApp(const SindarApp());
}

class SindarApp extends StatelessWidget {
  const SindarApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'سندار',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      locale: const Locale('ar'),
      builder: (context, child) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: SafeArea(
            top: true,
            bottom: true,
            left: false,
            right: false,
            child: child ?? const SizedBox.shrink(),
          ),
        );
      },
      home: const LicenseGateScreen(),
    );
  }
}
