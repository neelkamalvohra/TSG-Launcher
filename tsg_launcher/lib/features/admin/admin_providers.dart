import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/auth/auth_provider.dart';
import '../../core/auth/auth_service.dart';
import '../../core/tsg_auth/tsg_auth_service.dart';

/// Groups list — ordered by backend (superadmin, admin, head, sme, supervisor, engineer, trainee).
final adminGroupsProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final auth = ref.watch(authProvider);
  if (auth is! AuthStateAuthenticated) return [];
  return TsgAuthService.fetchGroups(auth.accessToken);
});

/// Full user list.
final adminUsersProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final auth = ref.watch(authProvider);
  if (auth is! AuthStateAuthenticated) return [];
  return TsgAuthService.fetchUsers(auth.accessToken);
});

/// Tracks the current server base URL in-memory so the Settings tab rebuilds
/// reactively after a save.
final serverUrlProvider = StateProvider<String>((ref) => AppConfig.tsgAuthBaseUrl);

/// Tracks the Quick Info webhook base URL reactively.
final quickInfoBaseProvider = StateProvider<String>((ref) => AppConfig.quickInfoBase);

/// Tracks the Quick Info API key reactively.
final quickInfoKeyProvider = StateProvider<String>((ref) => AppConfig.quickInfoKey);
