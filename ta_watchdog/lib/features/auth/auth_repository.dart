import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import '../../core/api_client.dart';

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(
    ref.watch(dioProvider),
    ref.watch(secureStorageProvider),
  );
});

class LoginResult {
  final bool isSuccess;
  final String? errorMessage;

  const LoginResult._({required this.isSuccess, this.errorMessage});

  const LoginResult.success() : this._(isSuccess: true);

  const LoginResult.failure(String message)
    : this._(isSuccess: false, errorMessage: message);
}

class AuthRepository {
  final Dio _dio;
  final FlutterSecureStorage _storage;
  final LocalAuthentication _localAuth = LocalAuthentication();

  AuthRepository(this._dio, this._storage);

  Future<bool> hasStoredToken() async {
    final token = await _storage.read(key: 'jwt_token');
    return token != null;
  }

  Future<bool> authenticateBiometrics() async {
    try {
      final isAvailable =
          await _localAuth.canCheckBiometrics ||
          await _localAuth.isDeviceSupported();
      if (!isAvailable) return false;

      final didAuthenticate = await _localAuth.authenticate(
        localizedReason: 'Please authenticate to access WatchDog',
      );
      return didAuthenticate;
    } catch (e) {
      return false;
    }
  }

  Future<String?> getServerBaseUrlOverride() async {
    return readBaseUrlOverride(_storage);
  }

  Future<void> setServerBaseUrlOverride(String rawValue) async {
    await writeBaseUrlOverride(_storage, rawValue);
  }

  Future<LoginResult> login(String password) async {
    try {
      final response = await _dio.post(
        '/api/auth/login',
        data: {'username': 'admin', 'password': password},
        options: Options(contentType: Headers.formUrlEncodedContentType),
      );

      if (response.statusCode == 200) {
        final token = response.data['access_token'];
        await _storage.write(key: 'jwt_token', value: token);
        return const LoginResult.success();
      }
      return const LoginResult.failure('Login failed. Check your password.');
    } on DioException catch (error) {
      final responseData = error.response?.data;
      if (responseData is Map) {
        final detail = responseData['detail'];
        if (detail is String && detail.trim().isNotEmpty) {
          return LoginResult.failure(detail.trim());
        }
      }
      return LoginResult.failure(
        error.response?.statusCode == 401
            ? 'Login failed. Check your password.'
            : 'Could not contact the server. Please try again.',
      );
    } catch (_) {
      return const LoginResult.failure(
        'Could not contact the server. Please try again.',
      );
    }
  }

  Future<void> logout() async {
    await _storage.delete(key: 'jwt_token');
  }
}
