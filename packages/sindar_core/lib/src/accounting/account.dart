enum AccountType {
  asset,
  liability,
  equity,
  revenue,
  expense,
}

enum AccountNature {
  debit,
  credit,
}

class Account {
  const Account({
    required this.code,
    required this.nameAr,
    required this.type,
    required this.level,
    required this.isPosting,
    this.parentCode,
  });

  final String code;
  final String nameAr;
  final AccountType type;
  final int level;
  final bool isPosting;
  final String? parentCode;

  AccountNature get nature => switch (type) {
        AccountType.asset || AccountType.expense => AccountNature.debit,
        AccountType.liability || AccountType.equity || AccountType.revenue => AccountNature.credit,
      };

  Map<String, Object?> toMap() => {
        'code': code,
        'name_ar': nameAr,
        'type': type.name,
        'level': level,
        'is_posting': isPosting ? 1 : 0,
        'parent_code': parentCode,
      };

  factory Account.fromMap(Map<String, Object?> map) {
    return Account(
      code: map['code']! as String,
      nameAr: map['name_ar']! as String,
      type: AccountType.values.byName(map['type']! as String),
      level: map['level']! as int,
      isPosting: (map['is_posting']! as int) == 1,
      parentCode: map['parent_code'] as String?,
    );
  }
}
