/// Form field checks. Each returns the message to show, or null when fine.
abstract final class Validators {
  static String? required(String? value, [String what = 'This']) =>
      (value == null || value.trim().isEmpty) ? '$what is required' : null;

  static String? email(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'Email is required';
    return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v) ? null : 'Enter a valid email address';
  }

  static String? password(String? value) =>
      (value ?? '').length < 8 ? 'Use at least 8 characters' : null;

  /// Optional unless [required]: a Bhutan mobile (17/77 + 6 digits) or any
  /// number with its country code.
  static String? phone(String? value, {bool required = false}) {
    final v = (value ?? '').replaceAll(RegExp(r'[\s-]'), '');
    if (v.isEmpty) return required ? 'Phone number is required' : null;
    return normalizePhone(v) == null ? 'Enter a valid phone number, e.g. 17123456' : null;
  }

  /// '+97517123456' from '17123456', '+975 17 12 34 56' or '97517123456';
  /// null when it isn't a phone number.
  static String? normalizePhone(String value) {
    var v = value.replaceAll(RegExp(r'[\s()-]'), '');
    if (RegExp(r'^[0-9]{8}$').hasMatch(v)) v = '+975$v';
    if (RegExp(r'^975[0-9]{8}$').hasMatch(v)) v = '+$v';
    return RegExp(r'^\+[0-9]{8,15}$').hasMatch(v) ? v : null;
  }

  /// A whole number from [min] up to [max].
  static String? wholeNumber(String? value, {int min = 0, int max = 1000000, String what = 'Amount'}) {
    final n = int.tryParse((value ?? '').trim());
    if (n == null) return '$what must be a whole number';
    if (n < min || n > max) return '$what must be from $min to $max';
    return null;
  }
}
