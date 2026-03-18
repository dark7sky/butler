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
  String _keyword = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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

    String textValue(dynamic value) => value?.toString().trim() ?? '';

    bool matchesKeyword(Map<String, dynamic> account) {
      final normalizedKeyword = _keyword.trim().toLowerCase();
      if (normalizedKeyword.isEmpty) return true;

      final searchable = [
        textValue(account['account_number']),
        textValue(account['name']),
        textValue(account['memo']),
        textValue(account['company']),
        textValue(account['type']),
      ].join(' ').toLowerCase();

      return searchable.contains(normalizedKeyword);
    }

    void copyAccountNumber(String accountNumber) {
      if (accountNumber.isEmpty) return;
      Clipboard.setData(ClipboardData(text: accountNumber));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('계좌번호를 복사했어요: $accountNumber'),
          duration: const Duration(seconds: 1),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(accountsProvider.future),
        child: accountsAsync.when(
          data: (accounts) {
            final filteredAccounts = accounts
                .whereType<Map>()
                .map((account) => Map<String, dynamic>.from(account))
                .where(matchesKeyword)
                .toList();

            filteredAccounts.sort((a, b) {
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

            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              children: [
                TextField(
                  controller: _searchController,
                  onChanged: (value) => setState(() => _keyword = value),
                  decoration: InputDecoration(
                    hintText: '계좌번호, 계좌이름, 메모 등으로 검색',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _keyword.isEmpty
                        ? null
                        : IconButton(
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _keyword = '');
                            },
                            icon: const Icon(Icons.close),
                          ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  '총 ${filteredAccounts.length}개 계좌',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const SizedBox(height: 8),
                if (filteredAccounts.isEmpty)
                  const SizedBox(
                    height: 300,
                    child: Center(child: Text('검색 결과가 없습니다.')),
                  )
                else
                  ...List.generate(filteredAccounts.length, (index) {
                    final acc = filteredAccounts[index];
                    final todayDiff = asDouble(acc['today_diff']);
                    final diffColor = todayDiff > 0
                        ? Colors.teal
                        : todayDiff < 0
                        ? Colors.redAccent
                        : Colors.blueGrey;
                    final accountNumber = textValue(acc['account_number']);
                    final accountName = textValue(acc['name']);
                    final company = textValue(acc['company']);
                    final memo = textValue(acc['memo']);
                    final type = textValue(acc['type']);

                    return Column(
                      children: [
                        ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            vertical: 8,
                            horizontal: 8,
                          ),
                          title: Row(
                            children: [
                              Text(
                                company,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                  color: Colors.blueGrey,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: InkWell(
                                  onTap: () => copyAccountNumber(accountNumber),
                                  borderRadius: BorderRadius.circular(4),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 2,
                                    ),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            accountName,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 15,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        if (accountNumber.isNotEmpty) ...[
                                          const SizedBox(width: 4),
                                          const Icon(
                                            Icons.copy,
                                            size: 14,
                                            color: Colors.grey,
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 4),
                              InkWell(
                                onTap: () => copyAccountNumber(accountNumber),
                                borderRadius: BorderRadius.circular(4),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 2,
                                  ),
                                  child: Row(
                                    children: [
                                      Flexible(
                                        child: Text(
                                          accountNumber,
                                          style: const TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey,
                                            fontFamily: 'monospace',
                                            decoration:
                                                TextDecoration.underline,
                                          ),
                                        ),
                                      ),
                                      if (accountNumber.isNotEmpty) ...[
                                        const SizedBox(width: 4),
                                        const Icon(
                                          Icons.copy,
                                          size: 12,
                                          color: Colors.grey,
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ),
                              if (type.isNotEmpty)
                                Text(
                                  type,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.blueGrey.withValues(
                                      alpha: 0.7,
                                    ),
                                  ),
                                ),
                              if (memo.isNotEmpty)
                                Text(
                                  memo,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: Colors.grey,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
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
                                      : company.isNotEmpty
                                      ? company
                                      : 'Account',
                                ),
                              ),
                            );
                          },
                        ),
                        if (index != filteredAccounts.length - 1)
                          const Divider(height: 1),
                      ],
                    );
                  }),
              ],
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
