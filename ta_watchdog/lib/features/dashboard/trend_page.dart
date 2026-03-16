import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
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
  final _compactCurrency = NumberFormat.compactCurrency(
    locale: 'ko_KR',
    symbol: '',
    decimalDigits: 0,
  );
  final _tooltipCurrency =
      NumberFormat.simpleCurrency(locale: 'ko_KR', decimalDigits: 0);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          _buildChartSelector(),
          const SizedBox(height: 16),
          _buildChartContainer(),
        ],
      ),
    );
  }

  Widget _buildChartSelector() {
    return Row(
      children: [
        Expanded(
          child: SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'day', label: Text('Today')),
              ButtonSegment(value: 'month', label: Text('Month')),
              ButtonSegment(value: 'year', label: Text('Year')),
            ],
            selected: {_chartType},
            onSelectionChanged: (Set<String> newSelection) {
              setState(() {
                _chartType = newSelection.first;
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
                });
              },
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildChartContainer() {
    final chartDataAsync = ref.watch(chartDataProvider(_chartType));

    final title = _chartType == 'day'
        ? 'Today Trend'
        : _chartType == 'month'
            ? 'Month Trend'
            : 'Year Trend';

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blueGrey),
            ),
            const SizedBox(height: 24),
            SizedBox(
              height: 400, // Slightly taller as it's a dedicated page
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

    final filteredData = _filterByRange(rawData);
    if (filteredData.isEmpty) {
      return const Center(child: Text('No data in selected range'));
    }

    final spots = <FlSpot>[];
    double minY = double.infinity;
    double maxY = double.negativeInfinity;

    for (int i = 0; i < filteredData.length; i++) {
        final current = _asDouble(filteredData[i]['balance']);
        final val = _showDiff && i > 0
            ? current - _asDouble(filteredData[i - 1]['balance'])
            : _showDiff
                ? 0.0
                : current;
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

    final yInterval =
        ((maxY - minY) / 5).abs().clamp(1, double.infinity).toDouble();
    final xInterval =
        (filteredData.length / 5).ceilToDouble().clamp(1, double.infinity).toDouble();

    return LineChart(
      LineChartData(
        gridData: FlGridData(
          show: true,
          drawVerticalLine: true,
          horizontalInterval: yInterval,
          verticalInterval: xInterval,
          getDrawingHorizontalLine: (value) => FlLine(
            color: Colors.blueGrey.withOpacity(0.1),
            strokeWidth: 1,
          ),
          getDrawingVerticalLine: (value) => FlLine(
            color: Colors.blueGrey.withOpacity(0.1),
            strokeWidth: 1,
          ),
        ),
        titlesData: FlTitlesData(
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (value, meta) {
                final index = value.toInt();
                if (index < 0 || index >= filteredData.length) return const SizedBox();
                
                int interval = (filteredData.length / 5).ceil();
                if (index % interval != 0 && index != filteredData.length - 1) return const SizedBox();

                final dateStr = filteredData[index]['date']?.toString() ?? '';
                final date = _parseDate(dateStr);
                String label = '';
                if (_chartType == 'day') label = DateFormat('HH:mm').format(date);
                if (_chartType == 'month') label = DateFormat('MM/dd').format(date);
                if (_chartType == 'year') label = DateFormat('yyyy/MM').format(date);

                return Padding(
                  padding: const EdgeInsets.only(top: 8.0),
                  child: Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey)),
                );
              },
              reservedSize: 22,
            ),
          ),
          leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: AxisTitles(
            sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (value, meta) {
                    return Text(
                        _compactCurrency.format(value),
                        style: const TextStyle(fontSize: 9, color: Colors.grey)
                    );
                },
                reservedSize: 45
            )
          ),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
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
              color: Colors.blueAccent.withOpacity(0.1),
            ),
          ),
        ],
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipItems: (touchedSpots) {
              return touchedSpots.map((spot) {
                final dateStr = filteredData[spot.x.toInt()]['date']?.toString() ?? '';
                final balance = spot.y;
                final valueText = _showDiff
                    ? _formatSigned(balance)
                    : _tooltipCurrency.format(balance);
                final dateLabel = _chartType == 'year'
                    ? DateFormat('yyyy/MM').format(_parseDate(dateStr))
                    : DateFormat('MM/dd HH:mm').format(_parseDate(dateStr));
                return LineTooltipItem(
                  '$dateLabel\n',
                  const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  children: [
                    TextSpan(
                      text: valueText,
                      style: const TextStyle(color: Colors.yellow, fontSize: 13),
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

  double _asDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0.0;
  }

  DateTime _parseDate(String input) {
    final parsed = DateTime.tryParse(input);
    if (parsed != null) return parsed;
    // Fallback for 'yyyy-MM-dd HH:mm:ss' (space-separated)
    try {
      return DateFormat('yyyy-MM-dd HH:mm:ss').parse(input);
    } catch (_) {
      return DateTime.now();
    }
  }

  List<dynamic> _filterByRange(List<dynamic> rawData) {
    final now = DateTime.now();
    return rawData.where((item) {
      final date = _parseDate(item['date']?.toString() ?? '');
      if (_chartType == 'day') {
        return date.year == now.year &&
            date.month == now.month &&
            date.day == now.day;
      }
      if (_chartType == 'month') {
        return date.year == now.year && date.month == now.month;
      }
      return date.year == now.year;
    }).toList();
  }

  String _formatSigned(double value) {
    final sign = value > 0 ? '+' : value < 0 ? '-' : '';
    return '$sign${_tooltipCurrency.format(value.abs())}';
  }
}
