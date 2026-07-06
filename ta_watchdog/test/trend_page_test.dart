import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ta_watchdog/features/dashboard/dashboard_provider.dart';
import 'package:ta_watchdog/features/dashboard/trend_account_filter.dart';
import 'package:ta_watchdog/features/dashboard/trend_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const accounts = [
    <String, dynamic>{
      'account_number': '222-222',
      'name': '급여통장',
      'memo': '월급',
      'company': '신한은행',
      'type': '입출금',
    },
    <String, dynamic>{
      'account_number': '111-111',
      'name': '투자계좌',
      'memo': '증권',
      'company': '미래에셋증권',
      'type': '증권',
    },
  ];

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Widget buildTrendPage({
    void Function(ChartRequest request)? onChartRequest,
  }) {
    return ProviderScope(
      overrides: [
        accountsProvider.overrideWith((ref) async => accounts),
        chartDataProvider.overrideWith((ref, request) {
          onChartRequest?.call(request);
          return <dynamic>[];
        }),
      ],
      child: const MaterialApp(home: TrendPage()),
    );
  }

  testWidgets('restores the saved Trend account filter on load', (tester) async {
    SharedPreferences.setMockInitialValues({
      trendAccountFilterPreferenceKey: ['222-222'],
    });
    ChartRequest? latestRequest;

    await tester.pumpWidget(
      buildTrendPage(onChartRequest: (request) => latestRequest = request),
    );
    await tester.pumpAndSettle();

    expect(find.text('월급'), findsOneWidget);
    expect(latestRequest?.accountNumbers, ['222-222']);
  });

  testWidgets('shows an empty state when no account matches the search query', (
    tester,
  ) async {
    await tester.pumpWidget(buildTrendPage());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(trendAccountFilterTriggerKey));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(trendAccountFilterSearchFieldKey), '없는계좌');
    await tester.pumpAndSettle();

    expect(find.text('검색 결과가 없습니다.'), findsOneWidget);
  });

  testWidgets('applies a filtered selection and persists it', (tester) async {
    await tester.pumpWidget(buildTrendPage());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(trendAccountFilterTriggerKey));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(trendAccountFilterSearchFieldKey), '미래');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(CheckboxListTile, '증권'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(trendAccountFilterApplyButtonKey));
    await tester.pumpAndSettle();

    final preferences = await SharedPreferences.getInstance();

    expect(find.text('증권'), findsOneWidget);
    expect(
      preferences.getStringList(trendAccountFilterPreferenceKey),
      ['111-111'],
    );
  });

  testWidgets('keeps the previous selection when the sheet is cancelled', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      trendAccountFilterPreferenceKey: ['222-222'],
    });

    await tester.pumpWidget(buildTrendPage());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(trendAccountFilterTriggerKey));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(trendAccountFilterSearchFieldKey), '미래');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(CheckboxListTile, '증권'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('취소'));
    await tester.pumpAndSettle();

    final preferences = await SharedPreferences.getInstance();

    expect(find.text('월급'), findsOneWidget);
    expect(
      preferences.getStringList(trendAccountFilterPreferenceKey),
      ['222-222'],
    );
  });
}
