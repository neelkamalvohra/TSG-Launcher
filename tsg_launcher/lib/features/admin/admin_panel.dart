import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/auth/auth_provider.dart';
import '../../core/auth/auth_service.dart';
import '../../core/models/role.dart';
import '../../core/models/tile_model.dart';
import '../../core/tsg_auth/server_config_service.dart';
import '../../core/tsg_auth/tsg_auth_service.dart';
import '../tiles/tiles_provider.dart';
import 'admin_providers.dart';
import 'tile_form.dart';
import 'user_management.dart';

final adminTilesProvider = FutureProvider<List<TileModel>>((ref) async {
  final auth = ref.watch(authProvider);
  if (auth is! AuthStateAuthenticated) return [];
  return TsgAuthService.fetchAllTiles(auth.accessToken);
});

class AdminPanel extends ConsumerStatefulWidget {
  const AdminPanel({super.key});

  @override
  ConsumerState<AdminPanel> createState() => _AdminPanelState();
}

class _AdminPanelState extends ConsumerState<AdminPanel>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this)
      ..addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    final role =
        auth is AuthStateAuthenticated ? auth.user.highestRole : Role.unknown;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin Panel'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.grid_view_rounded), text: 'Tiles'),
            Tab(icon: Icon(Icons.group_rounded), text: 'Groups'),
            Tab(icon: Icon(Icons.people_rounded), text: 'Users'),
            Tab(icon: Icon(Icons.settings_rounded), text: 'Settings'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          const _TilesTab(),
          _GroupsTab(callerRole: role),
          UserManagement(callerRole: role),
          _SettingsTab(callerRole: role),
        ],
      ),
      floatingActionButton: _buildFab(context, role),
    );
  }

  Widget? _buildFab(BuildContext context, Role role) {
    switch (_tabController.index) {
      case 0:
        if (!role.canManageTiles) return null;
        return FloatingActionButton.extended(
          heroTag: 'fab_tiles',
          icon: const Icon(Icons.add),
          label: const Text('Add Tile'),
          onPressed: () => _openTileForm(context, null),
        );
      case 1:
        if (!role.canManageGroups) return null;
        return FloatingActionButton.extended(
          heroTag: 'fab_groups',
          icon: const Icon(Icons.add),
          label: const Text('Add Group'),
          onPressed: () => _addGroupDialog(context),
        );
      case 2:
        if (!role.canManageUsers) return null;
        return FloatingActionButton.extended(
          heroTag: 'fab_users',
          icon: const Icon(Icons.person_add_rounded),
          label: const Text('Add User'),
          onPressed: () => _addUserDialog(context),
        );
      case 3:
        return null; // Settings tab has no FAB
      default:
        return null;
    }
  }

  void _openTileForm(BuildContext context, TileModel? existing) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => TileForm(
        existing: existing,
        onSaved: () {
          ref.invalidate(adminTilesProvider);
          ref.invalidate(tilesProvider);
          Navigator.of(context).pop();
        },
      ),
      fullscreenDialog: true,
    ));
  }

  Future<void> _addGroupDialog(BuildContext context) async {
    final auth = ref.read(authProvider);
    if (auth is! AuthStateAuthenticated) return;
    final ctrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Create Group'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Group name'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Create')),
        ],
      ),
    );
    if (confirmed != true || ctrl.text.trim().isEmpty) return;
    try {
      await TsgAuthService.createGroup(
          accessToken: auth.accessToken, name: ctrl.text.trim());
      ref.invalidate(adminGroupsProvider);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Future<void> _addUserDialog(BuildContext context) async {
    final auth = ref.read(authProvider);
    if (auth is! AuthStateAuthenticated) return;

    // Build group list from already-fetched provider (role groups only)
    final rawGroups = ref.read(adminGroupsProvider).value ?? [];
    final groups = rawGroups
        .map((g) => _GroupOption(
              pk: g['pk'].toString(),
              name: g['name'] as String? ?? '',
            ))
        .where((g) => Role.fromGroupName(g.name) != Role.unknown)
        .toList();

    final result = await showDialog<_NewUserData>(
      context: context,
      builder: (_) => _CreateUserDialog(groups: groups),
    );
    if (result == null) return;
    try {
      final created = await TsgAuthService.createUser(
        accessToken: auth.accessToken,
        username: result.username,
        email: result.email,
        name: result.name,
        password: result.password,
      );
      // Assign the selected group immediately after creation
      if (result.groupPk.isNotEmpty) {
        final userPk = created['pk']?.toString() ?? '';
        if (userPk.isNotEmpty) {
          await TsgAuthService.setUserGroups(
            accessToken: auth.accessToken,
            userPk: userPk,
            groupIds: [int.parse(result.groupPk)],
          );
        }
      }
      ref.invalidate(adminUsersProvider);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('User created')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }
}

// ── Create User Dialog ────────────────────────────────────────────────────────

class _GroupOption {
  final String pk;
  final String name;
  const _GroupOption({required this.pk, required this.name});
}

class _NewUserData {
  final String username;
  final String email;
  final String name;
  final String password;
  final String groupPk;
  const _NewUserData(
      {required this.username,
      required this.email,
      required this.name,
      required this.password,
      required this.groupPk});
}

class _CreateUserDialog extends StatefulWidget {
  final List<_GroupOption> groups;
  const _CreateUserDialog({required this.groups});

  @override
  State<_CreateUserDialog> createState() => _CreateUserDialogState();
}

class _CreateUserDialogState extends State<_CreateUserDialog> {
  final _formKey = GlobalKey<FormState>();
  final _usernameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _pwCtrl = TextEditingController();
  late String _selectedGroupPk;

  @override
  void initState() {
    super.initState();
    // Default to 'engineer' group; fall back to first available
    final engineerGroup = widget.groups
        .where((g) => g.name.toLowerCase() == 'engineer')
        .firstOrNull;
    _selectedGroupPk =
        engineerGroup?.pk ?? widget.groups.firstOrNull?.pk ?? '';
  }

  @override
  void dispose() {
    _usernameCtrl.dispose();
    _emailCtrl.dispose();
    _nameCtrl.dispose();
    _pwCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Create User'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _usernameCtrl,
                decoration: const InputDecoration(labelText: 'Username *'),
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'Required' : null,
              ),
              TextFormField(
                controller: _emailCtrl,
                decoration: const InputDecoration(labelText: 'Email *'),
                keyboardType: TextInputType.emailAddress,
                validator: (v) =>
                    v == null || !v.contains('@') ? 'Valid email required' : null,
              ),
              TextFormField(
                controller: _nameCtrl,
                decoration: const InputDecoration(labelText: 'Display name'),
              ),
              TextFormField(
                controller: _pwCtrl,
                decoration: const InputDecoration(labelText: 'Password *'),
                obscureText: true,
                validator: (v) =>
                    v == null || v.length < 6 ? 'Min 6 characters' : null,
              ),
              if (widget.groups.isNotEmpty) ...
                [
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    value: _selectedGroupPk,
                    decoration: const InputDecoration(labelText: 'Group / Role *'),
                    items: widget.groups
                        .map((g) => DropdownMenuItem(
                              value: g.pk,
                              child: Text(
                                g.name[0].toUpperCase() + g.name.substring(1),
                              ),
                            ))
                        .toList(),
                    onChanged: (v) {
                      if (v != null) setState(() => _selectedGroupPk = v);
                    },
                    validator: (v) =>
                        v == null || v.isEmpty ? 'Select a group' : null,
                  ),
                ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        TextButton(
          onPressed: () {
            if (!_formKey.currentState!.validate()) return;
            Navigator.pop(
              context,
              _NewUserData(
                username: _usernameCtrl.text.trim(),
                email: _emailCtrl.text.trim(),
                name: _nameCtrl.text.trim(),
                password: _pwCtrl.text,
                groupPk: _selectedGroupPk,
              ),
            );
          },
          child: const Text('Create'),
        ),
      ],
    );
  }
}

// ── Tiles Tab ────────────────────────────────────────────────────────────────

class _TilesTab extends ConsumerWidget {
  const _TilesTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tilesAsync = ref.watch(adminTilesProvider);
    final auth = ref.watch(authProvider);

    return tilesAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (tiles) => tiles.isEmpty
          ? const Center(child: Text('No tiles yet. Tap + to add one.'))
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: tiles.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final tile = tiles[i];
                return ListTile(
                  leading: const Icon(Icons.web_rounded),
                  title: Text(tile.name),
                  subtitle:
                      Text(tile.launchUrl, overflow: TextOverflow.ellipsis),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit_rounded),
                        onPressed: () => _editTile(context, ref, tile),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_rounded,
                            color: Colors.red),
                        onPressed: () =>
                            _confirmDelete(context, ref, tile, auth),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }

  void _editTile(BuildContext context, WidgetRef ref, TileModel tile) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => TileForm(
        existing: tile,
        onSaved: () {
          ref.invalidate(adminTilesProvider);
          ref.invalidate(tilesProvider);
          Navigator.of(context).pop();
        },
      ),
      fullscreenDialog: true,
    ));
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref,
      TileModel tile, AuthState auth) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Tile'),
        content: Text('Delete "${tile.name}"? This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child:
                  const Text('Delete', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirm != true) return;
    if (auth is AuthStateAuthenticated) {
      await TsgAuthService.deleteTile(auth.accessToken, tile.slug);
      ref.invalidate(adminTilesProvider);
      ref.invalidate(tilesProvider);
    }
  }
}

// ── Groups Tab ───────────────────────────────────────────────────────────────

class _GroupsTab extends ConsumerWidget {
  final Role callerRole;
  const _GroupsTab({required this.callerRole});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groupsAsync = ref.watch(adminGroupsProvider);

    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(adminGroupsProvider),
      child: groupsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (groups) => groups.isEmpty
            ? const Center(child: Text('No groups found.'))
            : ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: groups.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, i) {
                  final group = groups[i];
                  return ListTile(
                    leading: const Icon(Icons.group_rounded),
                    title: Text(group['name'] as String),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (callerRole.canManageGroups) ...[
                          IconButton(
                            icon: const Icon(Icons.edit_rounded),
                            tooltip: 'Rename group',
                            onPressed: () =>
                                _renameDialog(context, ref, group),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_rounded,
                                color: Colors.red),
                            tooltip: 'Delete group',
                            onPressed: () =>
                                _deleteDialog(context, ref, group),
                          ),
                        ],
                        const Icon(Icons.chevron_right),
                      ],
                    ),
                    onTap: () => _openDetail(context, group),
                  );
                },
              ),
      ),
    );
  }

  Future<void> _renameDialog(BuildContext context, WidgetRef ref,
      Map<String, dynamic> group) async {
    final auth = ref.read(authProvider);
    if (auth is! AuthStateAuthenticated) return;
    final ctrl = TextEditingController(text: group['name'] as String);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Rename Group'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'New name'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Rename')),
        ],
      ),
    );
    if (confirmed != true || ctrl.text.trim().isEmpty) return;
    try {
      await TsgAuthService.renameGroup(
        accessToken: auth.accessToken,
        groupId: group['pk'] as String,
        newName: ctrl.text.trim(),
      );
      ref.invalidate(adminGroupsProvider);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Future<void> _deleteDialog(BuildContext context, WidgetRef ref,
      Map<String, dynamic> group) async {
    final auth = ref.read(authProvider);
    if (auth is! AuthStateAuthenticated) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Group'),
        content: Text('Delete "${group['name']}"? This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await TsgAuthService.deleteGroup(
          accessToken: auth.accessToken, groupId: group['pk'] as String);
      ref.invalidate(adminGroupsProvider);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  void _openDetail(BuildContext context, Map<String, dynamic> group) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => _GroupDetailPage(
        groupId: group['pk'] as String,
        groupName: group['name'] as String,
        callerRole: callerRole,
      ),
    ));
  }
}

// ── Group Detail Page (Tiles + Members) ───────────────────────────────────────

class _GroupDetailPage extends ConsumerStatefulWidget {
  final String groupId;
  final String groupName;
  final Role callerRole;

  const _GroupDetailPage({
    required this.groupId,
    required this.groupName,
    required this.callerRole,
  });

  @override
  ConsumerState<_GroupDetailPage> createState() => _GroupDetailPageState();
}

class _GroupDetailPageState extends ConsumerState<_GroupDetailPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  Set<String> _assignedSlugs = {};
  List<TileModel> _allTiles = [];
  List<Map<String, dynamic>> _groupUsers = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final auth = ref.read(authProvider);
      if (auth is! AuthStateAuthenticated) return;

      final results = await Future.wait([
        TsgAuthService.fetchGroupDetail(auth.accessToken, widget.groupId),
        TsgAuthService.fetchAllTiles(auth.accessToken),
      ]);

      final detail = results[0] as Map<String, dynamic>;
      final allTiles = results[1] as List<TileModel>;
      final assignedTiles =
          (detail['tiles'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
      final slugs = assignedTiles.map((t) => t['slug'] as String).toSet();
      final users =
          (detail['users'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();

      setState(() {
        _assignedSlugs = slugs;
        _allTiles = allTiles;
        _groupUsers = users;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _toggleTile(TileModel tile) async {
    final auth = ref.read(authProvider);
    if (auth is! AuthStateAuthenticated) return;
    final isAssigned = _assignedSlugs.contains(tile.slug);
    try {
      if (isAssigned) {
        await TsgAuthService.removeTileFromGroup(
          accessToken: auth.accessToken,
          groupId: widget.groupId,
          tileId: tile.pk,
        );
        setState(() => _assignedSlugs.remove(tile.slug));
      } else {
        await TsgAuthService.assignTileToGroup(
          accessToken: auth.accessToken,
          groupId: widget.groupId,
          tileSlug: tile.slug,
        );
        setState(() => _assignedSlugs.add(tile.slug));
      }
      ref.invalidate(tilesProvider);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Future<void> _removeUser(Map<String, dynamic> user) async {
    final auth = ref.read(authProvider);
    if (auth is! AuthStateAuthenticated) return;
    try {
      await TsgAuthService.removeUserFromGroup(
        accessToken: auth.accessToken,
        groupId: widget.groupId,
        userId: user['pk'] as String,
      );
      setState(() =>
          _groupUsers.removeWhere((u) => u['pk'] == user['pk']));
      ref.invalidate(adminUsersProvider);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Future<void> _editUser(Map<String, dynamic> user) async {
    final auth = ref.read(authProvider);
    if (auth is! AuthStateAuthenticated) return;
    final nameCtrl = TextEditingController(text: user['name'] as String? ?? '');
    final pwCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Edit ${user['username']}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(labelText: 'Display name'),
            ),
            TextField(
              controller: pwCtrl,
              decoration: const InputDecoration(labelText: 'New password (leave blank to keep)'),
              obscureText: true,
            ),
          ],
        ),
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
    if (confirmed != true) return;
    final updates = <String, dynamic>{};
    if (nameCtrl.text.trim().isNotEmpty) updates['name'] = nameCtrl.text.trim();
    if (pwCtrl.text.isNotEmpty) updates['password'] = pwCtrl.text;
    if (updates.isEmpty) return;
    try {
      final result = await TsgAuthService.updateUser(
        accessToken: auth.accessToken,
        userPk: user['pk'] as String,
        name: updates['name'] as String?,
        password: updates['password'] as String?,
      );
      setState(() {
        final idx = _groupUsers.indexWhere((u) => u['pk'] == user['pk']);
        if (idx != -1) _groupUsers[idx] = {..._groupUsers[idx], ...result};
      });
      ref.invalidate(adminUsersProvider);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Future<void> _addMemberDialog() async {
    final auth = ref.read(authProvider);
    if (auth is! AuthStateAuthenticated) return;
    final allUsers = await TsgAuthService.fetchUsers(auth.accessToken);
    final groupPks = _groupUsers.map((u) => u['pk'].toString()).toSet();
    final eligible =
        allUsers.where((u) => !groupPks.contains(u['pk'].toString())).toList();

    if (!mounted) return;
    final selected = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _UserPickerDialog(users: eligible),
    );
    if (selected == null) return;
    try {
      await TsgAuthService.addUserToGroup(
        accessToken: auth.accessToken,
        groupId: widget.groupId,
        userId: int.parse(selected['pk'].toString()),
      );
      setState(() => _groupUsers.add({
            'pk': selected['pk'].toString(),
            'username': selected['username'],
            'name': selected['name'],
            'email': selected['email'],
          }));
      ref.invalidate(adminUsersProvider);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.groupName),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.grid_view_rounded), text: 'Tiles'),
            Tab(icon: Icon(Icons.people_rounded), text: 'Members'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text('Error: $_error'))
              : TabBarView(
                  controller: _tabController,
                  children: [
                    _buildTilesTab(),
                    _buildMembersTab(),
                  ],
                ),
    );
  }

  Widget _buildTilesTab() {
    if (_allTiles.isEmpty) {
      return const Center(child: Text('No tiles exist yet.'));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: _allTiles.length,
      itemBuilder: (context, i) {
        final tile = _allTiles[i];
        final assigned = _assignedSlugs.contains(tile.slug);
        return CheckboxListTile(
          value: assigned,
          onChanged: (_) => _toggleTile(tile),
          title: Text(tile.name),
          subtitle: Text(tile.launchUrl, overflow: TextOverflow.ellipsis),
          secondary: Icon(
            assigned ? Icons.check_circle_rounded : Icons.circle_outlined,
            color: assigned ? Theme.of(context).colorScheme.primary : null,
          ),
        );
      },
    );
  }

  Widget _buildMembersTab() {
    return Column(
      children: [
        if (widget.callerRole.canManageUsers)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.person_add_rounded),
                label: const Text('Add member'),
                onPressed: _addMemberDialog,
              ),
            ),
          ),
        Expanded(
          child: _groupUsers.isEmpty
              ? const Center(child: Text('No members in this group.'))
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: _groupUsers.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final user = _groupUsers[i];
                    final displayName =
                        (user['name'] as String? ?? '').isNotEmpty
                            ? user['name'] as String
                            : user['username'] as String? ?? '';
                    return ListTile(
                      leading: const CircleAvatar(
                          child: Icon(Icons.person_rounded)),
                      title: Text(displayName),
                      subtitle: Text(user['email'] as String? ??
                          user['username'] as String? ??
                          ''),
                      trailing: widget.callerRole.canManageUsers
                          ? Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.edit_rounded),
                                  tooltip: 'Edit user',
                                  onPressed: () => _editUser(user),
                                ),
                                IconButton(
                                  icon: const Icon(
                                      Icons.remove_circle_outline,
                                      color: Colors.red),
                                  tooltip: 'Remove from group',
                                  onPressed: () => _removeUser(user),
                                ),
                              ],
                            )
                          : null,
                    );
                  },
                ),
        ),
      ],
    );
  }
}

// ── User Picker Dialog ────────────────────────────────────────────────────────

class _UserPickerDialog extends StatefulWidget {
  final List<Map<String, dynamic>> users;
  const _UserPickerDialog({required this.users});

  @override
  State<_UserPickerDialog> createState() => _UserPickerDialogState();
}

class _UserPickerDialogState extends State<_UserPickerDialog> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final filtered = widget.users.where((u) {
      final q = _query.toLowerCase();
      return (u['username'] as String? ?? '').toLowerCase().contains(q) ||
          (u['name'] as String? ?? '').toLowerCase().contains(q) ||
          (u['email'] as String? ?? '').toLowerCase().contains(q);
    }).toList();

    return AlertDialog(
      title: const Text('Add member'),
      contentPadding: const EdgeInsets.fromLTRB(8, 12, 8, 0),
      content: SizedBox(
        width: 320,
        height: 400,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: TextField(
                decoration: const InputDecoration(
                    hintText: 'Search users...',
                    prefixIcon: Icon(Icons.search)),
                onChanged: (v) => setState(() => _query = v),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: filtered.isEmpty
                  ? const Center(child: Text('No users found'))
                  : ListView.builder(
                      itemCount: filtered.length,
                      itemBuilder: (context, i) {
                        final u = filtered[i];
                        final name =
                            (u['name'] as String? ?? '').isNotEmpty
                                ? u['name'] as String
                                : u['username'] as String? ?? '';
                        return ListTile(
                          title: Text(name),
                          subtitle:
                              Text(u['username'] as String? ?? ''),
                          onTap: () => Navigator.pop(context, u),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
      ],
    );
  }
}

// ── Settings Tab ─────────────────────────────────────────────────────────────

class _SettingsTab extends ConsumerStatefulWidget {
  final Role callerRole;
  const _SettingsTab({required this.callerRole});

  @override
  ConsumerState<_SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends ConsumerState<_SettingsTab> {
  late final TextEditingController _urlCtrl;
  late final TextEditingController _qiBaseCtrl;
  late final TextEditingController _qiKeyCtrl;
  bool _saving = false;
  bool _testing = false;
  String? _testResult;
  bool _testSuccess = false;
  bool _qiSaving = false;

  bool get _canEdit => widget.callerRole == Role.superadmin;

  @override
  void initState() {
    super.initState();
    _urlCtrl = TextEditingController(text: AppConfig.tsgAuthBaseUrl);
    _qiBaseCtrl = TextEditingController(text: AppConfig.quickInfoBase);
    _qiKeyCtrl = TextEditingController(text: AppConfig.quickInfoKey);
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    _qiBaseCtrl.dispose();
    _qiKeyCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final url = _urlCtrl.text.trim();
    if (url.isEmpty) return;
    setState(() {
      _saving = true;
      _testResult = null;
    });
    try {
      await ServerConfigService.setBaseUrl(url);
      ref.read(serverUrlProvider.notifier).state = url;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Server URL saved')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _testConnection() async {
    final url = _urlCtrl.text.trim();
    if (url.isEmpty) return;
    setState(() {
      _testing = true;
      _testResult = null;
    });
    try {
      // Temporarily override for the health check without persisting
      final original = AppConfig.tsgAuthBaseUrl;
      AppConfig.tsgAuthBaseUrl = url;
      try {
        await TsgAuthService.healthCheck();
        setState(() {
          _testResult = 'Connected successfully';
          _testSuccess = true;
        });
      } finally {
        AppConfig.tsgAuthBaseUrl = original;
      }
    } catch (e) {
      setState(() {
        _testResult = 'Failed: $e';
        _testSuccess = false;
      });
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  Future<void> _reset() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Reset to Default'),
        content: Text(
            'Reset server URL to the compile-time default?\n\n${AppConfig.defaultBaseUrl}'),
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
    if (confirmed != true) return;
    await ServerConfigService.resetToDefault();
    ref.read(serverUrlProvider.notifier).state = AppConfig.defaultBaseUrl;
    _urlCtrl.text = AppConfig.defaultBaseUrl;
    setState(() => _testResult = null);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Reset to default URL')),
      );
    }
  }

  Future<void> _saveQuickInfo() async {
    final base = _qiBaseCtrl.text.trim();
    final key = _qiKeyCtrl.text.trim();
    if (base.isEmpty || key.isEmpty) return;
    setState(() => _qiSaving = true);
    try {
      await ServerConfigService.setQuickInfoBase(base);
      await ServerConfigService.setQuickInfoKey(key);
      ref.read(quickInfoBaseProvider.notifier).state = base;
      ref.read(quickInfoKeyProvider.notifier).state = key;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Quick Info settings saved')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _qiSaving = false);
    }
  }

  Future<void> _resetQuickInfo() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Reset Quick Info to Default'),
        content: const Text(
            'Reset the Quick Info webhook URL and API key to their compile-time defaults?'),
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
    if (confirmed != true) return;
    await ServerConfigService.resetQuickInfoToDefault();
    ref.read(quickInfoBaseProvider.notifier).state = AppConfig.defaultQuickInfoBase;
    ref.read(quickInfoKeyProvider.notifier).state = AppConfig.defaultQuickInfoKey;
    _qiBaseCtrl.text = AppConfig.defaultQuickInfoBase;
    _qiKeyCtrl.text = AppConfig.defaultQuickInfoKey;
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Quick Info reset to defaults')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        // ── Header ───────────────────────────────────────────────────────────
        Row(
          children: [
            Icon(Icons.dns_rounded, color: theme.colorScheme.primary),
            const SizedBox(width: 10),
            Text('Server Configuration',
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold)),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          _canEdit
              ? 'Only superadmin can change the server URL.'
              : 'View-only. Contact a superadmin to change the server URL.',
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 24),

        // ── URL field ─────────────────────────────────────────────────────────
        TextField(
          controller: _urlCtrl,
          readOnly: !_canEdit,
          keyboardType: TextInputType.url,
          autocorrect: false,
          decoration: InputDecoration(
            labelText: 'Auth Server Base URL',
            hintText: 'http://192.168.1.x:8000',
            border: const OutlineInputBorder(),
            suffixIcon: _canEdit
                ? IconButton(
                    icon: const Icon(Icons.clear),
                    tooltip: 'Clear',
                    onPressed: () => _urlCtrl.clear(),
                  )
                : const Icon(Icons.lock_outline, size: 18),
          ),
          onChanged: (_) => setState(() => _testResult = null),
        ),
        const SizedBox(height: 16),

        // ── Test result banner ────────────────────────────────────────────────
        if (_testResult != null)
          Container(
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: _testSuccess
                  ? Colors.green.withValues(alpha: 0.12)
                  : Colors.red.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: _testSuccess ? Colors.green : Colors.red,
                width: 1,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  _testSuccess ? Icons.check_circle_outline : Icons.error_outline,
                  color: _testSuccess ? Colors.green : Colors.red,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _testResult!,
                    style: TextStyle(
                      color: _testSuccess ? Colors.green : Colors.red,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ),

        // ── Action buttons ────────────────────────────────────────────────────
        Row(
          children: [
            // Test connection — available to both roles
            Expanded(
              child: OutlinedButton.icon(
                icon: _testing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.wifi_tethering_rounded),
                label: const Text('Test Connection'),
                onPressed: _testing ? null : _testConnection,
              ),
            ),
            if (_canEdit) ...[
              const SizedBox(width: 12),
              // Save
              Expanded(
                child: FilledButton.icon(
                  icon: _saving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.save_rounded),
                  label: const Text('Save'),
                  onPressed: _saving ? null : _save,
                ),
              ),
            ],
          ],
        ),

        if (_canEdit) ...[
          const SizedBox(height: 8),
          TextButton.icon(
            icon: const Icon(Icons.restore_rounded, size: 18),
            label: const Text('Reset to Default'),
            style: TextButton.styleFrom(
                foregroundColor: theme.colorScheme.error),
            onPressed: _reset,
          ),
        ],

        const SizedBox(height: 32),
        const Divider(),
        const SizedBox(height: 12),

        // ── Current active URL (read from provider) ───────────────────────────
        Consumer(builder: (context, ref, _) {
          final current = ref.watch(serverUrlProvider);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Active URL',
                  style: theme.textTheme.labelSmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              const SizedBox(height: 4),
              SelectableText(
                current,
                style: theme.textTheme.bodyMedium?.copyWith(
                    fontFamily: 'monospace', fontWeight: FontWeight.w500),
              ),
            ],
          );
        }),

        const SizedBox(height: 40),

        // ── Quick Info API ────────────────────────────────────────────────────
        Row(
          children: [
            Icon(Icons.bar_chart_rounded, color: theme.colorScheme.primary),
            const SizedBox(width: 10),
            Text('Quick Info API',
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold)),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          _canEdit
              ? 'Webhook URL and API key for the tile quick-info panel.'
              : 'View-only. Contact a superadmin to change Quick Info settings.',
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 20),

        TextField(
          controller: _qiBaseCtrl,
          readOnly: !_canEdit,
          keyboardType: TextInputType.url,
          autocorrect: false,
          decoration: InputDecoration(
            labelText: 'Webhook Base URL',
            hintText: 'http://host:5555/webhook/path',
            border: const OutlineInputBorder(),
            suffixIcon: _canEdit
                ? IconButton(
                    icon: const Icon(Icons.clear),
                    tooltip: 'Clear',
                    onPressed: () => _qiBaseCtrl.clear(),
                  )
                : const Icon(Icons.lock_outline, size: 18),
          ),
        ),
        const SizedBox(height: 16),

        TextField(
          controller: _qiKeyCtrl,
          readOnly: !_canEdit,
          autocorrect: false,
          decoration: InputDecoration(
            labelText: 'API Key',
            hintText: 'e03fc535...',
            border: const OutlineInputBorder(),
            suffixIcon: _canEdit
                ? IconButton(
                    icon: const Icon(Icons.clear),
                    tooltip: 'Clear',
                    onPressed: () => _qiKeyCtrl.clear(),
                  )
                : const Icon(Icons.lock_outline, size: 18),
          ),
        ),
        const SizedBox(height: 16),

        if (_canEdit) ...[
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  icon: _qiSaving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.save_rounded),
                  label: const Text('Save'),
                  onPressed: _qiSaving ? null : _saveQuickInfo,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            icon: const Icon(Icons.restore_rounded, size: 18),
            label: const Text('Reset to Default'),
            style: TextButton.styleFrom(
                foregroundColor: theme.colorScheme.error),
            onPressed: _resetQuickInfo,
          ),
        ],

        const SizedBox(height: 32),
        const Divider(),
        const SizedBox(height: 12),

        Consumer(builder: (context, ref, _) {
          final base = ref.watch(quickInfoBaseProvider);
          final key = ref.watch(quickInfoKeyProvider);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Active Webhook URL',
                  style: theme.textTheme.labelSmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              const SizedBox(height: 4),
              SelectableText(
                base,
                style: theme.textTheme.bodyMedium?.copyWith(
                    fontFamily: 'monospace', fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 12),
              Text('Active API Key',
                  style: theme.textTheme.labelSmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              const SizedBox(height: 4),
              SelectableText(
                key,
                style: theme.textTheme.bodyMedium?.copyWith(
                    fontFamily: 'monospace', fontWeight: FontWeight.w500),
              ),
            ],
          );
        }),
      ],
    );
  }
}

