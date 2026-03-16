import 'package:flutter_riverpod/flutter_riverpod.dart';
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

final dashboardSummaryProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final dio = ref.watch(dioProvider);
  final response = await dio.get('/api/dashboard/summary');
  return response.data['data'];
});

final chartDataProvider = FutureProvider.autoDispose.family<List<dynamic>, String>((ref, type) async {
  final dio = ref.watch(dioProvider);
  final response = await dio.get('/api/dashboard/chart_native', queryParameters: {'chart_type': type});
  return response.data['data'];
});
final accountsProvider = FutureProvider<List<dynamic>>((ref) async {
  final dio = ref.watch(dioProvider);
  final response = await dio.get('/api/dashboard/accounts');
  if (response.data['status'] == 'error') {
    throw Exception(response.data['message']);
  }
  return (response.data['data'] as List?) ?? [];
});

final accountHistoryProvider =
    FutureProvider.autoDispose.family<List<dynamic>, AccountHistoryRequest>(
        (ref, request) async {
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
