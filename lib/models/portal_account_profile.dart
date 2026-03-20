class PortalAccountProfile {
  const PortalAccountProfile({
    required this.fullName,
    required this.identity,
    required this.organization,
    required this.department,
    required this.avatarPath,
    this.portalUserId,
  });

  factory PortalAccountProfile.fromPortalJson(Map<String, dynamic> json) {
    return PortalAccountProfile(
      fullName: _stringOf(json['username']),
      identity: _stringOf(json['jobs']),
      organization: _stringOf(json['subcompanyname']),
      department: _stringOf(json['deptname']),
      avatarPath: _stringOf(json['icon']),
      portalUserId: _intOf(json['userid']),
    );
  }

  final String fullName;
  final String identity;
  final String organization;
  final String department;
  final String avatarPath;
  final int? portalUserId;

  String get majorName => department.isNotEmpty ? department : organization;

  bool get isEmpty =>
      fullName.isEmpty &&
      identity.isEmpty &&
      organization.isEmpty &&
      department.isEmpty;

  static String _stringOf(dynamic value) {
    if (value is String) {
      return value.trim();
    }
    return '';
  }

  static int? _intOf(dynamic value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    if (value is String) {
      return int.tryParse(value.trim());
    }
    return null;
  }
}
