import 'dart:async';

import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../auth/biometric_service.dart';
import '../auth/token_storage.dart';
import '../models/user_model.dart';
import '../tsg_auth/tsg_auth_service.dart';

// ---------------------------------------------------------------------------
// Auth exception — distinguishes server-unreachable from bad credentials
// ---------------------------------------------------------------------------
class AuthException implements Exception {
  final String message;
  final bool isNetworkError;
  AuthException(this.message, {this.isNetworkError = false});

  @override
  String toString() => message;
}

// ---------------------------------------------------------------------------
// Auth state
// ---------------------------------------------------------------------------
sealed class AuthState {}

class AuthStateLoading extends AuthState {}

class AuthStateUnauthenticated extends AuthState {}

/// Tokens exist in storage but biometric verification is required first.
class AuthStateBiometricLock extends AuthState {}

class AuthStateAuthenticated extends AuthState {
  final UserModel user;
  final String accessToken;
  AuthStateAuthenticated({required this.user, required this.accessToken});
}

/// Login succeeded but user must change their password (first login or admin reset).
class AuthStateMustChangePassword extends AuthState {
  final UserModel user;
  final String accessToken;
  final String refreshToken;
  final bool isExpired; // true = 90-day expiry, false = must_change flag
  AuthStateMustChangePassword({
    required this.user,
    required this.accessToken,
    required this.refreshToken,
    this.isExpired = false,
  });
}

// ---------------------------------------------------------------------------
// AuthNotifier
// ---------------------------------------------------------------------------
class AuthNotifier extends StateNotifier<AuthState> {
  AuthNotifier() : super(AuthStateLoading()) {
    _tryRestoreSession();
  }

  Timer? _refreshTimer;

  @override
  void dispose() {
    _cancelRefreshTimer();
    super.dispose();
  }

  // Sets the authenticated state and arms the proactive refresh timer.
  void _setAuthenticated(UserModel user, String token) {
    _cancelRefreshTimer();
    state = AuthStateAuthenticated(user: user, accessToken: token);
    _scheduleRefresh(token);
  }

  void _cancelRefreshTimer() {
    _refreshTimer?.cancel();
    _refreshTimer = null;
  }

  // Schedules a silent token refresh 5 minutes before the JWT expires.
  void _scheduleRefresh(String token) {
    try {
      final jwt = JWT.decode(token);
      final exp = (jwt.payload as Map<String, dynamic>)['exp'] as int?;
      if (exp == null) return;
      final expiry = DateTime.fromMillisecondsSinceEpoch(exp * 1000);
      final refreshAt = expiry.subtract(const Duration(minutes: 5));
      final delay = refreshAt.difference(DateTime.now());
      if (delay.isNegative) {
        // Already at/past the refresh window — refresh immediately.
        _refresh();
        return;
      }
      _refreshTimer = Timer(delay, _refresh);
    } catch (_) {
      // Malformed token — skip scheduling; the call-site will get a 401 and
      // the app's error handling will redirect to login.
    }
  }

  // Called on app start — restore tokens from secure storage if present.
  Future<void> _tryRestoreSession() async {
    final hasTokens = await TokenStorage.hasTokens();
    if (!hasTokens) {
      state = AuthStateUnauthenticated();
      return;
    }
    // If device supports biometrics, require verification before unlocking.
    final biometricAvailable = await BiometricService.isAvailable();
    if (biometricAvailable) {
      state = AuthStateBiometricLock();
      return;
    }
    // No biometrics on this device — restore session directly.
    await _restoreFromStorage();
  }

  // Verify stored tokens are still valid and set Authenticated state.
  Future<void> _restoreFromStorage() async {
    final accessToken = await TokenStorage.getAccessToken();
    if (accessToken == null || accessToken.isEmpty) {
      state = AuthStateUnauthenticated();
      return;
    }

    // Fast path: decode JWT locally — no network call needed.
    // This lets the app open instantly even when the server is unreachable.
    try {
      final jwt = JWT.decode(accessToken);
      final exp = (jwt.payload as Map<String, dynamic>)['exp'] as int?;
      final isExpired = exp == null ||
          DateTime.now()
              .isAfter(DateTime.fromMillisecondsSinceEpoch(exp * 1000));

      if (!isExpired) {
        // Token is still valid — authenticate immediately from local data.
        final user =
            UserModel.fromJwtClaims(jwt.payload as Map<String, dynamic>);
        _setAuthenticated(user, accessToken);
        return;
      }
    } catch (_) {
      // JWT malformed — fall through to server validation.
    }

    // JWT is expired — attempt a silent refresh via the server.
    await _refresh();
  }

  // Called by BiometricLockScreen after a successful biometric challenge.
  Future<void> unlockWithBiometric() async {
    state = AuthStateLoading();
    await _restoreFromStorage();
  }

  // Called by BiometricLockScreen "Use password instead" — clears stored
  // tokens and forces the user through the full login flow.
  Future<void> forceFullLogin() async {
    await TokenStorage.clear();
    state = AuthStateUnauthenticated();
  }

  // Called by LoginScreen after form submission.
  Future<void> login({
    required String username,
    required String password,
  }) async {
    state = AuthStateLoading();
    try {
      final tokens = await TsgAuthService.login(username, password);
      await TokenStorage.save(
        accessToken: tokens['access_token']!,
        refreshToken: tokens['refresh_token']!,
        idToken: '',
      );
      final user = await _fetchUserProfile(tokens['access_token']!);

      final mustChange = tokens['must_change_password'] == true;
      final expired = tokens['password_expired'] == true;

      if (mustChange || expired) {
        state = AuthStateMustChangePassword(
          user: user,
          accessToken: tokens['access_token']!,
          refreshToken: tokens['refresh_token']!,
          isExpired: expired && !mustChange,
        );
        return;
      }

      _setAuthenticated(user, tokens['access_token']!);
    } catch (e) {
      state = AuthStateUnauthenticated();
      if (e is DioException && _isConnectivityError(e)) {
        throw AuthException(
          'Cannot reach the server.\nCheck your network connection.',
          isNetworkError: true,
        );
      }
      throw AuthException('Invalid username or password.');
    }
  }

  /// Called after a successful change-password. Promote to fully authenticated.
  Future<void> completePasswordChange() async {
    final stored = await TokenStorage.getAccessToken();
    if (stored == null || stored.isEmpty) {
      state = AuthStateUnauthenticated();
      return;
    }
    final user = await _fetchUserProfile(stored);
    _setAuthenticated(user, stored);
  }

  // Logs out the user: revokes token on server, then clears local storage.
  Future<void> logout() async {
    _cancelRefreshTimer();
    final refreshToken = await TokenStorage.getRefreshToken();
    if (refreshToken != null && refreshToken.isNotEmpty) {
      await TsgAuthService.logout(refreshToken);
    }
    await TokenStorage.clear();
    state = AuthStateUnauthenticated();
  }

  // Silently refresh the access token using the stored refresh token.
  Future<void> _refresh() async {
    final refreshToken = await TokenStorage.getRefreshToken();
    if (refreshToken == null || refreshToken.isEmpty) {
      state = AuthStateUnauthenticated();
      return;
    }
    try {
      final tokens = await TsgAuthService.refresh(refreshToken);
      await TokenStorage.save(
        accessToken: tokens['access_token']!,
        refreshToken: tokens['refresh_token']!,
        idToken: '',
      );
      final user = await _fetchUserProfile(tokens['access_token']!);
      _setAuthenticated(user, tokens['access_token']!);
    } on DioException catch (e) {
      if (_isConnectivityError(e)) {
        // Server unreachable — stay logged in using the stored access token
        // so the user isn't kicked out just because the server is temporarily down.
        final storedToken = await TokenStorage.getAccessToken();
        if (storedToken != null && storedToken.isNotEmpty) {
          try {
            final user = _parseUserFromJwt(storedToken);
            _setAuthenticated(user, storedToken);
            return;
          } catch (_) {}
        }
        // No usable stored token — unauthenticated but don't blame the user.
        state = AuthStateUnauthenticated();
        return;
      }
      // 401 / bad token — force re-login.
      await TokenStorage.clear();
      state = AuthStateUnauthenticated();
    } catch (_) {
      await TokenStorage.clear();
      state = AuthStateUnauthenticated();
    }
  }

  /// Returns true for transient network errors (as opposed to auth rejections).
  bool _isConnectivityError(DioException e) =>
      e.type == DioExceptionType.connectionError ||
      e.type == DioExceptionType.connectionTimeout ||
      e.type == DioExceptionType.receiveTimeout ||
      e.type == DioExceptionType.sendTimeout;

  UserModel _parseUserFromJwt(String token) {
    final jwt = JWT.decode(token);
    return UserModel.fromJwtClaims(jwt.payload as Map<String, dynamic>);
  }

  Future<UserModel> _fetchUserProfile(String accessToken) async {
    try {
      return await TsgAuthService.getMe(accessToken);
    } catch (_) {
      // Fallback: decode the JWT claims directly if the network call fails.
      return _parseUserFromJwt(accessToken);
    }
  }
}

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>(
  (_) => AuthNotifier(),
);

