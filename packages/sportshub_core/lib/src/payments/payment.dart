/// payments.method: how money reached the venue.
enum PaymentMethod {
  mbob('mbob', 'mBoB'),
  cash('cash', 'Cash'),
  bank('bank', 'Bank transfer'),
  other('other', 'Other');

  const PaymentMethod(this.value, this.label);
  final String value;
  final String label;

  static PaymentMethod from(String value) =>
      PaymentMethod.values.firstWhere((m) => m.value == value, orElse: () => PaymentMethod.other);
}

/// One payment at a venue, in any module: a gym fee today. Written only by
/// the database's functions (e.g. when gym staff confirm a membership).
class Payment {
  final String id;
  final String? userId;
  final String venueId;
  final String moduleKey;
  final String? referenceId;
  final int amount;
  final PaymentMethod method;
  final String? reference;
  final String status;
  final DateTime createdAt;

  /// From profiles, when the reader may see it (the venue's staff).
  final String? payerName;

  const Payment({
    required this.id,
    required this.venueId,
    required this.moduleKey,
    required this.amount,
    required this.method,
    required this.status,
    required this.createdAt,
    this.userId,
    this.referenceId,
    this.reference,
    this.payerName,
  });

  bool get isCompleted => status == 'completed';

  factory Payment.fromJson(Map<String, dynamic> json) => Payment(
        id: json['id'] as String,
        userId: json['user_id'] as String?,
        venueId: json['venue_id'] as String,
        moduleKey: json['module_key'] as String,
        referenceId: json['reference_id'] as String?,
        amount: (json['amount'] as num).toInt(),
        method: PaymentMethod.from(json['method'] as String),
        reference: json['reference'] as String?,
        status: json['status'] as String,
        createdAt: DateTime.parse(json['created_at'] as String),
        // Their account's name, or the name written down for payers without
        // one (a gym's walk-in members).
        payerName: (json['payer'] as Map<String, dynamic>?)?['full_name'] as String? ?? json['payer_name'] as String?,
      );
}
