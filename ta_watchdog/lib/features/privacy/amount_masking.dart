import 'package:flutter_riverpod/flutter_riverpod.dart';

final amountMaskEnabledProvider = StateProvider<bool>((ref) => false);

String maskAmountText(String original, {bool enabled = false}) {
  if (!enabled) return original;
  return '******';
}

