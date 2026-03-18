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
  String _chartType = 'day';
  bool _showDiff = false;
  late DateTime _endAt;
  late DateTime _startAt;

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
    _endAt = DateTime.now();
    _startAt = _endAt.subtract(const Duration(hours: 24));
  }

  @override
  Widget build(BuildContext context) {
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
                error: (err, stack) => Center(child: Text('Chart Error: $err')),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNativeChart(List<dynamic> rawData) {
    if (rawData.isEmpty) {
      return const Center(child: Text('No data available'));
    }

    final spots = <FlSpot>[];
    double minY = double.infinity;
    double maxY = double.negativeInfinity;

    for (int i = 0; i < rawData.length; i++) {
      final val = _asDouble(rawData[i]['balance']);
      spots.add(FlSpot(i.toDouble(), val));
      if (val < minY) minY = val;
      if (val > maxY) maxY = val;
    }

    double range = (maxY - minY).abs();
    if (range == 0) {
      range = math.max(1, maxY.abs() * 0.1);
    }
    final padding = range * 0.15;
    minY = (minY - padding).floorToDouble();
    maxY = (maxY + padding).ceilToDouble();
    if (minY == maxY) {
      minY -= 1;
      maxY += 1;
    }

    final yInterval = ((maxY - minY) / 5)
        .abs()
        .clamp(1, double.infinity)
        .toDouble();
    final xInterval = (rawData.length / 5)
        .ceilToDouble()
        .clamp(1, double.infinity)
        .toDouble();

    return LineChart(
      LineChartData(
        gridData: FlGridData(
          show: true,
          drawVerticalLine: true,
          horizontalInterval: yInterval,
          verticalInterval: xInterval,
          getDrawingHorizontalLine: (value) => FlLine(
            color: Colors.blueGrey.withValues(alpha: 0.1),
            strokeWidth: 1,
          ),
          getDrawingVerticalLine: (value) => FlLine(
            color: Colors.blueGrey.withValues(alpha: 0.1),
            strokeWidth: 1,
          ),
        ),
        titlesData: FlTitlesData(
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (value, meta) {
                final index = value.toInt();
                if (index < 0 || index >= rawData.length) {
                  return const SizedBox();
                }

                final interval = (rawData.length / 5).ceil();
                if (index % interval != 0 && index != rawData.length - 1) {
                  return const SizedBox();
                }

                final date = _parseDate(
                  rawData[index]['date']?.toString() ?? '',
                );
                final label = _bottomLabel(date);
                return Padding(
                  padding: const EdgeInsets.only(top: 8.0),
                  child: Text(
                    label,
                    style: const TextStyle(fontSize: 10, color: Colors.grey),
                  ),
                );
              },
              reservedSize: 22,
            ),
          ),
          leftTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          rightTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (value, meta) {
                return Text(
                  _compactCurrency.format(value),
                  style: const TextStyle(fontSize: 9, color: Colors.grey),
                );
              },
              reservedSize: 45,
            ),
          ),
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
        ),
        borderData: FlBorderData(show: false),
        minY: minY,
        maxY: maxY,
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            color: Colors.blueAccent,
            barWidth: 2,
            isStrokeCapRound: true,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              color: Colors.blueAccent.withValues(alpha: 0.1),
            ),
          ),
        ],
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipItems: (touchedSpots) {
              return touchedSpots.map((spot) {
                final dateStr =
                    rawData[spot.x.toInt()]['date']?.toString() ?? '';
                final balance = spot.y;
                final valueText = _showDiff
                    ? _formatSigned(balance)
                    : _tooltipCurrency.format(balance);
                final dateLabel = DateFormat(
                  'yyyy-MM-dd HH:mm',
                ).format(_parseDate(dateStr));
                return LineTooltipItem(
                  '$dateLabel\n',
                  const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                  children: [
                    TextSpan(
                      text: valueText,
                      style: const TextStyle(
                        color: Colors.yellow,
                        fontSize: 13,
                      ),
                    ),
                  ],
                );
              }).toList();
            },
          ),
        ),
      ),
    );
  }

  String _bottomLabel(DateTime date) {
    if (_showDiff) {
      if (_chartType == 'day') return DateFormat('MM/dd HH:mm').format(date);
      if (_chartType == 'month') return DateFormat('MM/dd').format(date);
      return DateFormat('yyyy/MM').format(date);
    }

    if (_chartType == 'day') return DateFormat('HH:mm').format(date);
    if (_chartType == 'month') return DateFormat('MM/dd').format(date);
    return DateFormat('yyyy/MM').format(date);
  }

  double _asDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0.0;
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

  String _formatSigned(double value) {
    final sign = value > 0
        ? '+'
        : value < 0
        ? '-'
        : '';
    return '$sign${_tooltipCurrency.format(value.abs())}';
  }
}
