import 'package:sportshub_core/sportshub_core.dart';

import 'gym_models.dart';

/// Blood groups the registration form offers (gym_members.blood_group).
const bloodGroups = ['A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-'];

/// How many months a package can be signed for, in the form's dropdown
/// (gym_add_membership takes 1 to 24).
const packageMonthOptions = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 18, 24];

/// A member registered at a gym's front desk (gym_members): no SportsHub
/// account needed. Their QR card holds [qrToken]; staff can also type
/// [code].
class GymMember {
  final String id;
  final String venueId;
  final String code;
  final String qrToken;
  final String fullName;
  final String phone;
  final String? email;
  final DateTime? dateOfBirth;
  final String? bloodGroup;
  final String? occupation;
  final int? dzongkhagId;
  final int? gewogId;
  final int? villageId;

  /// 'Chakhar, Chokhor, Bumthang', when the place's names are loaded.
  final String? placeName;
  final String? emergencyContactName;
  final String? emergencyContactPhone;
  final String? medicalNotes;
  final String? photoPath;
  final DateTime joinedOn;
  final DateTime createdAt;

  const GymMember({
    required this.id,
    required this.venueId,
    required this.code,
    required this.qrToken,
    required this.fullName,
    required this.phone,
    required this.joinedOn,
    required this.createdAt,
    this.email,
    this.dateOfBirth,
    this.bloodGroup,
    this.occupation,
    this.dzongkhagId,
    this.gewogId,
    this.villageId,
    this.placeName,
    this.emergencyContactName,
    this.emergencyContactPhone,
    this.medicalNotes,
    this.photoPath,
  });

  /// What the form edits.
  MemberDetails get details => MemberDetails(
        fullName: fullName,
        phone: phone,
        email: email,
        dateOfBirth: dateOfBirth,
        bloodGroup: bloodGroup,
        occupation: occupation,
        place: LocationSelection(dzongkhagId: dzongkhagId, gewogId: gewogId, villageId: villageId),
        emergencyContactName: emergencyContactName,
        emergencyContactPhone: emergencyContactPhone,
        medicalNotes: medicalNotes,
        joinedOn: joinedOn,
      );

  /// A gym_members row, with
  /// `village:villages(name), gewog:gewogs(name), dzongkhag:dzongkhags(name)`
  /// when selected.
  factory GymMember.fromJson(Map<String, dynamic> json) {
    String? name(String key) => (json[key] as Map<String, dynamic>?)?['name'] as String?;
    final place = [name('village'), name('gewog'), name('dzongkhag')].whereType<String>().join(', ');
    DateTime? date(String key) => json[key] == null ? null : BhutanTime.parseDate(json[key] as String);
    return GymMember(
      id: json['id'] as String,
      venueId: json['venue_id'] as String,
      code: json['code'] as String,
      qrToken: json['qr_token'] as String,
      fullName: json['full_name'] as String,
      phone: json['phone'] as String,
      email: json['email'] as String?,
      dateOfBirth: date('date_of_birth'),
      bloodGroup: json['blood_group'] as String?,
      occupation: json['occupation'] as String?,
      dzongkhagId: json['dzongkhag_id'] as int?,
      gewogId: json['gewog_id'] as int?,
      villageId: json['village_id'] as int?,
      placeName: place.isEmpty ? null : place,
      emergencyContactName: json['emergency_contact_name'] as String?,
      emergencyContactPhone: json['emergency_contact_phone'] as String?,
      medicalNotes: json['medical_notes'] as String?,
      photoPath: json['photo_path'] as String?,
      joinedOn: BhutanTime.parseDate(json['joined_on'] as String),
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}

/// The registration form's details (everything but the package and photo).
class MemberDetails {
  final String fullName;
  final String phone;
  final String? email;
  final DateTime? dateOfBirth;
  final String? bloodGroup;
  final String? occupation;
  final LocationSelection place;
  final String? emergencyContactName;
  final String? emergencyContactPhone;
  final String? medicalNotes;
  final DateTime joinedOn;

  const MemberDetails({
    required this.fullName,
    required this.phone,
    required this.joinedOn,
    this.email,
    this.dateOfBirth,
    this.bloodGroup,
    this.occupation,
    this.place = LocationSelection.empty,
    this.emergencyContactName,
    this.emergencyContactPhone,
    this.medicalNotes,
  });

  /// For gym_register_member and gym_update_member, which check it all again.
  Map<String, dynamic> toJson() {
    String? clean(String? v) => (v == null || v.trim().isEmpty) ? null : v.trim();
    return {
      'full_name': fullName.trim(),
      'phone': Validators.normalizePhone(phone) ?? phone.trim(),
      'email': clean(email)?.toLowerCase(),
      'date_of_birth': dateOfBirth == null ? null : isoDate(dateOfBirth!),
      'blood_group': bloodGroup,
      'occupation': clean(occupation),
      'dzongkhag_id': place.dzongkhagId,
      'gewog_id': place.gewogId,
      'village_id': place.villageId,
      'emergency_contact_name': clean(emergencyContactName),
      'emergency_contact_phone':
          clean(emergencyContactPhone) == null ? null : (Validators.normalizePhone(emergencyContactPhone!) ?? emergencyContactPhone!.trim()),
      'medical_notes': clean(medicalNotes),
      'joined_on': isoDate(joinedOn),
    };
  }
}

/// A package sold at the desk: which plan, for how many months, from when,
/// and what they paid.
class PackageSale {
  final GymPlan plan;
  final int months;
  final int amount;
  final PaymentMethod? method;
  final String? reference;

  const PackageSale({required this.plan, required this.months, required this.amount, this.method, this.reference});
}

/// '2026-11-08'.
String isoDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// [date] plus [months] calendar months, kept within the month as Postgres
/// does: 31 January + 1 month is 28 (or 29) February.
DateTime addMonths(DateTime date, int months) {
  final total = date.month - 1 + months;
  final year = date.year + total ~/ 12;
  final month = total % 12 + 1;
  final lastDay = DateTime(year, month + 1, 0).day;
  return DateTime(year, month, date.day > lastDay ? lastDay : date.day);
}

/// The expiry date of a package of [months] months starting on [start]: the
/// same date [months] months later (8 Nov + 3 months is 8 Feb), as
/// gym_add_membership works it out. They can still come in that day, and a
/// renewal starts on it.
DateTime packageEnd(DateTime start, int months) => addMonths(start, months);

/// The day another package for them starts: the day their current one
/// expires (so the dates don't drift), or [today] once it has ended. As
/// gym_renew_member works it out.
DateTime renewalStart(Iterable<GymSubscription> subscriptions, DateTime today) {
  var start = today;
  for (final s in subscriptions) {
    if (s.status == SubscriptionStatus.active && s.endDate != null && s.endDate!.isAfter(start)) start = s.endDate!;
  }
  return start;
}

/// How many months [plan] lasts: a 30-day plan is 1, a 365-day plan 12.
/// At least 1 (a week's plan counts as a month's price for the dropdown).
int planMonths(GymPlan plan) {
  final months = (plan.durationDays / 30.44).round();
  return months < 1 ? 1 : months;
}

/// What [months] months of [plan] cost at its price: the amount the form
/// suggests (staff enter what they actually received).
int packagePrice(GymPlan plan, int months) => (plan.price * months / planMonths(plan)).round();

/// The months option closest to [plan]'s own length, for the dropdown to
/// start on.
int defaultMonths(GymPlan plan) {
  final m = planMonths(plan);
  return packageMonthOptions.reduce((a, b) => (a - m).abs() <= (b - m).abs() ? a : b);
}

/// A registered member's standing today, from their memberships here.
enum MemberStanding { active, upcoming, ended, none }

MemberStanding standingOf(Iterable<GymSubscription> subscriptions, DateTime today) {
  if (subscriptions.any((s) => s.isCurrentOn(today))) return MemberStanding.active;
  if (subscriptions.any((s) => s.isUpcomingOn(today))) return MemberStanding.upcoming;
  if (subscriptions.any((s) => s.status == SubscriptionStatus.expired || s.status == SubscriptionStatus.active)) {
    return MemberStanding.ended;
  }
  return MemberStanding.none;
}
