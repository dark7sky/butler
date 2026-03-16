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
      final isAvailable = await _localAuth.canCheckBiometrics || await _localAuth.isDeviceSupported();
      if (!isAvailable) return false;

      final didAuthenticate = await _localAuth.authenticate(
        localizedReason: 'Please authenticate to access WatchDog',
      );
      return didAuthenticate;
    } catch (e) {
      return false;
    }
  }

  Future<bool> login(String password) async {
    try {
      final response = await _dio.post(
        '/api/auth/login',
        data: {
          'username': 'admin',
          'password': password,
        },
        options: Options(
          contentType: Headers.formUrlEncodedContentType
        )
      );

      if (response.statusCode == 200) {
        final token = response.data['access_token'];
        await _storage.write(key: 'jwt_token', value: token);
        return true;
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  Future<void> logout() async {
    await _storage.delete(key: 'jwt_token');
  }
}
