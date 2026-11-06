abstract final class ArabicAmountInWords {
  static String spell(double amount, {String currencyName = 'ريال'}) {
    final rounded = (amount * 100).round();
    final whole = rounded ~/ 100;
    final fraction = rounded % 100;
    final wholeWords = _integer(whole);
    if (fraction == 0) return '$wholeWords $currencyName فقط';
    return '$wholeWords $currencyName و${_integer(fraction)} هللة فقط';
  }

  static String _integer(int value) {
    if (value == 0) return 'صفر';
    if (value < 0) return 'سالب ${_integer(-value)}';

    final parts = <String>[];
    final millions = value ~/ 1000000;
    final thousands = (value % 1000000) ~/ 1000;
    final remainder = value % 1000;

    if (millions > 0) {
      parts.add(_group(millions, 'مليون', 'مليونان', 'ملايين'));
    }
    if (thousands > 0) {
      parts.add(_group(thousands, 'ألف', 'ألفان', 'آلاف'));
    }
    if (remainder > 0) {
      parts.add(_under1000(remainder));
    }
    return parts.join(' و');
  }

  static String _group(int value, String one, String two, String plural) {
    if (value == 1) return one;
    if (value == 2) return two;
    if (value >= 3 && value <= 10) return '${_under1000(value)} $plural';
    return '${_under1000(value)} $one';
  }

  static String _under1000(int value) {
    final hundreds = value ~/ 100;
    final rest = value % 100;
    final parts = <String>[];

    const hundredWords = {
      1: 'مئة',
      2: 'مئتان',
      3: 'ثلاثمئة',
      4: 'أربعمئة',
      5: 'خمسمئة',
      6: 'ستمئة',
      7: 'سبعمئة',
      8: 'ثمانمئة',
      9: 'تسعمئة',
    };
    if (hundreds > 0) parts.add(hundredWords[hundreds]!);
    if (rest > 0) parts.add(_under100(rest));
    return parts.join(' و');
  }

  static String _under100(int value) {
    const direct = {
      1: 'واحد',
      2: 'اثنان',
      3: 'ثلاثة',
      4: 'أربعة',
      5: 'خمسة',
      6: 'ستة',
      7: 'سبعة',
      8: 'ثمانية',
      9: 'تسعة',
      10: 'عشرة',
      11: 'أحد عشر',
      12: 'اثنا عشر',
      13: 'ثلاثة عشر',
      14: 'أربعة عشر',
      15: 'خمسة عشر',
      16: 'ستة عشر',
      17: 'سبعة عشر',
      18: 'ثمانية عشر',
      19: 'تسعة عشر',
      20: 'عشرون',
      30: 'ثلاثون',
      40: 'أربعون',
      50: 'خمسون',
      60: 'ستون',
      70: 'سبعون',
      80: 'ثمانون',
      90: 'تسعون',
    };
    final directValue = direct[value];
    if (directValue != null) return directValue;
    final units = value % 10;
    final tens = value - units;
    return '${direct[units]} و${direct[tens]}';
  }
}
