import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'dashboard_provider.dart';

class TrendPage extends ConsumerStatefulWidget {
  const TrendPage({super.key});

  @override
  ConsumerState<TrendPage> createState() => _TrendPageState();
}

class _TrendPageState extends ConsumerState<TrendPage> {
  bool _showDiff = false;
  late DateTime _endAt;
  late DateTime _startAt;
  late String _chartType;

  final _compactCurrency = NumberFormat.compactCurrency(
    locale: 'ko_KR',
    symbol: '',
    decimalDigits: 0,
  );
  final _tooltipCurrency = NumberFormat.simpleCurrency(
    locale: 'ko_KR',
    decimalDigits: 0,
  );

  @override
  void initState() {
    super.initState();
    _chartType = ref.read(trendChartTypeProvider);
    _endAt = DateTime.now();
    _startAt = _endAt.subtract(const Duration(hours: 24));
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<String>(trendChartTypeProvider, (previous, next) {
      if (previous == next) return;
      setState(() {
        _chartType = next;
        _endAt = DateTime.now();
        _applyQuickRange(_chartType);
      });
    });

    final chartDataAsync = ref.watch(
      chartDataProvider(
        ChartRequest(
          chartType: _chartType,
          startAt: _startAt,
          endAt: _endAt,
          diffMode: _showDiff,
        ),
      ),
    );

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(
          chartDataProvider(
            ChartRequest(
              chartType: _chartType,
              startAt: _startAt,
              endAt: _endAt,
              diffMode: _showDiff,
            ),
          ).future,
        ),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16.0),
          children: [
            _buildDateTimeFilter(context),
            const SizedBox(height: 12),
            _buildChartSelector(),
            const SizedBox(height: 16),
            _buildChartContainer(chartDataAsync),
          ],
        ),
      ),
    );
  }

  Widget _buildDateTimeFilter(BuildContext context) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Range',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.blueGrey,
              ),
            ),
            const SizedBox(height: 10),
            _buildDateTimeRow(
              context: context,
              label: 'Start',
              value: _startAt,
              onChanged: (next) {
                setState(() {
                  _startAt = next.isAfter(_endAt) ? _endAt : next;
                });
              },
            ),
            const SizedBox(height: 8),
            _buildDateTimeRow(
              context: context,
              label: 'End',
              value: _endAt,
              onChanged: (next) {
                setState(() {
                  _endAt = next;
                  if (_startAt.isAfter(_endAt)) {
                    _startAt = _endAt;
                  }
                });
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDateTimeRow({
    required BuildContext context,
    required String label,
    required DateTime value,
    required ValueChanged<DateTime> onChanged,
  }) {
    final dateLabel = DateFormat('yyyy-MM-dd HH:mm').format(value);
    return Row(
      children: [
        SizedBox(
          width: 42,
          child: Text(label, style: const TextStyle(color: Colors.blueGrey)),
        ),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () async {
              final pickedDate = await showDatePicker(
                context: context,
                initialDate: value,
                firstDate: DateTime(2000),
                lastDate: DateTime(2100),
              );
              if (pickedDate == null || !context.mounted) return;

              final pickedTime = await showTimePicker(
                context: context,
                initialTime: TimeOfDay.fromDateTime(value),
              );
              if (pickedTime == null || !context.mounted) return;

              final next = DateTime(
                pickedDate.year,
                pickedDate.month,
                pickedDate.day,
                pickedTime.hour,
                pickedTime.minute,
              );
              onChanged(next);
            },
            icon: const Icon(Icons.schedule, size: 18),
            label: Align(
              alignment: Alignment.centerLeft,
              child: Text(dateLabel),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildChartSelector() {
    final labels = _showDiff
        ? const {'day': 'hours', 'month': 'days', 'year': 'months'}
        : const {'day': 'day', 'month': 'month', 'year': 'year'};

    return Row(
      children: [
        Expanded(
          child: SegmentedButton<String>(
            showSelectedIcon: false,
            segments: [
              ButtonSegment(value: 'day', label: Text(labels['day']!)),
              ButtonSegment(value: 'month', label: Text(labels['month']!)),
              ButtonSegment(value: 'year', label: Text(labels['year']!)),
            ],
            selected: {_chartType},
            onSelectionChanged: (Set<String> newSelection) {
              setState(() {
                _chartType = newSelection.first;
                ref.read(trendChartTypeProvider.notifier).state = _chartType;
                _applyQuickRange(_chartType);
              });
            },
          ),
        ),
        const SizedBox(width: 12),
        Row(
          children: [
            const Text('Diff', style: TextStyle(color: Colors.blueGrey)),
            Switch(
              value: _showDiff,
              onChanged: (value) {
                setState(() {
                  _showDiff = value;
                  _applyQuickRange(_chartType);
                });
              },
            ),
          ],
        ),
      ],
    );
  }

  void _applyQuickRange(String type) {
    if (_showDiff) {
      if (type == 'day') {
        _startAt = _endAt.subtract(const Duration(hours: 24));
      } else if (type == 'month') {
        _startAt = _endAt.subtract(const Duration(days: 30));
      } else {
        _startAt = DateTime(
          _endAt.year - 1,
          _endAt.month,
          _endAt.day,
          _endAt.hour,
          _endAt.minute,
        );
      }
      return;
    }

    if (type == 'day') {
      _startAt = _endAt.subtract(const Duration(hours: 24));
    } else if (type == 'month') {
      _startAt = DateTime(
        _endAt.year,
        _endAt.month - 1,
        _endAt.day,
        _endAt.hour,
        _endAt.minute,
      );
    } else {
      _startAt = DateTime(
        _endAt.year - 1,
        _endAt.month,
        _endAt.day,
        _endAt.hour,
        _endAt.minute,
      );
    }
  }

  Widget _buildChartContainer(AsyncValue<List<dynamic>> chartDataAsync) {
    final titlePrefix = _showDiff ? 'Diff' : 'Total';
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '$titlePrefix Trend',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.blueGrey,
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              height: 400,
              child: chartDataAsync.when(
                data: (data) => _buildNativeChart(data),
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (err, stack) => Center(child: Text('Error: $err')),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNativeChart(List<dynamic> rawData) {
    if (rawData.isEmpty) {
      return const Center(child: Text('No data'));
    }

    final points = <FlSpot>[];
    final labels = <int, String>{};
    double minY = double.infinity;
    double maxY = -double.infinity;

    for (var i = 0; i < rawData.length; i++) {
      final item = rawData[i] as Map<String, dynamic>;
      final y = (item['balance'] as num?)?.toDouble() ?? 0;
      points.add(FlSpot(i.toDouble(), y));
      minY = math.min(minY, y);
      maxY = math.max(maxY, y);
      labels[i] = _formatXAxisLabel(item['date']?.toString() ?? '');
    }

    final padding = ((maxY - minY).abs() * 0.15).clamp(1000, double.infinity);

    return LineChart(
      LineChartData(
        minY: minY - padding,
        maxY: maxY + padding,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: _calculateInterval(minY, maxY),
        ),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 28,
              interval: _calculateBottomInterval(rawData.length),
              getTitlesWidget: (value, meta) {
                final label = labels[value.toInt()];
                if (label == null) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    label,
                    style: const TextStyle(fontSize: 10, color: Colors.grey),
                  ),
                );
              },
            ),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 56,
              interval: _calculateInterval(minY, maxY),
              getTitlesWidget: (value, meta) => Text(
                _compactCurrency.format(value),
                style: const TextStyle(fontSize: 10, color: Colors.grey),
              ),
            ),
          ),
        ),
        borderData: FlBorderData(show: false),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipItems: (spots) => spots.map((spot) {
              final item = rawData[spot.x.toInt()] as Map<String, dynamic>;
              final date = item['date']?.toString() ?? '';
              return LineTooltipItem(
                '${_formatTooltipDate(date)}\n${_tooltipCurrency.format(spot.y)}',
                const TextStyle(color: Colors.white),
              );
            }).toList(),
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: points,
            isCurved: true,
            color: Colors.blueAccent,
            barWidth: 3,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              color: Colors.blueAccent.withValues(alpha: 0.12),
            ),
          ),
        ],
      ),
    );
  }

  String _formatXAxisLabel(String raw) {
    final date = DateTime.tryParse(raw)?.toLocal();
    if (date == null) return '';
    if (_chartType == 'day') return DateFormat('HH:mm').format(date);
    if (_chartType == 'month') return DateFormat('MM/dd').format(date);
    return DateFormat('yyyy/MM').format(date);
  }

  String _formatTooltipDate(String raw) {
    final date = DateTime.tryParse(raw)?.toLocal();
    if (date == null) return raw;
    return DateFormat('yyyy-MM-dd HH:mm').format(date);
  }

  double _calculateInterval(double minY, double maxY) {
    final range = (maxY - minY).abs();
    if (range <= 0) return 1000;
    return math.max(range / 4, 1000);
  }

  static double _calculateBottomInterval(int count) {
    if (count <= 6) return 1;
    if (count <= 12) return 2;
    if (count <= 24) return 4;
    return (count / 6).ceilToDouble();
  }
}
