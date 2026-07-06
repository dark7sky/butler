import 'package:flutter_test/flutter_test.dart';
import 'package:ta_watchdog/features/dashboard/dashboard_provider.dart';

void main() {
  test('ChartRequest normalizes account numbers for equality and hashing', () {
    final startAt = DateTime(2026, 7, 6, 9);
    final endAt = DateTime(2026, 7, 6, 18);

    final requestA = ChartRequest(
      chartType: 'day',
      startAt: startAt,
      endAt: endAt,
      diffMode: false,
      accountNumbers: ['222-222', '111-111', '222-222'],
    );
    final requestB = ChartRequest(
      chartType: 'day',
      startAt: startAt,
      endAt: endAt,
      diffMode: false,
      accountNumbers: ['111-111', '222-222'],
    );

    expect(requestA.accountNumbers, ['111-111', '222-222']);
    expect(requestA, requestB);
    expect(requestA.hashCode, requestB.hashCode);
  });
}
