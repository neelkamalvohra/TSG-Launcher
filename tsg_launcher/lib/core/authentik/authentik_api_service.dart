import 'package:dio/dio.dart';
import '../auth/auth_service.dart';
import '../models/tile_model.dart';

class AuthentikApiService {
  late final Dio _dio;

  AuthentikApiService(String accessToken) {
    _dio = Dio(
      BaseOptions(
        baseUrl: AppConfig.authentikBaseUrl,
        headers: {
          'Authorization': 'Bearer $accessToken',
          'Content-Type': 'application/json',
        },
      ),
    );
  }

  // ── Tiles (Authentik Applications) ──────────────────────────────────────

  // Returns only applications the current user has access to (policy-filtered)
  Future<List<TileModel>> fetchTiles() async {
    final response = await _dio.get(
      '/api/v3/core/applications/',
      queryParameters: {'ordering': 'name', 'superuser_full_list': false},
    );
    final results = (response.data['results'] as List<dynamic>);
    return results
        .map((j) => TileModel.fromJson(j as Map<String, dynamic>))
        .where((t) => t.launchUrl.isNotEmpty && t.slug != AppConfig.clientId)
        .toList();
  }

  // Admin: fetch ALL applications regardless of policy
  Future<List<TileModel>> fetchAllTiles() async {
    final response = await _dio.get(
      '/api/v3/core/applications/',
      queryParameters: {'ordering': 'name', 'superuser_full_list': true},
    );
    final results = (response.data['results'] as List<dynamic>);
    return results
        .map((j) => TileModel.fromJson(j as Map<String, dynamic>))
        .toList();
  }

  Future<TileModel> createTile({
    required String name,
    required String slug,
    required String launchUrl,
    String? iconUrl,
    String? description,
  }) async {
    final response = await _dio.post(
      '/api/v3/core/applications/',
      data: {
        'name': name,
        'slug': slug,
        'meta_launch_url': launchUrl,
        if (iconUrl != null) 'meta_icon': iconUrl,
        if (description != null) 'meta_description': description,
        'policy_engine_mode': 'any',
      },
    );
    return TileModel.fromJson(response.data as Map<String, dynamic>);
  }

  Future<TileModel> updateTile({
    required String slug,
    required Map<String, dynamic> fields,
  }) async {
    final response = await _dio.patch(
      '/api/v3/core/applications/$slug/',
      data: fields,
    );
    return TileModel.fromJson(response.data as Map<String, dynamic>);
  }

  Future<void> deleteTile(String slug) async {
    await _dio.delete('/api/v3/core/applications/$slug/');
  }

  // ── Groups (Roles) ───────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> fetchGroups() async {
    final response = await _dio.get('/api/v3/core/groups/');
    return (response.data['results'] as List<dynamic>)
        .cast<Map<String, dynamic>>();
  }

  // ── Policy Bindings (tile ↔ group access control) ────────────────────────

  Future<List<Map<String, dynamic>>> fetchBindingsForApp(
      String appPk) async {
    final response = await _dio.get(
      '/api/v3/policies/bindings/',
      queryParameters: {'target': appPk},
    );
    return (response.data['results'] as List<dynamic>)
        .cast<Map<String, dynamic>>();
  }

  Future<void> createBinding({
    required String targetPk,
    required String groupPk,
    int order = 0,
  }) async {
    await _dio.post(
      '/api/v3/policies/bindings/',
      data: {
        'target': targetPk,
        'group': groupPk,
        'enabled': true,
        'order': order,
      },
    );
  }

  Future<void> deleteBinding(String bindingPk) async {
    await _dio.delete('/api/v3/policies/bindings/$bindingPk/');
  }

  // ── Users ────────────────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> fetchUsers() async {
    final response = await _dio.get(
      '/api/v3/core/users/',
      queryParameters: {'ordering': 'username', 'groups_by_pk': true},
    );
    return (response.data['results'] as List<dynamic>)
        .cast<Map<String, dynamic>>();
  }

  Future<void> setUserGroups({
    required String userPk,
    required List<String> groupPks,
  }) async {
    await _dio.patch(
      '/api/v3/core/users/$userPk/',
      data: {'groups': groupPks},
    );
  }
}
