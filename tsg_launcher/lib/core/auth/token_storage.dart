import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class TokenStorage {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  static const _keyAccess = 'access_token';
  static const _keyRefresh = 'refresh_token';
  static const _keyId = 'id_token';

  static Future<void> save({
    required String accessToken,
    required String refreshToken,
    required String idToken,
  }) async {
    await Future.wait([
      _storage.write(key: _keyAccess, value: accessToken),
      _storage.write(key: _keyRefresh, value: refreshToken),
      _storage.write(key: _keyId, value: idToken),
    ]);
  }

  static Future<String?> getAccessToken() =>
      _storage.read(key: _keyAccess);

  static Future<String?> getRefreshToken() =>
      _storage.read(key: _keyRefresh);

  static Future<String?> getIdToken() =>
      _storage.read(key: _keyId);

  static Future<void> clear() async {
    await Future.wait([
      _storage.delete(key: _keyAccess),
      _storage.delete(key: _keyRefresh),
      _storage.delete(key: _keyId),
    ]);
  }

  static Future<bool> hasTokens() async {
    final token = await _storage.read(key: _keyAccess);
    return token != null && token.isNotEmpty;
  }
}
