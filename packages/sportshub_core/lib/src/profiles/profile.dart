/// profiles.role: everyone is a user; admins are the SportsHub team, who
/// verify venues and turn modules on and off. Running a venue is not a
/// platform role: it's per venue (venue_staff).
abstract final class PlatformRole {
  static const user = 'user';
  static const admin = 'admin';
}

/// A row of profiles: one per account, made when the account is.
class Profile {
  final String id;
  final String fullName;
  final String? email;
  final String? phone;
  final String? dzongkhag;
  final String role;

  /// Short code gym staff can type at check-in instead of scanning
  /// ('4K7P9Q'). Shown under the member's QR code.
  final String memberCode;

  const Profile({
    required this.id,
    required this.fullName,
    required this.role,
    required this.memberCode,
    this.email,
    this.phone,
    this.dzongkhag,
  });

  bool get isAdmin => role == PlatformRole.admin;

  String get displayName => fullName.trim().isEmpty ? (email ?? 'SportsHub member') : fullName.trim();

  factory Profile.fromJson(Map<String, dynamic> json) => Profile(
        id: json['id'] as String,
        fullName: json['full_name'] as String? ?? '',
        email: json['email'] as String?,
        phone: json['phone'] as String?,
        dzongkhag: json['dzongkhag'] as String?,
        role: json['role'] as String? ?? PlatformRole.user,
        memberCode: json['member_code'] as String? ?? '',
      );
}
