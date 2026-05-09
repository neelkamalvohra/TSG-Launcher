import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../auth/auth_provider.dart';
import '../../features/auth/biometric_lock_screen.dart';
import '../../features/auth/login_screen.dart';
import '../../features/auth/forgot_password_screen.dart';
import '../../features/auth/change_password_screen.dart';
import '../../features/tiles/tiles_screen.dart';
import '../../features/webview/webview_screen.dart';
import '../../features/admin/admin_panel.dart';
import '../../features/roster_upload/roster_upload_screen.dart';

// Bridges Riverpod auth state changes to GoRouter's refresh mechanism.
// The router is created ONCE; only the redirect is re-evaluated on changes.
// This prevents the router from resetting to initialLocation on every
// auth-state transition (which was causing LoginScreen to be unmounted
// mid-login and errors to be silently swallowed).
class _RouterNotifier extends ChangeNotifier {
  _RouterNotifier(Ref ref) {
    ref.listen<AuthState>(authProvider, (_, __) => notifyListeners());
  }
}

/// Appends [token] as a `token` query parameter to [url].
/// Handles URLs that already have query parameters.
String _injectToken(String url, String? token) {
  if (token == null || token.isEmpty || url.isEmpty) return url;
  final separator = url.contains('?') ? '&' : '?';
  return '$url${separator}token=${Uri.encodeComponent(token)}';
}

final appRouterProvider = Provider<GoRouter>((ref) {
  final notifier = _RouterNotifier(ref);

  final router = GoRouter(
    initialLocation: '/login',
    refreshListenable: notifier,
    redirect: (context, state) {
      final authState = ref.read(authProvider);
      final isAuthenticated = authState is AuthStateAuthenticated;
      final isLoading = authState is AuthStateLoading;
      final isBiometricLock = authState is AuthStateBiometricLock;
      final isMustChange = authState is AuthStateMustChangePassword;
      final isLoginPage = state.matchedLocation == '/login';
      final isBiometricPage = state.matchedLocation == '/biometric-lock';
      final isChangePasswordPage = state.matchedLocation == '/change-password';
      final isForgotPasswordPage = state.matchedLocation == '/forgot-password';

      if (isLoading) return null;
      if (isBiometricLock && !isBiometricPage) return '/biometric-lock';
      if (isBiometricLock && isBiometricPage) return null;
      // Forgot password is always accessible from login
      if (isForgotPasswordPage) return null;
      // Force change-password screen
      if (isMustChange && !isChangePasswordPage) return '/change-password';
      if (isMustChange && isChangePasswordPage) return null;
      if (!isAuthenticated && !isMustChange && !isLoginPage) return '/login';
      if (isAuthenticated && isLoginPage) return '/tiles';
      if (isAuthenticated && isBiometricPage) return '/tiles';
      // After successful change-password, redirect away from that page
      if (isAuthenticated && isChangePasswordPage) return '/tiles';
      return null;
    },
    routes: [
      GoRoute(
        path: '/biometric-lock',
        builder: (_, __) => const BiometricLockScreen(),
      ),
      GoRoute(
        path: '/login',
        builder: (_, __) => const LoginScreen(),
      ),
      GoRoute(
        path: '/forgot-password',
        builder: (_, __) => const ForgotPasswordScreen(),
      ),
      GoRoute(
        path: '/change-password',
        builder: (_, state) {
          final authState = ref.read(authProvider);
          final isExpired = authState is AuthStateMustChangePassword && authState.isExpired;
          return ChangePasswordScreen(isExpired: isExpired);
        },
      ),
      GoRoute(
        path: '/tiles',
        builder: (_, __) => const TilesScreen(),
      ),
      GoRoute(
        path: '/roster-upload',
        builder: (_, __) => const RosterUploadScreen(),
      ),
      GoRoute(
        path: '/tile/:slug',
        builder: (_, state) {
          final slug = state.pathParameters['slug']!;
          // GoRouter may deserialize `extra` from JSON as Map<String, dynamic>,
          // so we safely extract values without a hard cast.
          final rawExtra = state.extra as Map?;
          final url = rawExtra?['url']?.toString() ?? '';
          final name = rawExtra?['name']?.toString() ?? slug;

          // app:// scheme → route to a native screen instead of WebView.
          if (url.startsWith('app://roster-upload')) {
            return const RosterUploadScreen();
          }

          // Inject JWT so the target app can verify the caller's identity.
          final authState = ref.read(authProvider);
          final token = authState is AuthStateAuthenticated
              ? authState.accessToken
              : null;
          return WebViewScreen(url: _injectToken(url, token), title: name);
        },
      ),
      GoRoute(
        path: '/admin',
        builder: (_, __) => const AdminPanel(),
        redirect: (context, state) {
          final auth = ref.read(authProvider);
          if (auth is AuthStateAuthenticated &&
              auth.user.highestRole.canAccessAdmin) {
            return null;
          }
          return '/tiles';
        },
      ),
    ],
    errorBuilder: (_, state) => Scaffold(
      body: Center(child: Text('Page not found: ${state.uri}')),
    ),
  );

  ref.onDispose(notifier.dispose);
  return router;
});
