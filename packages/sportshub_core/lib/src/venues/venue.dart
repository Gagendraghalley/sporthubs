/// venues.verification_status: a new venue waits for the SportsHub team,
/// who verify it (it goes live) or send it back with a note.
abstract final class VerificationStatus {
  static const pending = 'pending';
  static const verified = 'verified';
  static const rejected = 'rejected';
}

/// venue_staff.role: who runs a venue, as a key of the roles table. Per
/// venue, not across the platform: a gym's owner can be a member somewhere
/// else. These come with SportsHub; admins add more (Roles and permissions),
/// so what a role may do comes from its permissions, not its key.
abstract final class VenueRole {
  /// Always has every permission.
  static const owner = 'owner';
  static const manager = 'manager';

  /// Shown as 'Front desk'.
  static const staff = 'staff';
  static const trainer = 'trainer';

  /// Not a venue_staff role: a SportsHub super admin looking at any venue.
  static const admin = 'admin';

  /// The name of a role that comes with SportsHub; others show their own.
  static String label(String role) => switch (role) {
        owner => 'Owner',
        manager => 'Manager',
        staff => 'Front desk',
        trainer => 'Trainer',
        admin => 'SportsHub admin',
        _ => role,
      };

  /// Owners and super admins may do everything at a venue.
  static bool hasEverything(String role) => role == owner || role == admin;
}

/// Someone's place at a venue: their role there and what it lets them do.
class VenueAccess {
  final Venue venue;

  /// The role's key ([VenueRole]), or 'admin' for a super admin.
  final String role;
  final String roleName;

  /// The role's permission keys (VenuePermission, and the modules' own).
  final Set<String> permissions;

  VenueAccess(this.venue, this.role, {String? roleName, Set<String> permissions = const {}})
      : roleName = roleName ?? VenueRole.label(role),
        permissions = Set.unmodifiable(permissions);

  bool can(String permission) => VenueRole.hasEverything(role) || permissions.contains(permission);
}

/// A place on SportsHub: a gym today; more types as modules add them
/// (venue_types).
class Venue {
  final String id;
  final String type;
  final String name;
  final String? description;
  final String dzongkhag;
  final String? town;
  final String? address;
  final String? phone;
  final String? whatsapp;
  final double? latitude;
  final double? longitude;
  final List<String> photos;
  final String? paymentInfo;
  final String? cancellationPolicy;
  final String verificationStatus;
  final String? verificationNote;
  final double? ratingAverage;
  final int ratingCount;
  final String? createdBy;
  final DateTime createdAt;

  /// The business it belongs to (organisations): its roles are as that
  /// organisation has them.
  final String? organisationId;

  const Venue({
    required this.id,
    required this.type,
    required this.name,
    required this.dzongkhag,
    required this.verificationStatus,
    required this.createdAt,
    this.description,
    this.town,
    this.address,
    this.phone,
    this.whatsapp,
    this.latitude,
    this.longitude,
    this.photos = const [],
    this.paymentInfo,
    this.cancellationPolicy,
    this.verificationNote,
    this.ratingAverage,
    this.ratingCount = 0,
    this.createdBy,
    this.organisationId,
  });

  bool get isVerified => verificationStatus == VerificationStatus.verified;
  String? get coverPhoto => photos.isEmpty ? null : photos.first;
  bool get hasLocation => latitude != null && longitude != null;

  /// 'Changzamtog, Thimphu'.
  String get place => [if (town != null && town!.trim().isNotEmpty) town!.trim(), dzongkhag].join(', ');

  factory Venue.fromJson(Map<String, dynamic> json) => Venue(
        id: json['id'] as String,
        type: json['type'] as String,
        name: json['name'] as String,
        description: json['description'] as String?,
        dzongkhag: json['dzongkhag'] as String,
        town: json['town'] as String?,
        address: json['address'] as String?,
        phone: json['phone'] as String?,
        whatsapp: json['whatsapp'] as String?,
        latitude: (json['latitude'] as num?)?.toDouble(),
        longitude: (json['longitude'] as num?)?.toDouble(),
        photos: (json['photos'] as List?)?.cast<String>() ?? const [],
        paymentInfo: json['payment_info'] as String?,
        cancellationPolicy: json['cancellation_policy'] as String?,
        verificationStatus: json['verification_status'] as String? ?? VerificationStatus.pending,
        verificationNote: json['verification_note'] as String?,
        ratingAverage: (json['rating_average'] as num?)?.toDouble(),
        ratingCount: json['rating_count'] as int? ?? 0,
        createdBy: json['created_by'] as String?,
        createdAt: DateTime.parse(json['created_at'] as String),
        organisationId: json['organisation_id'] as String?,
      );
}

/// What the venue form sends (register_venue and update_venue).
class VenueDraft {
  final String type;
  final String name;
  final String? description;
  final String dzongkhag;
  final String? town;
  final String? address;
  final String? phone;
  final String? whatsapp;
  final String? paymentInfo;
  final String? cancellationPolicy;

  const VenueDraft({
    required this.type,
    required this.name,
    required this.dzongkhag,
    this.description,
    this.town,
    this.address,
    this.phone,
    this.whatsapp,
    this.paymentInfo,
    this.cancellationPolicy,
  });

  Map<String, dynamic> toJson() {
    String? clean(String? v) => (v == null || v.trim().isEmpty) ? null : v.trim();
    return {
      'type': type,
      'name': name.trim(),
      'description': clean(description),
      'dzongkhag': dzongkhag,
      'town': clean(town),
      'address': clean(address),
      'phone': clean(phone),
      'whatsapp': clean(whatsapp),
      'payment_info': clean(paymentInfo),
      'cancellation_policy': clean(cancellationPolicy),
    };
  }
}

/// A venue the signed-in user runs, with their role there and what it lets
/// them do (as the venue's organisation has the role).
class MyVenue {
  final Venue venue;
  final String role;
  final String roleName;
  final Set<String> permissions;

  /// The organisation the venue belongs to.
  final String? organisationName;

  MyVenue(this.venue, this.role, {String? roleName, this.permissions = const {}, this.organisationName})
      : roleName = roleName ?? VenueRole.label(role);

  VenueAccess get access => VenueAccess(venue, role, roleName: roleName, permissions: permissions);

  /// One of my_venues(): `{venue, role, role_name, organisation: {id, name},
  /// permissions}`. The database leaves out roles that are turned off.
  factory MyVenue.fromJson(Map<String, dynamic> json) => MyVenue(
        Venue.fromJson(json['venue'] as Map<String, dynamic>),
        json['role'] as String,
        roleName: json['role_name'] as String?,
        organisationName: (json['organisation'] as Map<String, dynamic>?)?['name'] as String?,
        permissions: {for (final p in (json['permissions'] as List? ?? const [])) p as String},
      );
}

/// Someone on a venue's staff list.
class VenueStaffMember {
  final String venueId;
  final String userId;
  final String role;
  final String roleName;
  final String name;
  final String? email;
  final String? phone;

  VenueStaffMember({
    required this.venueId,
    required this.userId,
    required this.role,
    required this.name,
    String? roleName,
    this.email,
    this.phone,
  }) : roleName = roleName ?? VenueRole.label(role);

  factory VenueStaffMember.fromJson(Map<String, dynamic> json) {
    final profile = json['profile'] as Map<String, dynamic>?;
    final name = (profile?['full_name'] as String?)?.trim() ?? '';
    return VenueStaffMember(
      venueId: json['venue_id'] as String,
      userId: json['user_id'] as String,
      role: json['role'] as String,
      roleName: (json['role_info'] as Map<String, dynamic>?)?['name'] as String?,
      name: name.isEmpty ? (profile?['email'] as String? ?? 'SportsHub member') : name,
      email: profile?['email'] as String?,
      phone: profile?['phone'] as String?,
    );
  }
}

/// A member's rating of a venue they have used.
class VenueReview {
  final String id;
  final String venueId;
  final String userId;
  final String reviewerName;
  final int rating;
  final String? comment;
  final DateTime createdAt;

  const VenueReview({
    required this.id,
    required this.venueId,
    required this.userId,
    required this.reviewerName,
    required this.rating,
    required this.createdAt,
    this.comment,
  });

  factory VenueReview.fromJson(Map<String, dynamic> json) => VenueReview(
        id: json['id'] as String,
        venueId: json['venue_id'] as String,
        userId: json['user_id'] as String,
        reviewerName: json['reviewer_name'] as String? ?? 'Member',
        rating: json['rating'] as int,
        comment: json['comment'] as String?,
        createdAt: DateTime.parse(json['created_at'] as String),
      );
}
