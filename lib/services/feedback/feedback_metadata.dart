import 'package:komodo_defi_types/komodo_defi_type_utils.dart';

import 'package:web_dex/shared/constants.dart' show contactDetailsMaxLength;

/// Contact fields come exclusively from the submitted form, never automatic
/// diagnostic metadata. The form also embeds them in its formatted description.
Map<String, String> submittedFeedbackContact(Map<String, dynamic>? extras) {
  const methods = {'email', 'discord', 'matrix', 'telegram'};
  final method = extras?['contact_method'];
  final details = extras?['contact_details'];
  if (method is! String || !methods.contains(method) || details is! String) {
    return const {};
  }
  final contact = details.trim();
  if (contact.isEmpty ||
      contact.length > contactDetailsMaxLength ||
      RegExp(r'[\x00-\x1f\x7f]').hasMatch(contact)) {
    return const {};
  }
  return {'contactMethod': method, 'contactDetails': contact};
}

/// Explicit diagnostic fields only. Wallet serialization, arbitrary package
/// fields, URLs, and contact details do not belong in automatic metadata.
Map<String, dynamic> sanitizeFeedbackMetadata(Map<String, dynamic> input) {
  const textFields = {
    'appName',
    'packageName',
    'version',
    'buildNumber',
    'platform',
    'targetPlatform',
    'mode',
    'timestamp',
  };
  const commitFields = {
    'commitHash',
    'coinsCurrentCommit',
    'coinsLatestCommit',
  };
  const booleanFields = {'walletIsHd', 'walletIsBip39'};
  return {
    for (final key in textFields)
      if (DiagnosticSanitizer.sanitizeMessage(input[key])
          case final String value)
        key: value,
    for (final key in booleanFields)
      if (input[key] case final bool value) key: value,
    for (final key in commitFields)
      if (input[key] case final String value)
        if (value == 'unknown' ||
            RegExp(r'^[a-fA-F0-9]{7,40}$').hasMatch(value))
          key: value,
  };
}
