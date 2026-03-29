import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/brand.dart';
import '../auth/auth_repository.dart';
import '../accounts/account_list_page.dart';
import '../chat/chat_page.dart';
import '../dashboard/dashboard_provider.dart';
import '../dashboard/dashboard_page.dart';
import '../dashboard/trend_page.dart';
import '../manual_inputs/manual_inputs_page.dart';
import '../privacy/amount_masking.dart';

class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  DateTime? _lastBackPressedAt;

  final List<Widget> _pages = const [
    DashboardPage(),
    TrendPage(),
    AccountListPage(),
    ManualInputsPage(),
    ChatPage(),
  ];

  Future<bool> _onWillPop() async {
    final currentIndex = ref.read(homeTabProvider);

    if (currentIndex != 0) {
      ref.read(homeTabProvider.notifier).state = 0;
      _lastBackPressedAt = null;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      return false;
    }

    final now = DateTime.now();
    final shouldExit = _lastBackPressedAt != null &&
        now.difference(_lastBackPressedAt!) <= const Duration(seconds: 2);

    if (shouldExit) {
      await SystemNavigator.pop();
      return false;
    }

    _lastBackPressedAt = now;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text('뒤로가기를 한 번 더 누르면 앱이 종료됩니다.'),
          duration: Duration(seconds: 2),
        ),
      );

    return false;
  }

  @override
  Widget build(BuildContext context) {
    final currentIndex = ref.watch(homeTabProvider);
    final isMaskEnabled = ref.watch(amountMaskEnabledProvider);

    return WillPopScope(
      onWillPop: _onWillPop,
      child: Scaffold(
        appBar: AppBar(
          title: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.asset(
                  AppBrand.markAsset,
                  width: 28,
                  height: 28,
                  fit: BoxFit.cover,
                ),
              ),
              const SizedBox(width: 10),
              const Text(AppBrand.appName),
            ],
          ),
          centerTitle: true,
          elevation: 0,
          actions: [
            TextButton.icon(
              onPressed: () async {
                final notifier = ref.read(amountMaskEnabledProvider.notifier);
                if (!isMaskEnabled) {
                  notifier.state = true;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('금액 가리기가 켜졌어요.'),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                  return;
                }

                final authRepo = ref.read(authRepositoryProvider);
                final authenticated = await authRepo.authenticateBiometrics();
                if (!mounted) return;

                if (authenticated) {
                  notifier.state = false;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('생체인증 완료. 금액 가리기를 해제했어요.'),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('생체인증에 실패했어요. 가리기를 유지합니다.'),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                }
              },
              icon: Icon(isMaskEnabled ? Icons.lock : Icons.lock_open, size: 18),
              label: const Text('가리기'),
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: _pages[currentIndex],
        bottomNavigationBar: NavigationBar(
          selectedIndex: currentIndex,
          onDestinationSelected: (index) =>
              ref.read(homeTabProvider.notifier).state = index,
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.dashboard_outlined),
              selectedIcon: Icon(Icons.dashboard),
              label: 'Dashboard',
            ),
            NavigationDestination(
              icon: Icon(Icons.show_chart),
              selectedIcon: Icon(Icons.show_chart),
              label: 'Trends',
            ),
            NavigationDestination(
              icon: Icon(Icons.table_chart_outlined),
              selectedIcon: Icon(Icons.table_chart),
              label: 'Table',
            ),
            NavigationDestination(
              icon: Icon(Icons.edit_note_outlined),
              selectedIcon: Icon(Icons.edit_note),
              label: 'Inputs',
            ),
            NavigationDestination(
              icon: Icon(Icons.chat_bubble_outline),
              selectedIcon: Icon(Icons.chat_bubble),
              label: 'ASK',
            ),
          ],
        ),
      ),
    );
  }
}
