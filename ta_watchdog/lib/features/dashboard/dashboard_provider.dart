import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import '../../core/api_client.dart';

class AccountHistoryRequest {
  final String accountNumber;
  final int limit;

  const AccountHistoryRequest({
    required this.accountNumber,
    required this.limit,
  });

  @override
  bool operator ==(Object other) {
    return other is AccountHistoryRequest &&
        other.accountNumber == accountNumber &&
        other.limit == limit;
  }

  @override
  int get hashCode => Object.hash(accountNumber, limit);
}

final homeTabProvider = StateProvider<int>((ref) => 0);
final trendChartTypeProvider = StateProvider<String>((ref) => 'day');
final selectedAccountProvider = StateProvider<AccountSelection?>((ref) => null);

class AccountSelection {
  final String accountNumber;
  final String accountName;

  const AccountSelection({
    required this.accountNumber,
    required this.accountName,
  });
}

final dashboardSummaryProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
      final dio = ref.watch(dioProvider);
      final response = await dio.get('/api/dashboard/summary');
      return response.data['data'];
    });

class ChartRequest {
  final String chartType;
  final DateTime startAt;
  final DateTime endAt;
  final bool diffMode;

  const ChartRequest({
    required this.chartType,
    required this.startAt,
    required this.endAt,
    required this.diffMode,
  });

  @override
  bool operator ==(Object other) {
    return other is ChartRequest &&
        other.chartType == chartType &&
        other.startAt == startAt &&
        other.endAt == endAt &&
        other.diffMode == diffMode;
  }

  @override
  int get hashCode => Object.hash(chartType, startAt, endAt, diffMode);
}

final chartDataProvider = FutureProvider.autoDispose
    .family<List<dynamic>, ChartRequest>((ref, request) async {
      final dio = ref.watch(dioProvider);
      final response = await dio.get(
        '/api/dashboard/chart_native',
        queryParameters: {
          'chart_type': request.chartType,
          'start_at': request.startAt.toIso8601String(),
          'end_at': request.endAt.toIso8601String(),
          'diff_mode': request.diffMode,
        },
      );

      if (response.data['status'] == 'error') {
        throw Exception(response.data['message']);
      }

      return (response.data['data'] as List?) ?? [];
    });
final accountsProvider = FutureProvider<List<dynamic>>((ref) async {
  final dio = ref.watch(dioProvider);
  final response = await dio.get('/api/dashboard/accounts');
  if (response.data['status'] == 'error') {
    throw Exception(response.data['message']);
  }
  return (response.data['data'] as List?) ?? [];
});

final accountHistoryProvider = FutureProvider.autoDispose
    .family<List<dynamic>, AccountHistoryRequest>((ref, request) async {
      final dio = ref.watch(dioProvider);
      final response = await dio.get(
        '/api/dashboard/accounts/${request.accountNumber}/history',
        queryParameters: {'limit': request.limit},
      );
      if (response.data['status'] == 'error') {
        throw Exception(response.data['message']);
      }
      return (response.data['data'] as List?) ?? [];
    });
