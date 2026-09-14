import 'package:easy_localization/easy_localization.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/services/security/private_key_export_service.dart';

String privateKeyExportErrorText(PrivateKeyExportError error) =>
    switch (error) {
      PrivateKeyExportError.incorrectPassword =>
        LocaleKeys.incorrectPassword.tr(),
      PrivateKeyExportError.sessionChanged =>
        LocaleKeys.privateKeyExportSessionChanged.tr(),
      PrivateKeyExportError.unavailable =>
        LocaleKeys.privateKeyRetrievalFailed.tr(),
    };

String privateKeyExportCoverageText(PrivateKeyExportCoverage coverage) =>
    switch (coverage.kind) {
      PrivateKeyExportCoverageKind.legacyWallet =>
        LocaleKeys.privateKeyExportLegacyCoverage.tr(),
      PrivateKeyExportCoverageKind.offlineAccount =>
        LocaleKeys.privateKeyExportAccountCoverage.tr(
          namedArgs: {'account': '${coverage.accountIndex}'},
        ),
      PrivateKeyExportCoverageKind.offlineHdRange =>
        LocaleKeys.privateKeyExportHdCoverage.tr(
          namedArgs: {
            'account': '${coverage.accountIndex}',
            'start': '${coverage.startIndex}',
            'end': '${coverage.endIndex}',
            'chain': switch (coverage.chain?.toLowerCase()) {
              'external' ||
              '0' ||
              'receiving' => LocaleKeys.privateKeyExportReceiving.tr(),
              'internal' ||
              '1' ||
              'change' => LocaleKeys.privateKeyExportChange.tr(),
              _ =>
                coverage.chain ?? LocaleKeys.privateKeyExportUnknownBranch.tr(),
            },
          },
        ),
    };

String privateKeyExportFailureText(
  PrivateKeyExportFailure failure, {
  required AssetId assetId,
}) => switch (failure) {
  PrivateKeyExportFailure.unsupportedProtocol =>
    assetId.subClass == CoinSubClass.trx ||
            assetId.subClass == CoinSubClass.trc20
        ? LocaleKeys.privateKeyExportTronUnavailable.tr()
        : LocaleKeys.privateKeyExportUnsupported.tr(),
  PrivateKeyExportFailure.invalidResponse =>
    LocaleKeys.privateKeyExportUnverified.tr(),
  PrivateKeyExportFailure.assetUnavailable ||
  PrivateKeyExportFailure.rpcFailed =>
    LocaleKeys.privateKeyExportAssetUnavailable.tr(),
};
