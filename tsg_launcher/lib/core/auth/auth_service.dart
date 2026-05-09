// App-wide configuration.
// The default compile-time URL is used until overridden via the Settings tab.
class AppConfig {
  /// Compile-time default — used when no value has been saved in secure storage.
  static const String defaultBaseUrl = 'https://tsg.captainparth.com';

  /// Runtime base URL for the TSG Auth FastAPI service.
  /// Mutated at startup by [ServerConfigService.init] and on save in the Settings tab.
  static String tsgAuthBaseUrl = defaultBaseUrl;

  /// Compile-time default for the Quick Info webhook base URL.
  static const String defaultQuickInfoBase =
      'https://n8n.captainparth.com/webhook/deskmate1';

  /// Runtime Quick Info webhook base URL.
  static String quickInfoBase = defaultQuickInfoBase;

  /// Compile-time default for the Quick Info API key.
  static const String defaultQuickInfoKey = 'e03fc53524454ab8b65d91b23c669cc5';

  /// Runtime Quick Info API key.
  static String quickInfoKey = defaultQuickInfoKey;
}
