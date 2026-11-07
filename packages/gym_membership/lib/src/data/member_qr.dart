/// A member's QR code: `sportshub:member:<their account id>`. Staff can also
/// type the member code printed under it ('4K7P9Q').
abstract final class MemberQr {
  static const prefix = 'sportshub:member:';

  static final _uuid = RegExp(r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$');
  static final _code = RegExp(r'^[A-Z0-9]{6}$');

  static String encode(String memberId) => '$prefix$memberId';

  /// Who a scanned or typed [raw] points to; null when it's neither a
  /// member's QR code nor a member code.
  static MemberRef? parse(String raw) {
    final text = raw.trim();
    if (text.toLowerCase().startsWith(prefix)) {
      final id = text.substring(prefix.length);
      return _uuid.hasMatch(id) ? MemberRef.id(id.toLowerCase()) : null;
    }
    if (_uuid.hasMatch(text)) return MemberRef.id(text.toLowerCase());
    final code = text.toUpperCase().replaceAll(RegExp(r'[\s-]'), '');
    return _code.hasMatch(code) ? MemberRef.code(code) : null;
  }
}

/// A member, by account id (from the QR code) or by member code (typed).
class MemberRef {
  final String? id;
  final String? code;

  const MemberRef.id(String this.id) : code = null;
  const MemberRef.code(String this.code) : id = null;

  @override
  bool operator ==(Object other) => other is MemberRef && other.id == id && other.code == code;

  @override
  int get hashCode => Object.hash(id, code);

  @override
  String toString() => id != null ? 'MemberRef.id($id)' : 'MemberRef.code($code)';
}
