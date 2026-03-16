import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// Configuration for API Base URL
const String _defaultProdBaseUrl = 'https://api.example.com';
const String _defaultDevBaseUrl = 'http://localhost:8921';

String get baseUrl {
  const definedBaseUrl = String.fromEnvironment('API_BASE_URL', defaultValue: '');
  if (definedBaseUrl.isNotEmpty) {
    return definedBaseUrl;
  }

  if (kReleaseMode) {
    return _defaultProdBaseUrl;
  }

  // For Local Development:
  if (kIsWeb) {
    return _defaultDevBaseUrl;
  }

  // For Android Emulator, localhost is 10.0.2.2
  // Override using --dart-define=API_BASE_URL=http://<your-lan-ip>:8921
  const bool useEmulator = true;
  if (useEmulator) {
    return 'http://10.0.2.2:8921';
  }

  return _defaultDevBaseUrl;
}

const _secureStorage = FlutterSecureStorage();

final secureStorageProvider = Provider<FlutterSecureStorage>((ref) {
  return _secureStorage;
});

final authTokenProvider = FutureProvider<String?>((ref) async {
  return await _secureStorage.read(key: 'jwt_token');
});

final dioProvider = Provider<Dio>((ref) {
  final dio = Dio(
    BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 60),
    ),
  );

  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) async {
        // Attempt to load token
        final token = await _secureStorage.read(key: 'jwt_token');
        if (token != null) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        return handler.next(options);
      },
    ),
  );

  return dio;
});
