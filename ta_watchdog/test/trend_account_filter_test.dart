import 'package:flutter_test/flutter_test.dart';
import 'package:ta_watchdog/features/dashboard/trend_account_filter.dart';

void main() {
  test('normalizeTrendAccountNumbers trims, de-duplicates, and sorts values', () {
    final normalized = normalizeTrendAccountNumbers([
      ' 222-222 ',
      '',
      '111-111',
      '222-222',
    ]);

    expect(normalized, ['111-111', '222-222']);
  });

  test('trendAccountMatchesQuery checks account number, alias, and company', () {
    final account = <String, dynamic>{
      'account_number': '123-456-789',
      'name': '급여 통장',
      'memo': '월급',
      'company': '신한은행',
      'type': '입출금',
    };

    expect(trendAccountMatchesQuery(account, '123456'), isTrue);
    expect(trendAccountMatchesQuery(account, '월급'), isTrue);
    expect(trendAccountMatchesQuery(account, '신한'), isTrue);
    expect(trendAccountMatchesQuery(account, '증권'), isFalse);
  });
}
