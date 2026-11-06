import 'package:flutter/material.dart';
import 'package:sindar_core/sindar_core.dart';

import '../data/local/sindar_database.dart';
import '../theme/app_theme.dart';

class ChartOfAccountsScreen extends StatelessWidget {
  const ChartOfAccountsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('شجرة الحسابات')),
      body: FutureBuilder<List<Account>>(
        future: SindarDatabase.instance.getAccounts(),
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'تعذر فتح قاعدة البيانات المحلية: ${snapshot.error}',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          final accounts = snapshot.data ?? const <Account>[];
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: accounts.length,
            separatorBuilder: (_, __) => const SizedBox(height: 6),
            itemBuilder: (context, index) {
              final account = accounts[index];
              return Container(
                padding: EdgeInsetsDirectional.only(
                  start: 14.0 + ((account.level - 1) * 18),
                  end: 14,
                  top: 12,
                  bottom: 12,
                ),
                decoration: BoxDecoration(
                  color: account.level == 1 ? AppColors.navy2 : Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: account.level == 1
                        ? AppColors.navy2
                        : const Color(0xFFE1E7EE),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      account.isPosting
                          ? Icons.account_balance_wallet_outlined
                          : Icons.account_tree_outlined,
                      color: account.level == 1 ? AppColors.gold2 : AppColors.navy2,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        account.nameAr,
                        style: TextStyle(
                          color: account.level == 1 ? Colors.white : AppColors.text,
                          fontWeight: account.level <= 2
                              ? FontWeight.w800
                              : FontWeight.w600,
                        ),
                      ),
                    ),
                    Text(
                      account.code,
                      style: TextStyle(
                        color: account.level == 1
                            ? Colors.white70
                            : AppColors.muted,
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}
