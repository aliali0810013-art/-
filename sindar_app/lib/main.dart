import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'src/theme/app_theme.dart';
import 'src/screens/home_dashboard_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: AppColors.navy,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: AppColors.navy,
      systemNavigationBarIconBrightness: Brightness.light,
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
          child: child ?? const SizedBox.shrink(),
        );
      },
      home: const HomeDashboardScreen(),
    );
  }
}
