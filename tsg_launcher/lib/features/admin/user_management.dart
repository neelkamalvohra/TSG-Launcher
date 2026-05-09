import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/auth/auth_provider.dart';
import '../../core/models/role.dart';
import '../../core/tsg_auth/tsg_auth_service.dart';
import 'admin_providers.dart';

// ── Local data models ─────────────────────────────────────────────────────────

class _UserEntry {
  final String pk;
  final String username;
  final String? name;
  final String? email;
  final List<String> groupIds;
  final bool isActive;
  final bool isSuperadmin;

  const _UserEntry({
    required this.pk,
    required this.username,
    this.name,
    this.email,
    required this.groupIds,
    required this.isActive,
    required this.isSuperadmin,
  });
}

class _GroupEntry {
  final String pk;
  final String name;
  const _GroupEntry({required this.pk, required this.name});
}

// ── UserManagement widget ─────────────────────────────────────────────────────

class UserManagement extends ConsumerWidget {
  final Role callerRole;
  const UserManagement({super.key, required this.callerRole});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final usersAsync = ref.watch(adminUsersProvider);
    final groupsAsync = ref.watch(adminGroupsProvider);

    if (usersAsync.isLoading || groupsAsync.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (usersAsync.hasError) {
      return Center(child: Text('Error loading users: ${usersAsync.error}'));
    }
    if (groupsAsync.hasError) {
      return Center(child: Text('Error loading groups: ${groupsAsync.error}'));
    }

    final rawUsers = usersAsync.value ?? [];
    final rawGroups = groupsAsync.value ?? [];

    final users = rawUsers
        .map((u) => _UserEntry(
              pk: u['pk'].toString(),
              username: u['username'] as String? ?? '',
              name: u['name'] as String?,
              email: u['email'] as String?,
              groupIds: ((u['groups'] as List? ?? []))
                  .map((g) => (g as Map<String, dynamic>)['pk'].toString())
                  .toList(),
              isActive: u['is_active'] as bool? ?? true,
              isSuperadmin: u['is_superadmin'] as bool? ?? false,
            ))
        .toList();

    final groups = rawGroups
        .map((g) => _GroupEntry(
              pk: g['pk'].toString(),
              name: g['name'] as String? ?? '',
            ))
        .toList();

    final groupMap = {for (final g in groups) g.pk: g.name};

    // Only show groups that correspond to known roles
    final roleGroups =
        groups.where((g) => Role.fromGroupName(g.name) != Role.unknown).toList();

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(adminUsersProvider);
        ref.invalidate(adminGroupsProvider);
      },
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: users.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, i) {
          final user = users[i];
          final currentRoleGroupName = user.groupIds
              .map((pk) => groupMap[pk])
              .whereType<String>()
              .where((name) => Role.fromGroupName(name) != Role.unknown)
              .firstOrNull;
          final targetRole = currentRoleGroupName != null
              ? Role.fromGroupName(currentRoleGroupName)
              : Role.unknown;

          return _UserTile(
            user: user,
            roleGroups: roleGroups,
            currentRoleGroupName: currentRoleGroupName,
            targetRole: targetRole,
            callerRole: callerRole,
            onRoleChanged: (newGroupPk) async {
              final auth = ref.read(authProvider);
              if (auth is! AuthStateAuthenticated) return;
              final nonRoleIds = user.groupIds
                  .where((pk) {
                    final n = groupMap[pk];
                    return n == null || Role.fromGroupName(n) == Role.unknown;
                  })
                  .map(int.parse)
                  .toList();
              final updated = [
                ...nonRoleIds,
                if (newGroupPk != null) int.parse(newGroupPk),
              ];
              await TsgAuthService.setUserGroups(
                accessToken: auth.accessToken,
                userPk: user.pk,
                groupIds: updated,
              );
              ref.invalidate(adminUsersProvider);
            },
            onToggleActive: (active) async {
              final auth = ref.read(authProvider);
              if (auth is! AuthStateAuthenticated) return;
              await TsgAuthService.updateUser(
                accessToken: auth.accessToken,
                userPk: user.pk,
                isActive: active,
              );
              ref.invalidate(adminUsersProvider);
            },
            onResetPassword: (newPw) async {
              final auth = ref.read(authProvider);
              if (auth is! AuthStateAuthenticated) return;
              await TsgAuthService.updateUser(
                accessToken: auth.accessToken,
                userPk: user.pk,
                password: newPw,
              );
            },
            onEditName: (newName) async {
              final auth = ref.read(authProvider);
              if (auth is! AuthStateAuthenticated) return;
              await TsgAuthService.updateUser(
                accessToken: auth.accessToken,
                userPk: user.pk,
                name: newName,
              );
              ref.invalidate(adminUsersProvider);
            },
            onDelete: () async {
              final auth = ref.read(authProvider);
              if (auth is! AuthStateAuthenticated) return;
              await TsgAuthService.deleteUser(
                accessToken: auth.accessToken,
                userPk: user.pk,
              );
              ref.invalidate(adminUsersProvider);
            },
          );
        },
      ),
    );
  }
}

// ── User Tile ─────────────────────────────────────────────────────────────────

class _UserTile extends StatelessWidget {
  final _UserEntry user;
  final List<_GroupEntry> roleGroups;
  final String? currentRoleGroupName;
  final Role targetRole;
  final Role callerRole;
  final Future<void> Function(String? newGroupPk) onRoleChanged;
  final Future<void> Function(bool active) onToggleActive;
  final Future<void> Function(String newPw) onResetPassword;
  final Future<void> Function(String newName) onEditName;
  final Future<void> Function() onDelete;

  const _UserTile({
    required this.user,
    required this.roleGroups,
    required this.currentRoleGroupName,
    required this.targetRole,
    required this.callerRole,
    required this.onRoleChanged,
    required this.onToggleActive,
    required this.onResetPassword,
    required this.onEditName,
    required this.onDelete,
  });

  bool get _canModify => callerRole.canManageUsers && callerRole.canModifyRole(targetRole);

  @override
  Widget build(BuildContext context) {
    final displayName =
        user.name?.isNotEmpty == true ? user.name! : user.username;
    final currentGroup =
        roleGroups.where((g) => g.name == currentRoleGroupName).firstOrNull;

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: user.isActive ? null : Colors.grey.shade300,
        child: Icon(
          Icons.person_rounded,
          color: user.isActive ? null : Colors.grey,
        ),
      ),
      title: Text(
        displayName,
        style: user.isActive
            ? null
            : const TextStyle(color: Colors.grey, decoration: TextDecoration.lineThrough),
      ),
      subtitle: Text(user.email ?? user.username),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Role dropdown — only if caller can modify this user's role
          if (_canModify)
            DropdownButton<String>(
              value: currentGroup?.pk,
              hint: const Text('No role'),
              underline: const SizedBox(),
              items: [
                const DropdownMenuItem<String>(
                    value: null, child: Text('No role')),
                ...roleGroups
                    .where((g) {
                      // Non-superadmins cannot assign admin/superadmin groups
                      if (callerRole.canEscalateToAdmin) return true;
                      final r = Role.fromGroupName(g.name);
                      return r.level < Role.admin.level;
                    })
                    .map((g) => DropdownMenuItem<String>(
                          value: g.pk,
                          child: Text(g.name),
                        )),
              ],
              onChanged: (pk) => onRoleChanged(pk),
            ),
          // More actions menu
          if (_canModify || callerRole.canEscalateToAdmin)
            PopupMenuButton<_UserAction>(
              icon: const Icon(Icons.more_vert),
              onSelected: (action) => _handleAction(context, action),
              itemBuilder: (_) => [
                if (_canModify) ...[
                  PopupMenuItem(
                    value: _UserAction.editName,
                    child: ListTile(
                      leading: const Icon(Icons.edit_rounded),
                      title: const Text('Edit name'),
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                    ),
                  ),
                  PopupMenuItem(
                    value: _UserAction.resetPassword,
                    child: ListTile(
                      leading: const Icon(Icons.lock_reset_rounded),
                      title: const Text('Reset password'),
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                    ),
                  ),
                  PopupMenuItem(
                    value: user.isActive
                        ? _UserAction.deactivate
                        : _UserAction.activate,
                    child: ListTile(
                      leading: Icon(user.isActive
                          ? Icons.block_rounded
                          : Icons.check_circle_outline_rounded),
                      title: Text(user.isActive ? 'Deactivate' : 'Activate'),
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                    ),
                  ),
                ],
                if (callerRole.canEscalateToAdmin)
                  PopupMenuItem(
                    value: _UserAction.delete,
                    child: ListTile(
                      leading:
                          const Icon(Icons.delete_rounded, color: Colors.red),
                      title: const Text('Delete user',
                          style: TextStyle(color: Colors.red)),
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  Future<void> _handleAction(BuildContext context, _UserAction action) async {
    switch (action) {
      case _UserAction.editName:
        final ctrl =
            TextEditingController(text: user.name ?? user.username);
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Edit display name'),
            content: TextField(
                controller: ctrl,
                decoration: const InputDecoration(labelText: 'Name'),
                autofocus: true),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel')),
              TextButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Save')),
            ],
          ),
        );
        if (confirmed == true && ctrl.text.trim().isNotEmpty) {
          try {
            await onEditName(ctrl.text.trim());
          } catch (e) {
            if (context.mounted) {
              ScaffoldMessenger.of(context)
                  .showSnackBar(SnackBar(content: Text('Error: $e')));
            }
          }
        }
        break;

      case _UserAction.resetPassword:
        final pwCtrl = TextEditingController();
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: Text('Reset password for ${user.username}'),
            content: TextField(
              controller: pwCtrl,
              decoration: const InputDecoration(labelText: 'New password'),
              obscureText: true,
              autofocus: true,
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel')),
              TextButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Reset')),
            ],
          ),
        );
        if (confirmed == true && pwCtrl.text.isNotEmpty) {
          try {
            await onResetPassword(pwCtrl.text);
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Password reset')));
            }
          } catch (e) {
            if (context.mounted) {
              ScaffoldMessenger.of(context)
                  .showSnackBar(SnackBar(content: Text('Error: $e')));
            }
          }
        }
        break;

      case _UserAction.deactivate:
      case _UserAction.activate:
        final activate = action == _UserAction.activate;
        try {
          await onToggleActive(activate);
        } catch (e) {
          if (context.mounted) {
            ScaffoldMessenger.of(context)
                .showSnackBar(SnackBar(content: Text('Error: $e')));
          }
        }
        break;

      case _UserAction.delete:
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Delete user'),
            content: Text(
                'Permanently delete "${user.username}"? This cannot be undone.'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel')),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Delete',
                    style: TextStyle(color: Colors.red)),
              ),
            ],
          ),
        );
        if (confirmed == true) {
          try {
            await onDelete();
          } catch (e) {
            if (context.mounted) {
              ScaffoldMessenger.of(context)
                  .showSnackBar(SnackBar(content: Text('Error: $e')));
            }
          }
        }
        break;
    }
  }
}

enum _UserAction { editName, resetPassword, deactivate, activate, delete }
