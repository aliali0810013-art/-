import 'dart:convert';

import '../data/local/sindar_database.dart';

class BusinessModuleConfig {
  const BusinessModuleConfig({
    this.sales = true,
    this.rentals = true,
    this.services = true,
    this.purchases = true,
    this.payroll = true,
  });

  final bool sales;
  final bool rentals;
  final bool services;
  final bool purchases;
  final bool payroll;

  BusinessModuleConfig copyWith({
    bool? sales,
    bool? rentals,
    bool? services,
    bool? purchases,
    bool? payroll,
  }) => BusinessModuleConfig(
    sales: sales ?? this.sales,
    rentals: rentals ?? this.rentals,
    services: services ?? this.services,
    purchases: purchases ?? this.purchases,
    payroll: payroll ?? this.payroll,
  );

  Map<String, Object?> toJson() => {
    'sales': sales,
    'rentals': rentals,
    'services': services,
    'purchases': purchases,
    'payroll': payroll,
  };

  factory BusinessModuleConfig.fromJson(Map<String, Object?> json) =>
      BusinessModuleConfig(
        sales: json['sales'] != false,
        rentals: json['rentals'] != false,
        services: json['services'] != false,
        purchases: json['purchases'] != false,
        payroll: json['payroll'] != false,
      );
}

class BusinessProfileService {
  const BusinessProfileService();

  static const _key = 'business_modules_v1';

  Future<BusinessModuleConfig> load() async {
    final raw = await SindarDatabase.instance.getSetting(_key);
    if (raw == null || raw.trim().isEmpty) {
      return const BusinessModuleConfig();
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return BusinessModuleConfig.fromJson(decoded);
      }
    } on FormatException {
      // Fall through to safe defaults.
    }
    return const BusinessModuleConfig();
  }

  Future<void> save(BusinessModuleConfig config) {
    return SindarDatabase.instance.saveSetting(_key, jsonEncode(config.toJson()));
  }
}
