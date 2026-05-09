enum Role {
  superadmin,
  admin,
  head,
  supervisor,
  sme,
  engineer,
  trainee,
  unknown;

  static Role fromGroupName(String name) {
    switch (name.toLowerCase()) {
      case 'superadmin':
        return Role.superadmin;
      case 'admin':
        return Role.admin;
      case 'head':
        return Role.head;
      case 'supervisor':
        return Role.supervisor;
      case 'sme':
        return Role.sme;
      case 'engineer':
        return Role.engineer;
      case 'trainee':
        return Role.trainee;
      default:
        return Role.unknown;
    }
  }

  int get level {
    switch (this) {
      case Role.superadmin:
        return 7;
      case Role.admin:
        return 6;
      case Role.head:
        return 5;
      case Role.supervisor:
        return 4;
      case Role.sme:
        return 3;
      case Role.engineer:
        return 2;
      case Role.trainee:
        return 1;
      case Role.unknown:
        return 0;
    }
  }

  /// Can the user access the admin panel at all?
  /// superadmin, admin, head, sme, supervisor
  bool get canAccessAdmin => level >= Role.sme.level;

  /// Can create/rename/delete groups?
  /// superadmin, admin, head
  bool get canManageGroups => level >= Role.head.level;

  /// Can add/deactivate/delete users, reset passwords, assign tiles?
  /// superadmin, admin, head, sme, supervisor
  bool get canManageUsers => level >= Role.sme.level;

  /// Can add/delete/assign tiles?
  /// superadmin, admin, head, sme, supervisor
  bool get canManageTiles => level >= Role.sme.level;

  /// Can promote a user to admin or superadmin?
  /// superadmin only
  bool get canEscalateToAdmin => this == Role.superadmin;

  /// Can this user modify a target user of the given role?
  /// Superadmin can modify anyone. Others cannot touch admin-or-above.
  bool canModifyRole(Role targetRole) {
    if (this == Role.superadmin) return true;
    return targetRole.level < Role.admin.level;
  }
}

