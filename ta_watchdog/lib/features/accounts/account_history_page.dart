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
  bool _selectionMode = false;
  bool _isDeleting = false;
  final Set<String> _selectedHistoryIds = <String>{};
  final _currency = NumberFormat.simpleCurrency(
    locale: 'ko_KR',
    decimalDigits: 0,
  );
  final _dateFormat = DateFormat('yyyy-MM-dd');
  final _timeFormat = DateFormat('HH:mm');

  AccountHistoryRequest get _request =>
      AccountHistoryRequest(accountNumber: widget.accountNumber, limit: _limit);

  @override
  Widget build(BuildContext context) {
    final accountsAsync = ref.watch(accountsProvider);
    final historyAsync = ref.watch(accountHistoryProvider(_request));
    final loadedHistory = historyAsync.asData?.value;

    return Scaffold(
      appBar: AppBar(
        title: _selectionMode
            ? Text('${_selectedHistoryIds.length} selected')
            : Text(widget.accountName),
        leading: _selectionMode
            ? IconButton(
                icon: const Icon(Icons.close),
                onPressed: _clearSelection,
              )
            : null,
        actions: [
          if (_selectionMode) ...[
            IconButton(
              icon: const Icon(Icons.select_all),
              tooltip: 'Select all',
              onPressed: loadedHistory == null
                  ? null
                  : () => _selectAllVisible(loadedHistory),
            ),
            IconButton(
              icon: _isDeleting
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.delete),
              tooltip: 'Delete selected',
              onPressed: _isDeleting || _selectedHistoryIds.isEmpty
                  ? null
                  : () => _deleteSelectedHistory(context),
            ),
          ] else
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
          final displayHistory = history;
          return RefreshIndicator(
            onRefresh: () =>
                ref.refresh(accountHistoryProvider(_request).future),
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
                if (_selectionMode)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      '길게 눌러 선택 모드로 들어왔어요. 삭제할 기록을 선택한 뒤 휴지통 버튼을 눌러주세요.',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.blueGrey[600],
                      ),
                    ),
                  ),
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: displayHistory.length,
                  separatorBuilder: (context, index) =>
                      const Divider(height: 16),
                  itemBuilder: (context, index) {
                    final entry = displayHistory[index];
                    final historyId = _historyEntryId(entry);
                    final date = _parseDate(entry['date']?.toString() ?? '');
                    final balance = _asDouble(entry['balance']);
                    final isSelected = _selectedHistoryIds.contains(historyId);
                    double? diff;
                    if (index + 1 < displayHistory.length) {
                      diff =
                          balance -
                          _asDouble(displayHistory[index + 1]['balance']);
                    }
                    return _buildHistoryRow(
                      entry: entry,
                      date: date,
                      balance: balance,
                      diff: diff,
                      isSelected: isSelected,
                    );
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
    return SegmentedButton<int>(
      segments: const [
        ButtonSegment(value: 50, label: Text('50')),
        ButtonSegment(value: 200, label: Text('200')),
        ButtonSegment(value: 1000, label: Text('1000')),
      ],
      selected: {_limit},
      onSelectionChanged: (selection) {
        setState(() {
          _limit = selection.first;
          _clearSelectionState();
        });
      },
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
    final delta = _calculateTodayChange(history) ?? listTodayDiff;
    final deltaColor = (delta ?? 0) >= 0 ? Colors.teal : Colors.redAccent;
    final deltaText = delta == null
        ? '--'
        : '${delta >= 0 ? '+' : ''}${_currency.format(delta)}';
    const deltaLabel = "Today's Change";

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

  Widget _buildHistoryRow({
    required Map<String, dynamic> entry,
    required DateTime date,
    required double balance,
    required double? diff,
    required bool isSelected,
  }) {
    final diffColor = (diff ?? 0) >= 0 ? Colors.teal : Colors.redAccent;
    final diffText = diff == null
        ? ''
        : '${diff >= 0 ? '+' : ''}${_currency.format(diff)}';

    return Material(
      color: isSelected ? Colors.blue.withOpacity(0.08) : Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onLongPress: () => _enterSelectionMode(entry),
        onTap: _selectionMode ? () => _toggleSelection(entry) : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
          child: Row(
            children: [
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 150),
                child: _selectionMode
                    ? Padding(
                        key: ValueKey<bool>(isSelected),
                        padding: const EdgeInsets.only(right: 12),
                        child: Icon(
                          isSelected
                              ? Icons.check_circle
                              : Icons.radio_button_unchecked,
                          color: isSelected ? Colors.blue : Colors.grey,
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
              Expanded(
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
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.grey,
                          ),
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
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _enterSelectionMode(Map<String, dynamic> entry) {
    setState(() {
      _selectionMode = true;
      _selectedHistoryIds.add(_historyEntryId(entry));
    });
  }

  void _toggleSelection(Map<String, dynamic> entry) {
    final id = _historyEntryId(entry);
    setState(() {
      if (_selectedHistoryIds.contains(id)) {
        _selectedHistoryIds.remove(id);
      } else {
        _selectedHistoryIds.add(id);
      }
      if (_selectedHistoryIds.isEmpty) {
        _selectionMode = false;
      }
    });
  }

  void _selectAllVisible(List<dynamic> history) {
    setState(() {
      _selectionMode = true;
      _selectedHistoryIds
        ..clear()
        ..addAll(history.map((entry) => _historyEntryId(entry)));
    });
  }

  void _clearSelection() {
    setState(_clearSelectionState);
  }

  void _clearSelectionState() {
    _selectionMode = false;
    _selectedHistoryIds.clear();
  }

  Future<void> _deleteSelectedHistory(BuildContext context) async {
    if (_selectedHistoryIds.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete records'),
        content: Text('${_selectedHistoryIds.length}개의 기록을 삭제할까요?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    setState(() {
      _isDeleting = true;
    });

    try {
      await ref
          .read(accountHistoryServiceProvider)
          .deleteHistoryEntries(
            accountNumber: widget.accountNumber,
            selectedDates: _selectedHistoryIds.toList(),
          );
      if (!mounted) return;
      setState(() {
        _isDeleting = false;
        _clearSelectionState();
      });
      messenger.showSnackBar(
        SnackBar(
          content: Text('선택한 기록을 삭제했습니다.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isDeleting = false;
      });
      messenger.showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst('Exception: ', '')),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  String _historyEntryId(Map<String, dynamic> entry) {
    return entry['date']?.toString() ?? '';
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
    double? yesterdayLatest;

    for (final entry in history) {
      final date = _parseDate(entry['date']?.toString() ?? '');
      final balance = _asDouble(entry['balance']);

      if (date.isBefore(todayStart)) {
        yesterdayLatest ??= balance;
        break;
      }

      todayLatest ??= balance;
      todayEarliest = balance;
    }

    if (todayLatest == null) return null;
    final baseline = yesterdayLatest ?? todayEarliest;
    if (baseline == null) return null;
    return todayLatest - baseline;
  }

}
