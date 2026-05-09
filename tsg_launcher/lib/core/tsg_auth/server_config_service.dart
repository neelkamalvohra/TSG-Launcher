import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../auth/auth_service.dart';

/// Persists the TSG Auth server base URL in secure storage.
/// Call [init] once at app startup to hydrate [AppConfig.tsgAuthBaseUrl].
class ServerConfigService {
  static const _storage = FlutterSecureStorage();
  static const _key = 'tsg_server_url';
  static const _quickInfoBaseKey = 'tsg_quick_info_base';
  static const _quickInfoKeyKey = 'tsg_quick_info_key';

  /// Load all persisted config values into [AppConfig].
  static Future<void> init() async {
    final savedUrl = await _storage.read(key: _key);
    if (savedUrl != null && savedUrl.isNotEmpty) {
      AppConfig.tsgAuthBaseUrl = savedUrl;
    }
    final savedQiBase = await _storage.read(key: _quickInfoBaseKey);
    if (savedQiBase != null && savedQiBase.isNotEmpty) {
      AppConfig.quickInfoBase = savedQiBase;
    }
    final savedQiKey = await _storage.read(key: _quickInfoKeyKey);
    if (savedQiKey != null && savedQiKey.isNotEmpty) {
      AppConfig.quickInfoKey = savedQiKey;
    }
  }

  // ── Auth server URL ────────────────────────────────────────────────────────

  /// Current URL (reads live storage; use [AppConfig.tsgAuthBaseUrl] for sync access).
  static Future<String> getBaseUrl() async {
    return await _storage.read(key: _key) ?? AppConfig.defaultBaseUrl;
  }

  /// Persist a new URL and update the in-memory value immediately.
  static Future<void> setBaseUrl(String url) async {
    await _storage.write(key: _key, value: url);
    AppConfig.tsgAuthBaseUrl = url;
  }

  /// Remove stored override — resets to compile-time default.
  static Future<void> resetToDefault() async {
    await _storage.delete(key: _key);
    AppConfig.tsgAuthBaseUrl = AppConfig.defaultBaseUrl;
  }

  // ── Quick Info config ──────────────────────────────────────────────────────

  static Future<void> setQuickInfoBase(String url) async {
    await _storage.write(key: _quickInfoBaseKey, value: url);
    AppConfig.quickInfoBase = url;
  }

  static Future<void> setQuickInfoKey(String key) async {
    await _storage.write(key: _quickInfoKeyKey, value: key);
    AppConfig.quickInfoKey = key;
  }

  static Future<void> resetQuickInfoToDefault() async {
    await _storage.delete(key: _quickInfoBaseKey);
    await _storage.delete(key: _quickInfoKeyKey);
    AppConfig.quickInfoBase = AppConfig.defaultQuickInfoBase;
    AppConfig.quickInfoKey = AppConfig.defaultQuickInfoKey;
  }
}
