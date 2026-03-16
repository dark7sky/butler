import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'features/auth/auth_repository.dart';
import 'features/auth/login_page.dart';
import 'features/home/home_page.dart';

void main() {
  runApp(
    const ProviderScope(
      child: WatchDogApp(),
    ),
  );
}

class WatchDogApp extends StatelessWidget {
  const WatchDogApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Total Account',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blueGrey),
        useMaterial3: true,
      ),
      home: const AuthWrapper(),
    );
  }
}

class AuthWrapper extends ConsumerStatefulWidget {
  const AuthWrapper({super.key});

  @override
  ConsumerState<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends ConsumerState<AuthWrapper> {
  bool _isLoading = true;
  bool _isAuthenticated = false;

  @override
  void initState() {
    super.initState();
    _checkAuth();
  }

  Future<void> _checkAuth() async {
    final authRepo = ref.read(authRepositoryProvider);
    final hasToken = await authRepo.hasStoredToken();

    if (hasToken) {
      // Prompt Biometrics if they have a token
      final authSuccess = await authRepo.authenticateBiometrics();
      if (authSuccess) {
        setState(() {
          _isAuthenticated = true;
        });
      }
      // If authSuccess is false, we just stay on _isAuthenticated = false
      // which will show the LoginPage. We DO NOT call logout() here
      // so the token stays in storage for the next attempt.
    }
    
    setState(() {
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (_isAuthenticated) {
      return const HomePage();
    }

    return const LoginPage();
  }
}
