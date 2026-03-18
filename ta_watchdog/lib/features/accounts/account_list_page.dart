import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _copyAccountNumber(String accountNumber) {
    if (accountNumber.isEmpty) return;

    Clipboard.setData(ClipboardData(text: accountNumber));
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('계좌번호를 복사했어요: $accountNumber')));
  }

  bool _matchesQuery(Map<String, dynamic> account, String normalizedQuery) {
    if (normalizedQuery.isEmpty) return true;

    final haystack = [
      account['account_number'],
      account['name'],
      account['memo'],
      account['company'],
      account['type'],
    ].whereType<String>().map((value) => value.toLowerCase()).join(' ');

    return haystack.contains(normalizedQuery);
  }

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
            final normalizedQuery = _searchQuery.trim().toLowerCase();
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

            final filteredAccounts = sortedAccounts
                .where(
                  (account) => _matchesQuery(
                    Map<String, dynamic>.from(account as Map),
                    normalizedQuery,
                  ),
                )
                .toList();

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
              itemCount: filteredAccounts.length + 1,
              separatorBuilder: (context, index) => index == 0
                  ? const SizedBox(height: 12)
                  : const Divider(height: 1),
              itemBuilder: (context, index) {
                if (index == 0) {
                  return TextField(
                    controller: _searchController,
                    textInputAction: TextInputAction.search,
                    decoration: InputDecoration(
                      hintText: '계좌명, 계좌번호, 메모로 검색',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _searchQuery.isEmpty
                          ? null
                          : IconButton(
                              onPressed: () {
                                _searchController.clear();
                                setState(() => _searchQuery = '');
                              },
                              icon: const Icon(Icons.clear),
                            ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onChanged: (value) => setState(() => _searchQuery = value),
                  );
                }

                if (filteredAccounts.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 48),
                    child: Center(child: Text('검색 결과가 없어요.')),
                  );
                }

                final acc = filteredAccounts[index - 1] as Map;
                final todayDiff = asDouble(acc['today_diff']);
                final diffColor = todayDiff > 0
                    ? Colors.teal
                    : todayDiff < 0
                    ? Colors.redAccent
                    : Colors.blueGrey;
                final accountNumber = (acc['account_number'] ?? '').toString();
                final accountName = (acc['name'] ?? '').toString();
                final memo = (acc['memo'] ?? '').toString();

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
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => _copyAccountNumber(accountNumber),
                          child: Text(
                            accountName,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ],
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 4),
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => _copyAccountNumber(accountNumber),
                        child: Text(
                          accountNumber,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.grey,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ),
                      if (memo.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            memo,
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.blueGrey.withValues(alpha: 0.8),
                            ),
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
                          accountNumber: accountNumber,
                          accountName: accountName.isNotEmpty
                              ? accountName
                              : (acc['company'] ?? 'Account').toString(),
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
