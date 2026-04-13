import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../features/auth/auth_state.dart';

// Configuration for API Base URL
const String _defaultProdBaseUrl = 'https://api.example.com';
const String _defaultDevBaseUrl = 'http://localhost:8921';
const String _apiBaseUrlOverrideKey = 'api_base_url_override';

String get defaultBaseUrl {
  const definedBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: '',
  );
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
  if (defaultTargetPlatform == TargetPlatform.android) {
    return 'http://10.0.2.2:8921';
  }

  return _defaultDevBaseUrl;
}

String? normalizeBaseUrlOverride(String rawValue) {
  final trimmed = rawValue.trim();
  if (trimmed.isEmpty) {
    return null;
  }

  final candidate = trimmed.contains('://') ? trimmed : 'http://$trimmed';
  final parsed = Uri.tryParse(candidate);
  if (parsed == null || parsed.scheme.isEmpty || parsed.host.isEmpty) {
    throw const FormatException(
      'Enter a valid server address like 192.168.0.10:8921 or https://api.example.com.',
    );
  }

  final scheme = parsed.scheme.toLowerCase();
  if (scheme != 'http' && scheme != 'https') {
    throw const FormatException(
      'Server address must start with http:// or https://.',
    );
  }

  return candidate.replaceFirst(RegExp(r'/+$'), '');
}

Future<String?> readBaseUrlOverride(FlutterSecureStorage storage) async {
  final rawValue = await storage.read(key: _apiBaseUrlOverrideKey);
  if (rawValue == null || rawValue.trim().isEmpty) {
    return null;
  }

  try {
    return normalizeBaseUrlOverride(rawValue);
  } on FormatException {
    await storage.delete(key: _apiBaseUrlOverrideKey);
    return null;
  }
}

Future<void> writeBaseUrlOverride(
  FlutterSecureStorage storage,
  String rawValue,
) async {
  final normalized = normalizeBaseUrlOverride(rawValue);
  if (normalized == null) {
    await storage.delete(key: _apiBaseUrlOverrideKey);
    return;
  }

  await storage.write(key: _apiBaseUrlOverrideKey, value: normalized);
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
      baseUrl: defaultBaseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 60),
    ),
  );

  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) async {
        final baseUrlOverride = await readBaseUrlOverride(_secureStorage);
        final resolvedBaseUrl = baseUrlOverride ?? defaultBaseUrl;
        options.path = Uri.parse(
          resolvedBaseUrl,
        ).resolve(options.path).toString();

        // Attempt to load token
        final token = await _secureStorage.read(key: 'jwt_token');
        if (token != null) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        return handler.next(options);
      },
      onError: (error, handler) async {
        if (error.response?.statusCode == 401) {
          await _secureStorage.delete(key: 'jwt_token');
          ref.read(isAuthenticatedProvider.notifier).state = false;
        }
        return handler.next(error);
      },
    ),
  );

  return dio;
});
