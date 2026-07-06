import 'dart:collection';

const trendAccountFilterPreferenceKey = 'trend_selected_account_numbers';

List<String> normalizeTrendAccountNumbers(Iterable<String> accountNumbers) {
  final normalized = SplayTreeSet<String>();

  for (final accountNumber in accountNumbers) {
    final trimmed = accountNumber.trim();
    if (trimmed.isNotEmpty) {
      normalized.add(trimmed);
    }
  }

  return normalized.toList(growable: false);
}

bool sameTrendAccountNumbers(List<String> a, List<String> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;

  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }

  return true;
}

bool trendAccountMatchesQuery(Map<String, dynamic> account, String rawQuery) {
  final normalizedQuery = rawQuery.trim().toLowerCase();
  if (normalizedQuery.isEmpty) return true;

  final values = [
    account['account_number'],
    account['name'],
    account['memo'],
    account['company'],
    account['type'],
  ].map((value) => value?.toString() ?? '').toList(growable: false);

  final plainHaystack = values.join(' ').toLowerCase();
  final compactHaystack = _compactTrendAccountSearchText(values.join(''));
  final compactQuery = _compactTrendAccountSearchText(normalizedQuery);

  return plainHaystack.contains(normalizedQuery) ||
      (compactQuery.isNotEmpty && compactHaystack.contains(compactQuery));
}

String trendAccountDisplayName(Map<String, dynamic> account) {
  final memo = account['memo']?.toString().trim() ?? '';
  final name = account['name']?.toString().trim() ?? '';
  final company = account['company']?.toString().trim() ?? '';
  final accountNumber = account['account_number']?.toString().trim() ?? '';

  if (memo.isNotEmpty) return memo;
  if (name.isNotEmpty) return name;
  if (company.isNotEmpty) return company;

  return accountNumber.isNotEmpty ? accountNumber : '계좌';
}

String trendAccountSubtitle(Map<String, dynamic> account) {
  final name = account['name']?.toString().trim() ?? '';
  final memo = account['memo']?.toString().trim() ?? '';
  final accountNumber = account['account_number']?.toString().trim() ?? '';
  final company = account['company']?.toString().trim() ?? '';
  final type = account['type']?.toString().trim() ?? '';

  final parts = <String>[
    if (memo.isNotEmpty && name.isNotEmpty) name,
    if (accountNumber.isNotEmpty) accountNumber,
    if (company.isNotEmpty) company,
    if (type.isNotEmpty) type,
  ];

  return parts.isEmpty ? '계좌 상세 정보 없음' : parts.join(' / ');
}

String _compactTrendAccountSearchText(String value) {
  return value.toLowerCase().replaceAll(RegExp(r'[\s-]+'), '');
}
