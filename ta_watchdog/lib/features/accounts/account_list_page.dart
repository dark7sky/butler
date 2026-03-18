import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../dashboard/dashboard_provider.dart';
import 'account_history_page.dart';

class AccountListPage extends ConsumerStatefulWidget {
  const AccountListPage({super.key});

  @override
  ConsumerState<AccountListPage> createState() => _AccountListPageState();
}

class _AccountListPageState extends ConsumerState<AccountListPage> {
  @override
  Widget build(BuildContext context) {
    ref.listen<AccountSelection?>(selectedAccountProvider, (previous, next) {
      if (next == null || previous == next) return;

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ref.read(selectedAccountProvider.notifier).state = null;
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => AccountHistoryPage(
              accountNumber: next.accountNumber,
              accountName: next.accountName,
            ),
          ),
        );
      });
    });

    final accountsAsync = ref.watch(accountsProvider);
    final currency = NumberFormat.simpleCurrency(
      locale: 'ko_KR',
      decimalDigits: 0,
    );

    double asDouble(dynamic value) {
      if (value is num) return value.toDouble();
      return double.tryParse(value?.toString() ?? '') ?? 0.0;
    }

    String formatSigned(double value) {
      final sign = value > 0
          ? '+'
          : value < 0
              ? '-'
              : '';
      return '$sign${currency.format(value.abs())}';
    }

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(accountsProvider.future),
        child: accountsAsync.when(
          data: (accounts) {
            final sortedAccounts = [...accounts];
            sortedAccounts.sort((a, b) {
              final diffA = asDouble(a['today_diff']);
              final diffB = asDouble(b['today_diff']);
              final hasDiffA = diffA != 0.0;
              final hasDiffB = diffB != 0.0;
              if (hasDiffA != hasDiffB) {
                return hasDiffA ? -1 : 1;
              }
              final absCompare = diffB.abs().compareTo(diffA.abs());
              if (absCompare != 0) return absCompare;
              final balA = asDouble(a['latest_balance']);
              final balB = asDouble(b['latest_balance']);
              return balB.compareTo(balA);
            });

            if (sortedAccounts.isEmpty) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                children: const [
                  SizedBox(
                    height: 300,
                    child: Center(child: Text('No accounts found.')),
                  ),
                ],
              );
            }

            return ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              itemCount: sortedAccounts.length,
              separatorBuilder: (context, index) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final acc = sortedAccounts[index];
                final todayDiff = asDouble(acc['today_diff']);
                final diffColor = todayDiff > 0
                    ? Colors.teal
                    : todayDiff < 0
                        ? Colors.redAccent
                        : Colors.blueGrey;
                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    vertical: 8,
                    horizontal: 8,
                  ),
                  title: Row(
                    children: [
                      Text(
                        acc['company'] ?? '',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          color: Colors.blueGrey,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          acc['name'] ?? '',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 4),
                      Text(
                        acc['account_number'] ?? '',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                          fontFamily: 'monospace',
                        ),
                      ),
                      if (acc['type'] != null)
                        Text(
                          acc['type'],
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.blueGrey.withValues(alpha: 0.7),
                          ),
                        ),
                    ],
                  ),
                  trailing: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        currency.format(acc['latest_balance']),
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: Colors.blueGrey[900],
                        ),
                      ),
                      Text(
                        formatSigned(todayDiff),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: diffColor,
                        ),
                      ),
                      const Icon(
                        Icons.chevron_right,
                        size: 16,
                        color: Colors.grey,
                      ),
                    ],
                  ),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) => AccountHistoryPage(
                          accountNumber: acc['account_number'],
                          accountName:
                              acc['name'] ?? acc['company'] ?? 'Account',
                        ),
                      ),
                    );
                  },
                );
              },
            );
          },
          loading: () => ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            children: const [
              SizedBox(
                height: 300,
                child: Center(child: CircularProgressIndicator()),
              ),
            ],
          ),
          error: (err, stack) => ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              SizedBox(height: 300, child: Center(child: Text('Error: $err'))),
            ],
          ),
        ),
      ),
    );
  }
}
