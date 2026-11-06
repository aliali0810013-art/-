import 'package:flutter/foundation.dart';

import 'erp_repository.dart';
import 'operational_models.dart';

class SessionController {
  SessionController._();

  static final SessionController instance = SessionController._();

  final ValueNotifier<AppUserRecord?> currentUser =
      ValueNotifier<AppUserRecord?>(null);

  Future<void> initialize() async {
    await ErpRepository.instance.initialize();
    if (currentUser.value != null) return;
    final users = await ErpRepository.instance.listUsers();
    if (users.isNotEmpty) {
      currentUser.value = users.firstWhere(
        (user) => user.isSystemAdmin,
        orElse: () => users.first,
      );
    }
  }

  Future<bool> switchUser(String loginCode, String pin) async {
    final user = await ErpRepository.instance.authenticate(loginCode, pin);
    if (user == null) return false;
    currentUser.value = user;
    return true;
  }

  Future<bool> can(String module, {String action = 'view'}) async {
    final user = currentUser.value;
    if (user == null) return false;

    final grant = await ErpRepository.instance.currentLicenseGrant();
    if (grant != null && !grant.canOperate && module != 'settings') {
      return false;
    }

    return ErpRepository.instance.hasPermission(
      user,
      module,
      action: action,
    );
  }

  Future<bool> canOpen(String module) => can(module);
}
