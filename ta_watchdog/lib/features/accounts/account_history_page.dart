import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../dashboard/dashboard_provider.dart';

class AccountHistoryPage extends ConsumerStatefulWidget {
  final String accountNumber;
  final String accountName;

  const AccountHistoryPage({
    super.key,
    required this.accountNumber,
    required this.accountName,
  });

  @override
  ConsumerState<AccountHistoryPage> createState() => _AccountHistoryPageState();
}

class _AccountHistoryPageState extends ConsumerState<AccountHistoryPage> {
  int _limit = 50;
  bool _groupByDay = false;
  final _currency = NumberFormat.simpleCurrency(
    locale: 'ko_KR',
    decimalDigits: 0,
  );
  final _dateFormat = DateFormat('yyyy-MM-dd');
  final _timeFormat = DateFormat('HH:mm');

  @override
  Widget build(BuildContext context) {
    final accountsAsync = ref.watch(accountsProvider);
    final historyAsync = ref.watch(
      accountHistoryProvider(
        AccountHistoryRequest(
          accountNumber: widget.accountNumber,
          limit: _limit,
        ),
      ),
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.accountName),
        actions: [
          IconButton(
            icon: const Icon(Icons.copy),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: widget.accountNumber));
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Copied: ${widget.accountNumber}'),
                  duration: const Duration(seconds: 1),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
          ),
        ],
      ),
      body: historyAsync.when(
        data: (history) {
          if (history.isEmpty) {
            return const Center(child: Text('No history available'));
          }
          final displayHistory = _groupByDay
              ? _collapseToDailyLast(history)
              : history;
          return RefreshIndicator(
            onRefresh: () => ref.refresh(
              accountHistoryProvider(
                AccountHistoryRequest(
                  accountNumber: widget.accountNumber,
                  limit: _limit,
                ),
              ).future,
            ),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _buildSummaryCard(
                  history,
                  displayHistory,
                  _findListTodayDiff(accountsAsync.value),
                ),
                const SizedBox(height: 12),
                _buildControls(),
                const SizedBox(height: 12),
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: displayHistory.length,
                  separatorBuilder: (context, index) =>
                      const Divider(height: 16),
                  itemBuilder: (context, index) {
                    final entry = displayHistory[index];
                    final date = _parseDate(entry['date']?.toString() ?? '');
                    final balance = _asDouble(entry['balance']);
                    double? diff;
                    if (index + 1 < displayHistory.length) {
                      diff =
                          balance -
                          _asDouble(displayHistory[index + 1]['balance']);
                    }
                    return _buildHistoryRow(date, balance, diff);
                  },
                ),
              ],
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) => Center(child: Text('Error: $err')),
      ),
    );
  }

  Widget _buildControls() {
    return Row(
      children: [
        Expanded(
          child: SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 50, label: Text('50')),
              ButtonSegment(value: 200, label: Text('200')),
              ButtonSegment(value: 1000, label: Text('1000')),
            ],
            selected: {_limit},
            onSelectionChanged: (selection) {
              setState(() {
                _limit = selection.first;
              });
            },
          ),
        ),
        const SizedBox(width: 12),
        Row(
          children: [
            const Text('Days', style: TextStyle(color: Colors.blueGrey)),
            Switch(
              value: _groupByDay,
              onChanged: (value) {
                setState(() {
                  _groupByDay = value;
                });
              },
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSummaryCard(
    List<dynamic> history,
    List<dynamic> displayHistory,
    double? listTodayDiff,
  ) {
    final latest = displayHistory.first;
    final latestDate = _parseDate(latest['date']?.toString() ?? '');
    final latestBalance = _asDouble(latest['balance']);
    final delta = _groupByDay
        ? _calculateMonthlyChange(history)
        : _calculateTodayChange(history) ?? listTodayDiff;
    final deltaColor = (delta ?? 0) >= 0 ? Colors.teal : Colors.redAccent;
    final deltaText = delta == null
        ? '--'
        : '${delta >= 0 ? '+' : ''}${_currency.format(delta)}';
    final deltaLabel = _groupByDay ? 'Monthly Change' : "Today's Change";

    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Current Balance',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.blueGrey,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _currency.format(latestBalance),
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Last: ${_dateFormat.format(latestDate)} ${_timeFormat.format(latestDate)}',
                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  deltaLabel,
                  style: const TextStyle(fontSize: 12, color: Colors.blueGrey),
                ),
                const SizedBox(height: 6),
                Text(
                  deltaText,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: deltaColor,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  double? _findListTodayDiff(List<dynamic>? accounts) {
    if (accounts == null || accounts.isEmpty) return null;

    final target = _accountMatchKey(widget.accountNumber);
    if (target.isEmpty) return null;

    for (final account in accounts) {
      final number = _accountMatchKey(account['account_number']?.toString());
      if (number == target) {
        return _asNullableDouble(account['today_diff']);
      }
    }
    return null;
  }

  String _accountMatchKey(String? value) {
    final raw = (value ?? '').trim();
    if (raw.isEmpty) return '';

    final digits = raw.replaceAll(RegExp(r'\D'), '');
    if (digits.isNotEmpty) return digits;

    return raw.toLowerCase();
  }

  Widget _buildHistoryRow(DateTime date, double balance, double? diff) {
    final diffColor = (diff ?? 0) >= 0 ? Colors.teal : Colors.redAccent;
    final diffText = diff == null
        ? ''
        : '${diff >= 0 ? '+' : ''}${_currency.format(diff)}';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _dateFormat.format(date),
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
              Text(
                _timeFormat.format(date),
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                _currency.format(balance),
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                  color: Colors.blueGrey[900],
                ),
              ),
              if (diff != null)
                Text(
                  diffText,
                  style: TextStyle(fontSize: 11, color: diffColor),
                ),
            ],
          ),
        ],
      ),
    );
  }

  double _asDouble(dynamic value) {
    return _asNullableDouble(value) ?? 0.0;
  }

  double? _asNullableDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString());
  }

  DateTime _parseDate(String input) {
    final parsed = DateTime.tryParse(input);
    if (parsed != null) return parsed;
    try {
      return DateFormat('yyyy-MM-dd HH:mm:ss').parse(input);
    } catch (_) {
      return DateTime.now();
    }
  }

  double? _calculateTodayChange(List<dynamic> history) {
    if (history.isEmpty) return null;
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    double? todayLatest;
    double? todayEarliest;

    for (final entry in history) {
      final date = _parseDate(entry['date']?.toString() ?? '');
      final balance = _asDouble(entry['balance']);

      if (date.isBefore(todayStart)) {
        break;
      }

      todayLatest ??= balance;
      todayEarliest = balance;
    }

    if (todayLatest == null || todayEarliest == null) return null;
    return todayLatest - todayEarliest;
  }

  double? _calculateMonthlyChange(List<dynamic> history) {
    if (history.isEmpty) return null;
    final now = DateTime.now();
    final currentYear = now.year;
    final currentMonth = now.month;
    final prevMonth = currentMonth == 1 ? 12 : currentMonth - 1;
    final prevYear = currentMonth == 1 ? currentYear - 1 : currentYear;
    double? currentMonthLatest;
    double? prevMonthLatest;
    for (final entry in history) {
      final date = _parseDate(entry['date']?.toString() ?? '');
      final balance = _asDouble(entry['balance']);
      if (currentMonthLatest == null &&
          date.year == currentYear &&
          date.month == currentMonth) {
        currentMonthLatest = balance;
      }
      if (currentMonthLatest != null &&
          prevMonthLatest == null &&
          date.year == prevYear &&
          date.month == prevMonth) {
        prevMonthLatest = balance;
        break;
      }
    }
    if (currentMonthLatest == null || prevMonthLatest == null) return null;
    return currentMonthLatest - prevMonthLatest;
  }

  List<dynamic> _collapseToDailyLast(List<dynamic> history) {
    final Map<String, dynamic> latestByDate = {};
    final Map<String, DateTime> latestAt = {};
    for (final entry in history) {
      final date = _parseDate(entry['date']?.toString() ?? '');
      final key = DateFormat('yyyy-MM-dd').format(date);
      final current = latestAt[key];
      if (current == null || date.isAfter(current)) {
        latestAt[key] = date;
        latestByDate[key] = entry;
      }
    }
    final items = latestByDate.entries.toList()
      ..sort((a, b) => b.key.compareTo(a.key));
    return items.map((e) {
      final date = latestAt[e.key];
      if (date == null) return e.value;
      return {...e.value, 'date': date.toIso8601String()};
    }).toList();
  }
}
