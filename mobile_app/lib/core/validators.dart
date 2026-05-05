/// Validation for sign up: email and strong password

final _emailRegex = RegExp(
  r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$',
);

/// Valid email e.g. zainch1211@gmail.com
String? validateEmail(String? value) {
  if (value == null || value.trim().isEmpty) {
    return 'Enter email';
  }
  if (!_emailRegex.hasMatch(value.trim())) {
    return 'Enter a valid email (e.g. zainch1211@gmail.com)';
  }
  return null;
}

/// Password: min 8 chars, at least one number, one letter, one special char, one capital
String? validateStrongPassword(String? value) {
  if (value == null || value.isEmpty) {
    return 'Enter password';
  }
  if (value.length < 8) {
    return 'Password must be at least 8 characters';
  }
  if (!value.contains(RegExp(r'[A-Z]'))) {
    return 'Password must contain at least one capital letter';
  }
  if (!value.contains(RegExp(r'[a-z]'))) {
    return 'Password must contain at least one letter';
  }
  if (!value.contains(RegExp(r'[0-9]'))) {
    return 'Password must contain at least one number';
  }
  // Special chars (use normal string to avoid raw-string quote/backtick issues)
  final specialChar = RegExp(r'[!@#$%^&*()_+\-=\[\]{}|;:",.<>?/\\`~]');
  if (!value.contains(specialChar)) {
    return 'Password must contain at least one special character (!@#\$%^&* etc.)';
  }
  return null;
}

String? validateUsername(String? value) {
  if (value == null || value.trim().isEmpty) {
    return 'Enter username';
  }
  if (value.trim().length < 2) {
    return 'Username must be at least 2 characters';
  }
  return null;
}

String? validatePasswordRequired(String? value) {
  if (value == null || value.isEmpty) {
    return 'Enter password';
  }
  return null;
}
