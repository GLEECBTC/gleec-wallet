import 'package:characters/characters.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/shared/constants.dart';

/// Enum representing different types of password validation errors
enum PasswordValidationError {
  containsPassword,
  tooShort,
  tooLong,
  missingDigit,
  missingLowercase,
  missingUppercase,
  missingSpecialCharacter,
  consecutiveCharacters,
  none,
}

/// Converts a password validation error to a localized error message
String? passwordErrorMessage(PasswordValidationError error) {
  switch (error) {
    case PasswordValidationError.containsPassword:
      return LocaleKeys.passwordContainsTheWordPassword.tr();
    case PasswordValidationError.tooShort:
      return LocaleKeys.passwordTooShort.tr();
    case PasswordValidationError.tooLong:
      return LocaleKeys.passwordTooLong.tr();
    case PasswordValidationError.missingDigit:
      return LocaleKeys.passwordMissingDigit.tr();
    case PasswordValidationError.missingLowercase:
      return LocaleKeys.passwordMissingLowercase.tr();
    case PasswordValidationError.missingUppercase:
      return LocaleKeys.passwordMissingUppercase.tr();
    case PasswordValidationError.missingSpecialCharacter:
      return LocaleKeys.passwordMissingSpecialCharacter.tr();
    case PasswordValidationError.consecutiveCharacters:
      return LocaleKeys.passwordConsecutiveCharacters.tr();
    case PasswordValidationError.none:
      return null;
  }
}

String? validateConfirmPassword(String password, String confirmPassword) {
  return password != confirmPassword
      ? LocaleKeys.walletCreationConfirmPasswordError.tr()
      : null;
}

String? validatePasswordLegacy(String password, String errorText) {
  final RegExp exp = RegExp(
    r'^(?:(?=.*[a-z])(?=.*[A-Z])(?=.*[^a-zA-Z0-9\s])).{12,}$',
  );
  return password.isEmpty || !password.contains(exp) ? errorText : null;
}

/// Validates password according to KDF password policy
///
/// Password requirements:
/// - At least 8 characters long
/// - Can't contain the word "password"
/// - At least 1 digit
/// - At least 1 lowercase character
/// - At least 1 uppercase character
/// - At least 1 special character
/// - No same character 3 times in a row
String? validatePassword(String password) {
  return passwordErrorMessage(checkPasswordRequirements(password));
}

/// Internal validation method that returns the enum error type
PasswordValidationError checkPasswordRequirements(String password) {
  // As suggested by CodeRabbitAI:
  // password.length counts UTF-16 code units, so a single emoji or accented
  // glyph can be reported as 2 – 4 characters, letting users create visually
  // short (and possibly weak) passwords that still pass the length check.
  // Switch to password.characters.length, already available via the characters
  // package you import.
  if (password.characters.length < 8) {
    return PasswordValidationError.tooShort;
  }

  if (password.characters.length > passwordMaxLength) {
    return PasswordValidationError.tooLong;
  }

  if (password.toLowerCase().contains(
    RegExp('password', caseSensitive: false, unicode: true),
  )) {
    return PasswordValidationError.containsPassword;
  }

  // Check for digits (any numerical digit in any script)
  if (!RegExp(r'.*\p{N}.*', unicode: true).hasMatch(password)) {
    return PasswordValidationError.missingDigit;
  }

  // Check for lowercase (any lowercase letter in any script)
  if (!RegExp(r'.*\p{Ll}.*', unicode: true).hasMatch(password)) {
    return PasswordValidationError.missingLowercase;
  }

  // Check for uppercase (any uppercase letter in any script)
  if (!RegExp(r'.*\p{Lu}.*', unicode: true).hasMatch(password)) {
    return PasswordValidationError.missingUppercase;
  }

  // Check for special characters
  if (!RegExp(r'.*[^\p{L}\p{N}].*', unicode: true).hasMatch(password)) {
    return PasswordValidationError.missingSpecialCharacter;
  }

  // Unicode-aware check for consecutive repeated characters using Characters class
  final charactersList = password.characters.toList();
  for (int i = 0; i < charactersList.length - 2; i++) {
    if (charactersList[i] == charactersList[i + 1] &&
        charactersList[i] == charactersList[i + 2]) {
      return PasswordValidationError.consecutiveCharacters;
    }
  }

  return PasswordValidationError.none;
}
