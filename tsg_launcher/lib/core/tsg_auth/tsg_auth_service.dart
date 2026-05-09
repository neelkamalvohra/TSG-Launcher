import 'package:dio/dio.dart';
import '../auth/auth_service.dart';
import '../models/tile_model.dart';
import '../models/user_model.dart';

/// HTTP client for the TSG Auth FastAPI service.
/// All methods are static; pass the access token explicitly where required.
class TsgAuthService {
  static Dio _authed(String accessToken) => Dio(
        BaseOptions(
          baseUrl: AppConfig.tsgAuthBaseUrl,
          headers: {
            'Authorization': 'Bearer $accessToken',
            'Content-Type': 'application/json',
          },
          connectTimeout: const Duration(seconds: 5),
          receiveTimeout: const Duration(seconds: 10),
        ),
      );

  // Not a singleton — re-created per call so it always uses the current baseUrl
  // (which may have been updated at runtime via the Settings tab).
  static Dio get _anon => Dio(
        BaseOptions(
          baseUrl: AppConfig.tsgAuthBaseUrl,
          headers: {'Content-Type': 'application/json'},
          connectTimeout: const Duration(seconds: 5),
          receiveTimeout: const Duration(seconds: 10),
        ),
      );

  // ── Health ────────────────────────────────────────────────────────────────

  /// Hits GET /health — throws on failure. Used by the Settings tab to
  /// validate a URL before saving.
  static Future<void> healthCheck() async {
    await _anon.get('/health');
  }

  // ── Auth ──────────────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>> login(
      String username, String password) async {
    final response = await _anon.post('/auth/login', data: {
      'username': username,
      'password': password,
    });
    final data = response.data as Map<String, dynamic>;
    return {
      'access_token': data['access_token'] as String,
      'refresh_token': data['refresh_token'] as String,
      'must_change_password': data['must_change_password'] ?? false,
      'password_expired': data['password_expired'] ?? false,
    };
  }

  static Future<Map<String, String>> refresh(String refreshToken) async {
    final response = await _anon.post('/auth/refresh', data: {
      'refresh_token': refreshToken,
    });
    final data = response.data as Map<String, dynamic>;
    return {
      'access_token': data['access_token'] as String,
      'refresh_token': data['refresh_token'] as String,
    };
  }

  static Future<void> logout(String refreshToken) async {
    try {
      await _anon.post('/auth/logout', data: {'refresh_token': refreshToken});
    } catch (_) {
      // Best-effort — proceed even if the call fails
    }
  }

  // ── Me ────────────────────────────────────────────────────────────────────

  static Future<UserModel> getMe(String accessToken) async {
    final response = await _authed(accessToken).get('/me');
    return UserModel.fromMeResponse(response.data as Map<String, dynamic>);
  }

  static Future<List<TileModel>> fetchTiles(String accessToken) async {
    final response = await _authed(accessToken).get('/me');
    final data = response.data as Map<String, dynamic>;
    final tiles = data['tiles'] as List<dynamic>? ?? [];
    return tiles
        .map((j) => TileModel.fromJson(j as Map<String, dynamic>))
        .where((t) => t.launchUrl.isNotEmpty)
        .toList();
  }

  // ── Admin — Tiles ─────────────────────────────────────────────────────────

  static Future<List<TileModel>> fetchAllTiles(String accessToken) async {
    final response = await _authed(accessToken).get('/admin/tiles');
    final results = response.data as List<dynamic>;
    return results.map((j) => TileModel.fromJson(j as Map<String, dynamic>)).toList();
  }

  static Future<TileModel> createTile({
    required String accessToken,
    required String name,
    required String slug,
    required String launchUrl,
    String? iconUrl,
    String? description,
    String? quickPanel,
  }) async {
    final response = await _authed(accessToken).post('/admin/tiles', data: {
      'name': name,
      'slug': slug,
      'meta_launch_url': launchUrl,
      if (iconUrl != null && iconUrl.isNotEmpty) 'meta_icon': iconUrl,
      if (description != null && description.isNotEmpty)
        'meta_description': description,
      if (quickPanel != null && quickPanel.isNotEmpty && quickPanel != 'none')
        'quick_panel': quickPanel,
    });
    return TileModel.fromJson(response.data as Map<String, dynamic>);
  }

  static Future<TileModel> updateTile({
    required String accessToken,
    required String slug,
    required Map<String, dynamic> fields,
  }) async {
    final response =
        await _authed(accessToken).patch('/admin/tiles/$slug', data: fields);
    return TileModel.fromJson(response.data as Map<String, dynamic>);
  }

  static Future<void> deleteTile(String accessToken, String slug) async {
    await _authed(accessToken).delete('/admin/tiles/$slug');
  }

  // ── Admin — Users ─────────────────────────────────────────────────────────

  static Future<List<Map<String, dynamic>>> fetchUsers(
      String accessToken) async {
    final response = await _authed(accessToken).get('/admin/users');
    return (response.data as List<dynamic>).cast<Map<String, dynamic>>();
  }

  static Future<Map<String, dynamic>> createUser({
    required String accessToken,
    required String username,
    required String email,
    required String name,
    required String password,
    bool isSuperadmin = false,
  }) async {
    final response = await _authed(accessToken).post('/admin/users', data: {
      'username': username,
      'email': email,
      'name': name,
      'password': password,
      'is_superadmin': isSuperadmin,
    });
    return response.data as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> updateUser({
    required String accessToken,
    required String userPk,
    String? email,
    String? name,
    String? password,
    bool? isActive,
    bool? isSuperadmin,
  }) async {
    final data = <String, dynamic>{};
    if (email != null) data['email'] = email;
    if (name != null) data['name'] = name;
    if (password != null) data['password'] = password;
    if (isActive != null) data['is_active'] = isActive;
    if (isSuperadmin != null) data['is_superadmin'] = isSuperadmin;
    final response =
        await _authed(accessToken).patch('/admin/users/$userPk', data: data);
    return response.data as Map<String, dynamic>;
  }

  static Future<void> deleteUser({
    required String accessToken,
    required String userPk,
  }) async {
    await _authed(accessToken).delete('/admin/users/$userPk');
  }

  static Future<void> setUserGroups({
    required String accessToken,
    required String userPk,
    required List<int> groupIds,
  }) async {
    await _authed(accessToken).put(
      '/admin/users/$userPk/groups',
      data: {'group_ids': groupIds},
    );
  }

  // ── Admin — Groups ────────────────────────────────────────────────────────

  static Future<List<Map<String, dynamic>>> fetchGroups(
      String accessToken) async {
    final response = await _authed(accessToken).get('/admin/groups');
    return (response.data as List<dynamic>).cast<Map<String, dynamic>>();
  }

  /// Returns {pk, name, tiles: [...], users: [...]}
  static Future<Map<String, dynamic>> fetchGroupDetail(
      String accessToken, String groupId) async {
    final response =
        await _authed(accessToken).get('/admin/groups/$groupId');
    return response.data as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> createGroup({
    required String accessToken,
    required String name,
  }) async {
    final response = await _authed(accessToken)
        .post('/admin/groups', data: {'name': name});
    return response.data as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> renameGroup({
    required String accessToken,
    required String groupId,
    required String newName,
  }) async {
    final response = await _authed(accessToken)
        .patch('/admin/groups/$groupId', data: {'name': newName});
    return response.data as Map<String, dynamic>;
  }

  static Future<void> deleteGroup({
    required String accessToken,
    required String groupId,
  }) async {
    await _authed(accessToken).delete('/admin/groups/$groupId');
  }

  static Future<void> addUserToGroup({
    required String accessToken,
    required String groupId,
    required int userId,
  }) async {
    await _authed(accessToken)
        .post('/admin/groups/$groupId/users', data: {'user_id': userId});
  }

  static Future<void> removeUserFromGroup({
    required String accessToken,
    required String groupId,
    required String userId,
  }) async {
    await _authed(accessToken)
        .delete('/admin/groups/$groupId/users/$userId');
  }

  static Future<void> assignTileToGroup({
    required String accessToken,
    required String groupId,
    required String tileSlug,
  }) async {
    await _authed(accessToken)
        .post('/admin/groups/$groupId/tiles', data: {'tile_slug': tileSlug});
  }

  static Future<void> removeTileFromGroup({
    required String accessToken,
    required String groupId,
    required String tileId,
  }) async {
    await _authed(accessToken)
        .delete('/admin/groups/$groupId/tiles/$tileId');
  }

  // ── Password management ───────────────────────────────────────────────────

  /// Self-service forgot-password: server generates temp password & emails the user.
  /// Always returns normally (server hides whether email exists).
  static Future<void> forgotPassword(String email) async {
    await _anon.post('/auth/forgot-password', data: {'email': email});
  }

  /// Authenticated change-password (first-login or expiry enforcement).
  static Future<void> changePassword({
    required String accessToken,
    required String currentPassword,
    required String newPassword,
  }) async {
    await _authed(accessToken).post('/auth/change-password', data: {
      'current_password': currentPassword,
      'new_password': newPassword,
    });
  }

  /// Admin-triggered password reset for a specific user.
  static Future<Map<String, dynamic>> adminResetPassword({
    required String accessToken,
    required String userPk,
  }) async {
    final response = await _authed(accessToken)
        .post('/admin/users/$userPk/reset-password');
    return response.data as Map<String, dynamic>;
  }
}
