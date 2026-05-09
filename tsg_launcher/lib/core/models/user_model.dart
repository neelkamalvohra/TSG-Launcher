import 'role.dart';

class UserModel {
  final String pk;
  final String username;
  final String email;
  final String name;
  final List<String> groups;
  final Role highestRole;

  const UserModel({
    required this.pk,
    required this.username,
    required this.email,
    required this.name,
    required this.groups,
    required this.highestRole,
  });

  factory UserModel.fromJwtClaims(Map<String, dynamic> claims) {
    final rawGroups = claims['groups'];
    final groups = rawGroups is List
        ? rawGroups.map((g) => g.toString()).toList()
        : <String>[];

    final roles = groups.map(Role.fromGroupName).toList()
      ..sort((a, b) => b.level.compareTo(a.level));

    return UserModel(
      pk: claims['sub']?.toString() ?? '',
      username: claims['preferred_username']?.toString() ?? '',
      email: claims['email']?.toString() ?? '',
      name: claims['name']?.toString() ?? '',
      groups: groups,
      highestRole: roles.isEmpty ? Role.unknown : roles.first,
    );
  }

  factory UserModel.fromApiJson(Map<String, dynamic> json) {
    final rawGroups = json['groups_obj'] as List<dynamic>? ?? [];
    final groups =
        rawGroups.map((g) => (g['name'] as String?) ?? '').toList();

    final roles = groups.map(Role.fromGroupName).toList()
      ..sort((a, b) => b.level.compareTo(a.level));

    return UserModel(
      pk: json['pk']?.toString() ?? '',
      username: json['username']?.toString() ?? '',
      email: json['email']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      groups: groups,
      highestRole: roles.isEmpty ? Role.unknown : roles.first,
    );
  }

  // Parse from GET /api/v3/core/users/me/ response
  // Response: { "user": { "pk", "username", "name", "email", "groups": [{"name","pk"}] } }
  factory UserModel.fromMeResponse(Map<String, dynamic> meJson) {
    final userJson = (meJson['user'] as Map<String, dynamic>?) ?? meJson;
    final rawGroups = userJson['groups'] as List<dynamic>? ?? [];
    final groups = rawGroups
        .map((g) => (g as Map<String, dynamic>)['name'] as String? ?? '')
        .where((n) => n.isNotEmpty)
        .toList();

    final roles = groups.map(Role.fromGroupName).toList()
      ..sort((a, b) => b.level.compareTo(a.level));

    return UserModel(
      pk: userJson['pk']?.toString() ?? '',
      username: userJson['username']?.toString() ?? '',
      email: userJson['email']?.toString() ?? '',
      name: userJson['name']?.toString() ?? '',
      groups: groups,
      highestRole: roles.isEmpty ? Role.unknown : roles.first,
    );
  }
}
