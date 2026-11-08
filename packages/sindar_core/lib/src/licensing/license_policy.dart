class LicensePolicy {
  const LicensePolicy({
    required this.customerId,
    required this.isTaxEnabled,
    required this.countryCode,
    required this.currencyCode,
    required this.currencySymbol,
    required this.maxUsers,
  });

  final String customerId;
  final bool isTaxEnabled;
  final String countryCode;
  final String currencyCode;
  final String currencySymbol;
  final int maxUsers;

  bool get isYemen => countryCode == 'YE';
  bool get isSaudiArabia => countryCode == 'SA';

  /// Yemen workspace is always non-tax in SINDAR UI. Other countries honor
  /// the licensed tax flag; Saudi tax mode exposes ZATCA-oriented invoices.
  bool get taxModeEnabled => isTaxEnabled && !isYemen;

  String get currencyNameAr => switch (currencyCode) {
        'SAR' => 'ريال سعودي',
        'YER' => 'ريال يمني',
        'USD' => 'دولار أمريكي',
        _ => currencyCode,
      };

  String get moneyLabelAr => currencySymbol.trim().isEmpty
      ? currencyNameAr
      : '$currencyNameAr ($currencySymbol)';

  static const lockedDefault = LicensePolicy(
    customerId: 'local',
    isTaxEnabled: false,
    countryCode: 'YE',
    currencyCode: 'YER',
    currencySymbol: 'ر.ي',
    maxUsers: 1,
  );

  LicensePolicy copyWith({
    String? customerId,
    bool? isTaxEnabled,
    String? countryCode,
    String? currencyCode,
    String? currencySymbol,
    int? maxUsers,
  }) {
    return LicensePolicy(
      customerId: customerId ?? this.customerId,
      isTaxEnabled: isTaxEnabled ?? this.isTaxEnabled,
      countryCode: countryCode ?? this.countryCode,
      currencyCode: currencyCode ?? this.currencyCode,
      currencySymbol: currencySymbol ?? this.currencySymbol,
      maxUsers: maxUsers ?? this.maxUsers,
    );
  }

  Map<String, Object?> toJson() => {
        'customerId': customerId,
        'isTaxEnabled': isTaxEnabled,
        'countryCode': countryCode,
        'currencyCode': currencyCode,
        'currencySymbol': currencySymbol,
        'maxUsers': maxUsers,
      };

  factory LicensePolicy.fromJson(Map<String, Object?> json) {
    final maxUsers = (json['maxUsers'] as num?)?.toInt() ?? 1;
    if (maxUsers < 1) {
      throw const FormatException('maxUsers must be at least 1');
    }
    return LicensePolicy(
      customerId: (json['customerId'] as String?)?.trim().isNotEmpty == true
          ? (json['customerId']! as String)
          : 'local',
      isTaxEnabled: json['isTaxEnabled'] == true,
      countryCode: (json['countryCode'] as String? ?? 'YE').toUpperCase(),
      currencyCode: (json['currencyCode'] as String? ?? 'YER').toUpperCase(),
      currencySymbol: json['currencySymbol'] as String? ?? 'ر.ي',
      maxUsers: maxUsers,
    );
  }
}
