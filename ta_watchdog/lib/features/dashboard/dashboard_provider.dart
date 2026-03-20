import 'package:dio/dio.dart';
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

class DeleteAccountHistoryRequest {
  final String accountNumber;
  final List<String> selectedDates;

  const DeleteAccountHistoryRequest({
    required this.accountNumber,
    required this.selectedDates,
  });

  Map<String, dynamic> toJson() => {'selected_dates': selectedDates};
}

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

final accountHistoryServiceProvider = Provider<AccountHistoryService>((ref) {
  return AccountHistoryService(ref);
});

class AccountHistoryService {
  final Ref ref;

  AccountHistoryService(this.ref);

  Future<void> deleteHistoryEntries({
    required String accountNumber,
    required List<String> selectedDates,
  }) async {
    final dio = ref.read(dioProvider);
    final payload = DeleteAccountHistoryRequest(
      accountNumber: accountNumber,
      selectedDates: selectedDates,
    ).toJson();

    try {
      await dio.post(
        '/api/dashboard/accounts/$accountNumber/history/delete',
        data: payload,
      );
    } on DioException catch (error) {
      final statusCode = error.response?.statusCode;
      if (statusCode != 404 && statusCode != 405) {
        throw Exception(_describeDeleteError(error));
      }

      try {
        await dio.delete(
          '/api/dashboard/accounts/$accountNumber/history',
          data: payload,
        );
      } on DioException catch (fallbackError) {
        throw Exception(_describeDeleteError(fallbackError));
      }
    }

    ref.invalidate(accountsProvider);
    ref.invalidate(dashboardSummaryProvider);
    ref.invalidate(chartDataProvider);
    ref.invalidate(accountHistoryProvider);
  }

  String _describeDeleteError(DioException error) {
    final responseData = error.response?.data;
    final detail = _extractErrorDetail(responseData);
    if (detail != null) {
      return detail;
    }

    return switch (error.response?.statusCode) {
      404 =>
        'Delete API not found on the server. Please update or redeploy the backend.',
      405 =>
        'Delete method is not allowed by the current server or proxy. Please update the backend deployment.',
      _ => error.message ?? 'Failed to delete the selected history entries.',
    };
  }

  String? _extractErrorDetail(dynamic responseData) {
    if (responseData is! Map) {
      return null;
    }

    final detail = responseData['detail'] ?? responseData['message'];
    if (detail is String && detail.trim().isNotEmpty) {
      return detail.trim();
    }

    return null;
  }
}
