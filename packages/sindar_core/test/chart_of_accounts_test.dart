import 'package:sindar_core/sindar_core.dart';
import 'package:test/test.dart';

void main() {
  test('standard chart contains five account classes and valid parents', () {
    expect(StandardChartOfAccounts.isBalancedStructure, isTrue);
    final roots = StandardChartOfAccounts.accounts
        .where((account) => account.parentCode == null)
        .map((account) => account.type)
        .toSet();

    expect(roots, containsAll(AccountType.values));
    expect(StandardChartOfAccounts.accounts.length, greaterThanOrEqualTo(40));
  });
}
