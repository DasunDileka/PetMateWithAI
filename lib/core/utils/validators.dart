/// Form validators shared by every input in the app.
///
/// Client-side validation is a usability measure, not a security control — the
/// Firestore rules are what actually enforce shape and ownership on the server.
/// These exist so the user gets an immediate, specific message rather than a
/// round-trip failure.
class Validators {
  const Validators._();

  // Deliberately permissive: the goal is to catch typos, not to police the RFC.
  static final RegExp _email = RegExp(r'^[\w.+-]+@[\w-]+\.[\w.-]+$');

  static String? required(String? value, {String field = 'This field'}) {
    if (value == null || value.trim().isEmpty) return '$field is required.';
    return null;
  }

  static String? name(String? value) {
    final String v = (value ?? '').trim();
    if (v.isEmpty) return 'Please enter your name.';
    if (v.length < 2) return 'Please enter your full name.';
    if (v.length > 80) return 'That name is too long.';
    return null;
  }

  static String? email(String? value) {
    final String v = (value ?? '').trim();
    if (v.isEmpty) return 'Please enter your email address.';
    if (!_email.hasMatch(v)) return 'Please enter a valid email address.';
    return null;
  }

  static String? password(String? value) {
    final String v = value ?? '';
    if (v.isEmpty) return 'Please enter a password.';
    // Firebase enforces a six-character minimum; matching it here keeps the
    // error local instead of arriving from the server.
    if (v.length < 6) return 'Password must be at least 6 characters.';
    if (v.length > 128) return 'That password is too long.';
    return null;
  }

  static String? confirmPassword(String? value, String original) {
    if (value == null || value.isEmpty) return 'Please confirm your password.';
    if (value != original) return 'Passwords do not match.';
    return null;
  }

  static String? petName(String? value) {
    final String v = (value ?? '').trim();
    if (v.isEmpty) return 'Please enter your pet\'s name.';
    if (v.length > 60) return 'That name is too long.';
    return null;
  }

  /// Weight in kilograms. The upper bound is generous but stops obvious
  /// unit mistakes (entering grams) from corrupting the AI context.
  static String? weight(String? value, {bool optional = false}) {
    final String v = (value ?? '').trim();
    if (v.isEmpty) return optional ? null : 'Please enter a weight.';
    final double? parsed = double.tryParse(v);
    if (parsed == null) return 'Enter a number, for example 18.5';
    if (parsed <= 0) return 'Weight must be greater than zero.';
    if (parsed > 200) return 'That weight looks too high. Enter it in kilograms.';
    return null;
  }

  static String? positiveNumber(String? value, {String field = 'Value'}) {
    final String v = (value ?? '').trim();
    if (v.isEmpty) return '$field is required.';
    final double? parsed = double.tryParse(v);
    if (parsed == null) return 'Enter a number.';
    if (parsed <= 0) return '$field must be greater than zero.';
    return null;
  }

  static String? duration(String? value) {
    final String v = (value ?? '').trim();
    if (v.isEmpty) return 'Please enter a duration.';
    final int? parsed = int.tryParse(v);
    if (parsed == null) return 'Enter whole minutes, for example 20';
    if (parsed <= 0) return 'Duration must be greater than zero.';
    if (parsed > 1440) return 'That is longer than a day.';
    return null;
  }

  static String? phone(String? value, {bool optional = true}) {
    final String v = (value ?? '').trim();
    if (v.isEmpty) return optional ? null : 'Please enter a phone number.';
    if (v.length < 6) return 'That phone number looks too short.';
    if (!RegExp(r'^[\d\s()+-]+$').hasMatch(v)) {
      return 'Use digits, spaces and + ( ) - only.';
    }
    return null;
  }

  static String? optionalEmail(String? value) {
    final String v = (value ?? '').trim();
    if (v.isEmpty) return null;
    return _email.hasMatch(v) ? null : 'Please enter a valid email address.';
  }

  /// Caps free-text notes so a single record cannot bloat a document or a
  /// downstream AI prompt.
  static String? notes(String? value, {int max = 500}) {
    final String v = (value ?? '').trim();
    if (v.length > max) return 'Please keep this under $max characters.';
    return null;
  }
}
