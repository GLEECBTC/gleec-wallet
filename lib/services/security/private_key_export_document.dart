import 'dart:convert';

import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';

/// Intentional user export, separate from every diagnostic serializer.
SensitiveString privateKeyExportDocument(
  PrivateKeyExportResult result, {
  Set<AssetId> excludedAssets = const {},
}) {
  final displayed = PrivateKeyExportResult(
    outcomes: result.outcomes
        .where((outcome) => !excludedAssets.contains(outcome.assetId))
        .toList(),
  );
  return SensitiveString(
    const JsonEncoder.withIndent('  ').convert({
      'format': 'gleec-private-key-export',
      'version': 1,
      'scope': 'requested_assets_and_reported_ranges',
      'complete_for_displayed_assets': displayed.isComplete,
      'excluded_assets': excludedAssets.map((asset) => asset.id).toList(),
      'assets': displayed.outcomes.map((outcome) => outcome.toJson()).toList(),
    }),
  );
}
