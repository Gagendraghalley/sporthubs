/// venues.verification_status: a new venue waits for the SportsHub team,
/// who verify it (it goes live) or send it back with a note.
abstract final class VerificationStatus {
  static const pending = 'pending';
  static const verified = 'verified';
  static const rejected = 'rejected';
}

/// venue_staff.role: who runs a venue. Per venue, not across the platform:
/// a gym's owner can be a member somewhere else.
abstract final class VenueRole {
  static const owner = 'owner';
  static const manager = 'manager';
  static const staff = 'staff';

  /// Not a venue_staff role: a SportsHub admin looking at any venue.
  static const admin = 'admin';

  /// Owners and managers change details, plans and prices, and see income.
  static bool canManage(String role) => role == owner || role == manager || role == admin;

  /// Only owners add or remove staff.
  static bool canEditStaff(String role) => role == owner || role == admin;

  static String label(String role) => switch (role) {
        owner => 'Owner',
        manager => 'Manager',
        staff => 'Staff',
        admin => 'Admin',
        _ => role,
      };
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

/// A venue the signed-in user runs, with their role there.
class MyVenue {
  final Venue venue;
  final String role;

  const MyVenue(this.venue, this.role);
}

/// Someone on a venue's staff list.
class VenueStaffMember {
  final String venueId;
  final String userId;
  final String role;
  final String name;
  final String? email;
  final String? phone;

  const VenueStaffMember({
    required this.venueId,
    required this.userId,
    required this.role,
    required this.name,
    this.email,
    this.phone,
  });

  factory VenueStaffMember.fromJson(Map<String, dynamic> json) {
    final profile = json['profile'] as Map<String, dynamic>?;
    final name = (profile?['full_name'] as String?)?.trim() ?? '';
    return VenueStaffMember(
      venueId: json['venue_id'] as String,
      userId: json['user_id'] as String,
      role: json['role'] as String,
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
