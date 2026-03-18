import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'dashboard_provider.dart';

class DashboardPage extends ConsumerStatefulWidget {
  const DashboardPage({super.key});

  @override
  ConsumerState<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends ConsumerState<DashboardPage> {
  bool _isBalanceVisible = false;
  final _currency = NumberFormat.simpleCurrency(locale: 'ko_KR', decimalDigits: 0);

  @override
  Widget build(BuildContext context) {
    final summaryAsync = ref.watch(dashboardSummaryProvider);

    return RefreshIndicator(
      onRefresh: () => ref.refresh(dashboardSummaryProvider.future),
      child: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          summaryAsync.when(
            data: (data) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildSummaryCards(data, context),
                const SizedBox(height: 24),
                _buildTodayDetailSection(data['today_detail'], context),
              ],
            ),
            loading: () => const SizedBox(
              height: 200,
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (err, stack) => SizedBox(
              height: 200,
              child: Center(child: Text('Error loading summary: $err')),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTodayDetailSection(
    Map<String, dynamic> todayDetail,
    BuildContext context,
  ) {
    final List<dynamic> accountsDiff = todayDetail['accounts_diff'] ?? [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4.0),
          child: Row(
            children: [
              const Icon(Icons.list_alt, size: 20, color: Colors.blueGrey),
              const SizedBox(width: 8),
              Text(
                "Today's Details",
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.blueGrey[800],
                ),
              ),
              const Spacer(),
              if (accountsDiff.isNotEmpty)
                Text(
                  '${accountsDiff.length} accounts',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (accountsDiff.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(32.0),
              child: Center(
                child: Text(
                  'No changes today',
                  style: TextStyle(color: Colors.grey),
                ),
              ),
            ),
          )
        else
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: accountsDiff.length,
            itemBuilder: (context, index) =>
                _buildDetailItem(accountsDiff[index], context),
            separatorBuilder: (context, index) => const SizedBox(height: 8),
          ),
      ],
    );
  }

  Widget _buildDetailItem(Map<String, dynamic> item, BuildContext context) {
    final diffValue = _asDouble(item['diff']);
    final bool isPositive = diffValue > 0;

    String company = '';
    String name = '';
    String accountNumber = '';

    final info = item['info'];
    if (info is Map) {
      company = info['company'] ?? 'Unknown';
      name = info['name'] ?? '';
      accountNumber = info['account_number'] ?? '';
    } else {
      company = info.toString();
    }

    return Card(
      elevation: 1,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: CircleAvatar(
          backgroundColor: (isPositive ? Colors.teal : Colors.redAccent)
              .withValues(alpha: 0.1),
          child: Icon(
            isPositive ? Icons.arrow_upward : Icons.arrow_downward,
            color: isPositive ? Colors.teal : Colors.redAccent,
            size: 20,
          ),
        ),
        title: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              company,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            if (name.isNotEmpty) ...[
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  name,
                  style: const TextStyle(
                    fontSize: 11,
                    color: Colors.blueGrey,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ],
          ],
        ),
        subtitle: accountNumber.isNotEmpty
            ? GestureDetector(
                onTap: () {
                  Clipboard.setData(ClipboardData(text: accountNumber));
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Copied: $accountNumber'),
                      duration: const Duration(seconds: 1),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                },
                child: Row(
                  children: [
                    Text(
                      accountNumber,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.grey,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Icon(Icons.copy, size: 12, color: Colors.grey),
                  ],
                ),
              )
            : null,
        trailing: Text(
          '${isPositive ? '+' : ''}${_currency.format(diffValue)}',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 15,
            color: isPositive ? Colors.teal : Colors.redAccent,
          ),
        ),
      ),
    );
  }

  Widget _buildSummaryCards(Map<String, dynamic> data, BuildContext context) {
    final daily = data['summary_daily'];
    final monthly = data['summary_monthly'];

    return Column(
      children: [
        GestureDetector(
          onTap: () => setState(() => _isBalanceVisible = !_isBalanceVisible),
          child: _buildMetricCard(
            title: 'Total Balance',
            value: _isBalanceVisible
                ? _currency.format(daily['balance_now'])
                : '********',
            subtitle: 'Last Update: ${daily['last_date']}',
            icon: Icons.account_balance_wallet,
            color: Colors.blueAccent,
            trailing: Icon(
              _isBalanceVisible ? Icons.visibility : Icons.visibility_off,
              color: Colors.grey,
              size: 20,
            ),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _buildMetricCard(
                title: "Today's Change",
                value:
                    '${daily['diff_day'] > 0 ? '+' : ''}${_currency.format(daily['diff_day'])}',
                icon: Icons.today,
                color: daily['diff_day'] >= 0 ? Colors.teal : Colors.redAccent,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildMetricCard(
                title: "Month's Change",
                value:
                    '${monthly['diff_this_month'] > 0 ? '+' : ''}${_currency.format(monthly['diff_this_month'])}',
                icon: Icons.calendar_month,
                color: monthly['diff_this_month'] >= 0
                    ? Colors.teal
                    : Colors.redAccent,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildMetricCard({
    required String title,
    required String value,
    String? subtitle,
    required IconData icon,
    required Color color,
    Widget? trailing,
  }) {
    final isDarkTheme = Theme.of(context).brightness == Brightness.dark;

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 28),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.blueGrey,
                  ),
                ),
                if (trailing != null) ...[const Spacer(), trailing],
              ],
            ),
            const SizedBox(height: 8),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                value,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: isDarkTheme ? Colors.white : Colors.blueGrey[900],
                ),
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: const TextStyle(fontSize: 10, color: Colors.grey),
              ),
            ],
          ],
        ),
      ),
    );
  }

  double _asDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0.0;
  }
}
