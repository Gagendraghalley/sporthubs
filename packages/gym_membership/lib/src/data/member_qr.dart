/// A member's QR code: `sportshub:member:<their account id>` on an account
/// member's phone, or `sportshub:gym-member:<card token>` on the card of a
/// member registered at the front desk. Staff can also type the member code
/// printed under either ('4K7P9Q').
abstract final class MemberQr {
  static const prefix = 'sportshub:member:';
  static const cardPrefix = 'sportshub:gym-member:';

  static final _uuid = RegExp(r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$');
  static final _code = RegExp(r'^[A-Z0-9]{6}$');
  static final _token = RegExp(r'^[0-9a-f]{32}$');

  static String encode(String memberId) => '$prefix$memberId';

  /// What a registered member's card holds.
  static String encodeCard(String qrToken) => '$cardPrefix$qrToken';

  /// Who a scanned or typed [raw] points to; null when it's neither a
  /// member's QR code nor a member code.
  static MemberRef? parse(String raw) {
    final text = raw.trim();
    if (text.toLowerCase().startsWith(cardPrefix)) {
      final token = text.substring(cardPrefix.length).toLowerCase();
      return _token.hasMatch(token) ? MemberRef.card(token) : null;
    }
    if (text.toLowerCase().startsWith(prefix)) {
      final id = text.substring(prefix.length);
      return _uuid.hasMatch(id) ? MemberRef.id(id.toLowerCase()) : null;
    }
    if (_uuid.hasMatch(text)) return MemberRef.id(text.toLowerCase());
    final code = text.toUpperCase().replaceAll(RegExp(r'[\s-]'), '');
    return _code.hasMatch(code) ? MemberRef.code(code) : null;
  }
}

/// A member: by account id (an account member's QR code), by card token (a
/// registered member's card) or by member code (typed).
class MemberRef {
  final String? id;
  final String? code;
  final String? cardToken;

  const MemberRef.id(String this.id)
      : code = null,
        cardToken = null;
  const MemberRef.code(String this.code)
      : id = null,
        cardToken = null;
  const MemberRef.card(String this.cardToken)
      : id = null,
        code = null;

  @override
  bool operator ==(Object other) =>
      other is MemberRef && other.id == id && other.code == code && other.cardToken == cardToken;

  @override
  int get hashCode => Object.hash(id, code, cardToken);

  @override
  String toString() => id != null
      ? 'MemberRef.id($id)'
      : cardToken != null
          ? 'MemberRef.card($cardToken)'
          : 'MemberRef.code($code)';
}
