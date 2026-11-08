import 'package:sportshub_core/sportshub_core.dart';

/// gym_subscriptions.status. A member asks for a plan (pending); the gym's
/// staff confirm the payment (active); it runs out (expired) or is called
/// off before it starts (cancelled).
abstract final class SubscriptionStatus {
  static const pending = 'pending';
  static const active = 'active';
  static const expired = 'expired';
  static const cancelled = 'cancelled';
}

/// A membership plan a gym sells: 'Monthly', 30 days, Nu. 1,500.
class GymPlan {
  final String id;
  final String venueId;
  final String name;
  final String? description;
  final int durationDays;
  final int price;
  final bool isActive;

  const GymPlan({
    required this.id,
    required this.venueId,
    required this.name,
    required this.durationDays,
    required this.price,
    required this.isActive,
    this.description,
  });

  factory GymPlan.fromJson(Map<String, dynamic> json) => GymPlan(
        id: json['id'] as String,
        venueId: json['venue_id'] as String,
        name: json['name'] as String,
        description: json['description'] as String?,
        durationDays: json['duration_days'] as int,
        price: (json['price'] as num).toInt(),
        isActive: json['is_active'] as bool? ?? true,
      );
}

/// One membership (or a request for one) of one member at one gym. The
/// plan's name, length and price are copied when it's requested, so later
/// price changes don't touch it.
class GymSubscription {
  final String id;
  final String venueId;

  /// Who it is for: their account id, or for a member registered at the
  /// front desk their gym_members id ([gymMemberId] too). Either way one
  /// person's memberships share it.
  final String memberId;

  /// Set for a member registered at the front desk (no SportsHub account).
  final String? gymMemberId;
  final String? planId;
  final String planName;
  final int durationDays;
  final int price;
  final String status;
  final DateTime? startDate;
  final DateTime? endDate;
  final DateTime requestedAt;
  final DateTime? activatedAt;

  /// Joined in when the reader may see them.
  final String? gymName;
  final String? memberName;
  final String? memberPhone;
  final String? memberCode;

  const GymSubscription({
    required this.id,
    required this.venueId,
    required this.memberId,
    this.gymMemberId,
    required this.planName,
    required this.durationDays,
    required this.price,
    required this.status,
    required this.requestedAt,
    this.planId,
    this.startDate,
    this.endDate,
    this.activatedAt,
    this.gymName,
    this.memberName,
    this.memberPhone,
    this.memberCode,
  });

  bool get isPending => status == SubscriptionStatus.pending;

  /// For a member registered at the front desk.
  bool get isRegistered => gymMemberId != null;

  /// Paid and covering [today].
  bool isCurrentOn(DateTime today) =>
      status == SubscriptionStatus.active && !startDate!.isAfter(today) && !endDate!.isBefore(today);

  /// Paid, starting after [today] (a renewal).
  bool isUpcomingOn(DateTime today) => status == SubscriptionStatus.active && startDate!.isAfter(today);

  /// Days it still covers, [today] included: 1 on its last day.
  int daysLeftOn(DateTime today) => endDate == null ? 0 : BhutanTime.daysBetween(today, endDate!) + 1;

  /// How much of it has passed, 0 to 1.
  double progressOn(DateTime today) {
    if (startDate == null || endDate == null) return 0;
    final total = BhutanTime.daysBetween(startDate!, endDate!) + 1;
    final used = BhutanTime.daysBetween(startDate!, today) + 1;
    return (used / total).clamp(0, 1).toDouble();
  }

  String get memberDisplayName => (memberName == null || memberName!.trim().isEmpty) ? 'Member' : memberName!.trim();

  /// A gym_subscriptions row, with `member:profiles(...)` or
  /// `registered:gym_members(full_name, phone, code)` when selected.
  factory GymSubscription.fromJson(Map<String, dynamic> json) {
    final member = json['member'] as Map<String, dynamic>? ?? json['registered'] as Map<String, dynamic>?;
    final gym = json['gym'] as Map<String, dynamic>?;
    DateTime? date(String key) => json[key] == null ? null : BhutanTime.parseDate(json[key] as String);
    DateTime? moment(String key) => json[key] == null ? null : DateTime.parse(json[key] as String);
    return GymSubscription(
      id: json['id'] as String,
      venueId: json['venue_id'] as String,
      memberId: (json['member_id'] ?? json['gym_member_id']) as String,
      gymMemberId: json['gym_member_id'] as String?,
      planId: json['plan_id'] as String?,
      planName: json['plan_name'] as String,
      durationDays: json['duration_days'] as int,
      price: (json['price'] as num).toInt(),
      status: json['status'] as String,
      startDate: date('start_date'),
      endDate: date('end_date'),
      requestedAt: DateTime.parse(json['requested_at'] as String),
      activatedAt: moment('activated_at'),
      gymName: gym?['name'] as String?,
      memberName: member?['full_name'] as String?,
      memberPhone: member?['phone'] as String?,
      memberCode: (member?['member_code'] ?? member?['code']) as String?,
    );
  }
}

/// A member's visit, recorded by the gym's staff.
class GymCheckIn {
  final String id;
  final String venueId;

  /// Their account id, or their gym_members id ([gymMemberId] too).
  final String memberId;
  final String? gymMemberId;
  final DateTime checkedInAt;
  final String? gymName;
  final String? memberName;

  const GymCheckIn({
    required this.id,
    required this.venueId,
    required this.memberId,
    required this.checkedInAt,
    this.gymMemberId,
    this.gymName,
    this.memberName,
  });

  factory GymCheckIn.fromJson(Map<String, dynamic> json) => GymCheckIn(
        id: json['id'] as String,
        venueId: json['venue_id'] as String,
        memberId: (json['member_id'] ?? json['gym_member_id']) as String,
        gymMemberId: json['gym_member_id'] as String?,
        checkedInAt: DateTime.parse(json['checked_in_at'] as String),
        gymName: (json['gym'] as Map<String, dynamic>?)?['name'] as String?,
        memberName: ((json['member'] ?? json['registered']) as Map<String, dynamic>?)?['full_name'] as String?,
      );
}

/// What gym_check_in answers: who it was and how long they have left.
class CheckInResult {
  final String memberName;
  final String? memberCode;
  final String planName;
  final DateTime endDate;
  final int daysLeft;

  /// Check-ins earlier today (they may have come back, or been scanned twice).
  final int earlierToday;

  /// For a member registered at the front desk: who, their photo (to see
  /// it's them) and what the desk should know about their health.
  final String? gymMemberId;
  final String? photoPath;
  final String? medicalNotes;

  const CheckInResult({
    required this.memberName,
    required this.planName,
    required this.endDate,
    required this.daysLeft,
    required this.earlierToday,
    this.memberCode,
    this.gymMemberId,
    this.photoPath,
    this.medicalNotes,
  });

  factory CheckInResult.fromJson(Map<String, dynamic> json) => CheckInResult(
        memberName: (json['member_name'] as String?)?.trim().isNotEmpty == true ? json['member_name'] as String : 'Member',
        memberCode: json['member_code'] as String?,
        planName: json['plan_name'] as String,
        endDate: BhutanTime.parseDate(json['end_date'] as String),
        daysLeft: json['days_left'] as int,
        earlierToday: json['earlier_today'] as int? ?? 0,
        gymMemberId: json['gym_member_id'] as String?,
        photoPath: json['photo_path'] as String?,
        medicalNotes: json['medical_notes'] as String?,
      );
}

/// A gym's numbers today, for its Manage page.
class GymDashboard {
  final int pending;
  final int active;
  final int expiringSoon;
  final int checkInsToday;

  /// Null for front-desk staff, who don't see income.
  final int? incomeThisMonth;

  const GymDashboard({
    required this.pending,
    required this.active,
    required this.expiringSoon,
    required this.checkInsToday,
    this.incomeThisMonth,
  });

  factory GymDashboard.fromJson(Map<String, dynamic> json) => GymDashboard(
        pending: json['pending'] as int? ?? 0,
        active: json['active'] as int? ?? 0,
        expiringSoon: json['expiring_soon'] as int? ?? 0,
        checkInsToday: json['check_ins_today'] as int? ?? 0,
        incomeThisMonth: (json['income_this_month'] as num?)?.toInt(),
      );
}
