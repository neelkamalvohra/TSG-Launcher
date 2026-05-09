import 'package:local_auth/local_auth.dart';

class BiometricService {
  static final _auth = LocalAuthentication();

  /// Returns true if the device supports biometric authentication
  /// and has enrolled credentials (fingerprint / face).
  static Future<bool> isAvailable() async {
    try {
      final canCheck = await _auth.canCheckBiometrics;
      final isSupported = await _auth.isDeviceSupported();
      return canCheck && isSupported;
    } catch (_) {
      return false;
    }
  }

  /// Shows the system biometric prompt.
  /// Returns true if the user authenticated successfully.
  /// [biometricOnly] = false allows device PIN/pattern as a fallback.
  static Future<bool> authenticate({bool biometricOnly = false}) async {
    try {
      return await _auth.authenticate(
        localizedReason: 'Verify your identity to access TSG Launcher',
        options: AuthenticationOptions(
          biometricOnly: biometricOnly,
          stickyAuth: true, // keep prompt visible if user switches apps
        ),
      );
    } catch (_) {
      return false;
    }
  }
}
