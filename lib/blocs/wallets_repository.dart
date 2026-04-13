import 'dart:async';
import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart'
    show AuthException, AuthExceptionType, CoinSubClass;
import 'package:komodo_legacy_wallet_migration/komodo_legacy_wallet_migration.dart';
import 'package:web_dex/app_config/app_config.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/mm2/mm2_api/mm2_api.dart';
import 'package:web_dex/model/kdf_auth_metadata_extension.dart';
import 'package:web_dex/model/prepared_legacy_migration.dart';
import 'package:web_dex/model/wallet.dart';
import 'package:web_dex/services/file_loader/file_loader.dart';
import 'package:web_dex/services/storage/base_storage.dart';
import 'package:web_dex/shared/utils/validators.dart';
import 'package:web_dex/shared/utils/encryption_tool.dart';
import 'package:web_dex/shared/utils/utils.dart';

enum LegacyWalletCleanupStatus { complete, partial }

class LegacyWalletCleanupOutcome {
  const LegacyWalletCleanupOutcome({
    required this.status,
    required this.sourceRemoved,
    this.message,
  });

  const LegacyWalletCleanupOutcome.complete({required bool sourceRemoved})
    : this(
        status: LegacyWalletCleanupStatus.complete,
        sourceRemoved: sourceRemoved,
      );

  const LegacyWalletCleanupOutcome.partial({
    required bool sourceRemoved,
    required String message,
  }) : this(
         status: LegacyWalletCleanupStatus.partial,
         sourceRemoved: sourceRemoved,
         message: message,
       );

  final LegacyWalletCleanupStatus status;
  final bool sourceRemoved;
  final String? message;

  bool get isComplete => status == LegacyWalletCleanupStatus.complete;
}

class LegacySpecialCaseImportResult {
  const LegacySpecialCaseImportResult({
    required this.walletCoinIdsToActivate,
    this.warningMessage,
  });

  final List<String> walletCoinIdsToActivate;
  final String? warningMessage;
}

class WalletsRepository {
  static const String _legacyPassphraseSavedKey = 'isPassphraseIsSaved';
  static const String _legacyZCoinActivationRequestedKeyPrefix =
      'z-coin-activation-requested-';
  static const String _legacySwitchPinKey = 'switch_pin';
  static const String _legacySwitchPinBiometricKey = 'switch_pin_biometric';
  static const String _legacySwitchPinLogoutKey = 'switch_pin_log_out_on_exit';
  static const String _legacyDisallowScreenshotKey = 'disallowScreenshot';
  static const String _legacyIsCamoEnabledKey = 'isCamoEnabled';
  static const String _legacyIsCamoActiveKey = 'isCamoActive';
  static const String _legacyCamoFractionKey = 'camoFraction';
  static const String _legacyCamoBalanceKey = 'camoBalance';
  static const String _legacyCamoSessionStartedAtKey = 'camoSessionStartedAt';
  static const String _legacyZhtlcSyncTypeKey = 'zhtlcSyncType';
  static const String _legacyZhtlcSyncStartDateKey = 'zhtlcSyncStartDate';
  static const String _legacyPendingZhtlcAssetsExtrasKey =
      'pending_zhtlc_assets';
  static const String _legacyRequestedZhtlcCoinIdsExtrasKey =
      'requested_zhtlc_coin_ids';
  static const String _legacyZhtlcSyncPolicyExtrasKey = 'zhtlc_sync_policy';
  static const String _zhtlcMigrationWarning =
      'Wallet migrated, but some ZHTLC assets still need Zcash parameters before activation.';

  WalletsRepository(
    this._kdfSdk,
    this._mm2Api,
    this._legacyWalletStorage, {
    KomodoLegacyWalletMigration? legacyNativeWalletMigration,
    EncryptionTool? encryptionTool,
    FileLoader? fileLoader,
    ZcashParamsDownloader Function()? zcashParamsDownloaderFactory,
  }) : _legacyNativeWalletMigration =
           legacyNativeWalletMigration ?? KomodoLegacyWalletMigration(),
       _encryptionTool = encryptionTool ?? EncryptionTool(),
       _fileLoader = fileLoader ?? FileLoader.fromPlatform(),
       _zcashParamsDownloaderFactory =
           zcashParamsDownloaderFactory ?? ZcashParamsDownloaderFactory.create;

  final KomodoDefiSdk _kdfSdk;
  final Mm2Api _mm2Api;
  final BaseStorage _legacyWalletStorage;
  final KomodoLegacyWalletMigration _legacyNativeWalletMigration;
  final EncryptionTool _encryptionTool;
  final FileLoader _fileLoader;
  final ZcashParamsDownloader Function() _zcashParamsDownloaderFactory;
  final StreamController<List<Wallet>> _walletsController =
      StreamController<List<Wallet>>.broadcast();

  List<Wallet>? _cachedWallets;
  List<Wallet>? _cachedLegacyWallets;
  List<Wallet>? get wallets => _cachedWallets;
  bool get isCacheLoaded =>
      _cachedWallets != null && _cachedLegacyWallets != null;

  /// Clears both SDK and legacy wallet caches so the next [getWallets] call
  /// fetches fresh data. Call after operations that change the wallet list
  /// (migration, deletion, etc.) to avoid stale UI state.
  void invalidateCache() {
    _cachedWallets = null;
    _cachedLegacyWallets = null;
  }

  Stream<List<Wallet>> watchWallets() async* {
    if (isCacheLoaded) {
      yield _buildCombinedCachedWallets();
    }
    yield* _walletsController.stream;
  }

  Future<List<Wallet>> refreshWallets() async {
    return getWallets();
  }

  Future<List<Wallet>> getWallets() async {
    final sdkWallets = (await _kdfSdk.wallets)
        .where(
          (wallet) =>
              wallet.config.type != WalletType.trezor &&
              !wallet.name.toLowerCase().startsWith(trezorWalletNamePrefix),
        )
        .toList();
    final sharedPrefsLegacyWallets = await _getSharedPrefsLegacyWallets();
    final nativeLegacyWallets = await _getNativeLegacyWallets();

    final hiddenSharedPrefsWallets = sharedPrefsLegacyWallets
        .where(
          (wallet) =>
              _findMigratedSdkWalletForSource(wallet, sdkWallets) != null,
        )
        .toList(growable: false);
    final hiddenNativeWallets = nativeLegacyWallets
        .where(
          (wallet) =>
              _findMigratedSdkWalletForSource(wallet, sdkWallets) != null,
        )
        .toList(growable: false);

    if (hiddenSharedPrefsWallets.isNotEmpty) {
      try {
        await _pruneSharedPrefsLegacyWallets(hiddenSharedPrefsWallets);
      } catch (error, stackTrace) {
        log(
          'Failed to prune migrated shared-preferences legacy wallets: $error',
          path: 'wallets_repository => getWallets',
          trace: stackTrace,
          isError: true,
        ).ignore();
      }
    }

    _cachedWallets = sdkWallets;
    _cachedLegacyWallets = <Wallet>[
      ...sharedPrefsLegacyWallets.where(
        (wallet) => !hiddenSharedPrefsWallets.contains(wallet),
      ),
      ...nativeLegacyWallets.where(
        (wallet) => !hiddenNativeWallets.contains(wallet),
      ),
    ];
    final allWallets = _buildCombinedCachedWallets();
    _emitWalletsUpdate(allWallets);
    return allWallets;
  }

  Future<List<Wallet>> _getSharedPrefsLegacyWallets() async {
    final rawLegacyWallets =
        (await _legacyWalletStorage.read(allWalletsStorageKey) as List?)
            ?.cast<Map<String, dynamic>>() ??
        [];

    return rawLegacyWallets.map((Map<String, dynamic> w) {
      final wallet = Wallet.fromJson(w);
      return wallet.copyWith(
        config: wallet.config.copyWith(
          // Wallet type for legacy wallets is iguana, to avoid confusion with
          // missing/empty balances. Sign into iguana for legacy wallets by
          // default, but allow for them to be signed into hdwallet if desired.
          type: WalletType.iguana,
          isLegacyWallet: true,
        ),
        legacySource: LegacyWalletSource(
          kind: LegacyWalletSourceKind.sharedPrefs,
          originalWalletName: wallet.name,
          originalWalletId: wallet.id,
        ),
      );
    }).toList();
  }

  Future<List<Wallet>> _getNativeLegacyWallets() async {
    if (!_legacyNativeWalletMigration.isSupportedPlatform) {
      return const <Wallet>[];
    }

    try {
      final legacyWallets = await _legacyNativeWalletMigration
          .listLegacyWallets();
      return legacyWallets
          .map(
            (wallet) => Wallet(
              id: wallet.walletId,
              name: wallet.walletName,
              config: WalletConfig(
                seedPhrase: '',
                activatedCoins: wallet.activatedCoins,
                hasBackup: false,
                type: WalletType.iguana,
                isLegacyWallet: true,
              ),
              legacySource: LegacyWalletSource(
                kind: LegacyWalletSourceKind.nativeApp,
                originalWalletName: wallet.walletName,
                originalWalletId: wallet.walletId,
              ),
            ),
          )
          .toList(growable: false);
    } catch (e, s) {
      log(
        'Failed to list native legacy wallets: $e',
        path: 'wallets_repository => _getNativeLegacyWallets',
        trace: s,
        isError: true,
      ).ignore();
      return const <Wallet>[];
    }
  }

  Future<void> deleteWallet(Wallet wallet, {required String password}) async {
    log(
      'Deleting a wallet ${wallet.id}',
      path: 'wallet_bloc => deleteWallet',
    ).ignore();

    if (wallet.isNativeLegacyWallet) {
      final cleanupOutcome = await cleanupMigratedLegacyWallet(
        wallet: wallet,
        password: password,
      );
      if (!cleanupOutcome.isComplete && !cleanupOutcome.sourceRemoved) {
        throw AuthException(
          cleanupOutcome.message ??
              'Failed to fully delete legacy wallet data.',
          type: AuthExceptionType.generalAuthError,
        );
      }

      if (cleanupOutcome.sourceRemoved) {
        _cachedLegacyWallets?.removeWhere(
          (candidate) =>
              candidate.id == wallet.id &&
              candidate.legacySource?.kind == wallet.legacySource?.kind,
        );
        _emitCachedWalletsIfAvailable();
      }
      return;
    }

    if (wallet.isLegacyWallet) {
      final wallets = await _getSharedPrefsLegacyWallets();
      wallets.removeWhere((w) => w.id == wallet.id);
      await _legacyWalletStorage.write(allWalletsStorageKey, wallets);
      await _cleanupSharedPrefsLegacyResidue(wallet.id);
      _cachedLegacyWallets?.removeWhere(
        (candidate) =>
            candidate.id == wallet.id &&
            candidate.legacySource?.kind == wallet.legacySource?.kind,
      );
      _emitCachedWalletsIfAvailable();
      return;
    }

    try {
      await _kdfSdk.auth.deleteWallet(
        walletName: wallet.name,
        password: password,
      );
      _cachedWallets?.removeWhere((w) => w.name == wallet.name);
      _emitCachedWalletsIfAvailable();
      return;
    } catch (e) {
      log(
        'Failed to delete wallet: $e',
        path: 'wallet_bloc => deleteWallet',
        isError: true,
      ).ignore();
      rethrow;
    }
  }

  Future<String> readLegacySeed(Wallet wallet, String password) async {
    if (wallet.isNativeLegacyWallet) {
      final secrets = await readNativeLegacyWalletSecrets(wallet, password);
      return secrets.seedPhrase;
    }

    final decryptedSeed = await _encryptionTool.decryptData(
      password,
      wallet.config.seedPhrase,
    );
    if (decryptedSeed == null || decryptedSeed.isEmpty) {
      throw AuthException(
        'Incorrect wallet password',
        type: AuthExceptionType.incorrectPassword,
      );
    }

    return decryptedSeed;
  }

  Future<LegacyWalletSecrets> readNativeLegacyWalletSecrets(
    Wallet wallet,
    String password,
  ) async {
    final nativeWallet = _toNativeLegacyWalletRecord(wallet);
    if (nativeWallet == null) {
      throw AuthException.notFound();
    }

    try {
      return await _legacyNativeWalletMigration.readWalletSecrets(
        wallet: nativeWallet,
        password: password,
      );
    } on LegacyWalletMigrationException catch (e) {
      throw _mapLegacyMigrationException(e);
    }
  }

  Future<LegacyWalletCleanupOutcome> cleanupMigratedLegacyWallet({
    required Wallet wallet,
    required String password,
    LegacyWalletSecrets? nativeSecrets,
  }) async {
    if (wallet.isNativeLegacyWallet) {
      final nativeWallet = _toNativeLegacyWalletRecord(wallet);
      if (nativeWallet == null) {
        throw AuthException.notFound();
      }

      try {
        final result = await _legacyNativeWalletMigration
            .deleteLegacyWalletData(
              wallet: nativeWallet,
              password: password,
              secrets: nativeSecrets,
            );

        if (result.metadataDeleted) {
          await _cleanupNativeLegacySharedPrefsResidue(wallet.id);
        }

        return result.isComplete
            ? LegacyWalletCleanupOutcome.complete(
                sourceRemoved: result.metadataDeleted,
              )
            : LegacyWalletCleanupOutcome.partial(
                sourceRemoved: result.metadataDeleted,
                message:
                    result.warningMessage ??
                    'Legacy wallet cleanup incomplete.',
              );
      } on LegacyWalletMigrationException catch (e) {
        throw _mapLegacyMigrationException(e);
      }
    }

    try {
      if (wallet.isLegacyWallet) {
        final wallets = await _getSharedPrefsLegacyWallets();
        wallets.removeWhere((w) => w.id == wallet.id);
        await _legacyWalletStorage.write(allWalletsStorageKey, wallets);
        await _cleanupSharedPrefsLegacyResidue(wallet.id);
        _cachedLegacyWallets?.removeWhere(
          (candidate) =>
              candidate.id == wallet.id &&
              candidate.legacySource?.kind == wallet.legacySource?.kind,
        );
      }

      return const LegacyWalletCleanupOutcome.complete(sourceRemoved: true);
    } catch (error) {
      return LegacyWalletCleanupOutcome.partial(
        sourceRemoved: false,
        message:
            'Legacy wallet cleanup incomplete. '
            'Shared-preferences cleanup failed: $error',
      );
    }
  }

  Future<PreparedLegacyMigration> prepareLegacyMigration({
    required Wallet sourceWallet,
    required String legacyPassword,
    bool allowWeakPassword = false,
  }) async {
    if (!sourceWallet.isLegacyWallet) {
      throw AuthException.notFound();
    }

    await getWallets();
    final sdkWallets = _cachedWallets ?? await _loadSdkWallets();
    final migratedWallet = _findMigratedSdkWalletForSource(
      sourceWallet,
      sdkWallets,
    );
    if (migratedWallet != null) {
      throw AuthException.legacyWalletAlreadyMigrated(migratedWallet.name);
    }

    final bool requiresNewKdfPassword = allowWeakPassword
        ? checkPasswordRequirements(legacyPassword) ==
              PasswordValidationError.tooLong
        : validatePassword(legacyPassword) != null;
    final String sanitizedTargetName = sanitizeLegacyMigrationName(
      sourceWallet.name,
    );

    LegacyWalletSecrets? nativeLegacySecrets;
    String seedPhrase = '';
    List<String> requestedZhtlcCoinIds = const <String>[];
    ZhtlcRecurringSyncPolicy? zhtlcSyncPolicy;
    Map<String, dynamic> legacyWalletExtras = const <String, dynamic>{};
    if (sourceWallet.isNativeLegacyWallet) {
      nativeLegacySecrets = await readNativeLegacyWalletSecrets(
        sourceWallet,
        legacyPassword,
      );
      seedPhrase = nativeLegacySecrets.seedPhrase;
      requestedZhtlcCoinIds = nativeLegacySecrets.requestedZhtlcCoinIds;
      zhtlcSyncPolicy = _resolveLegacyZhtlcSyncPolicy(
        legacySyncType: nativeLegacySecrets.legacyZhtlcSyncType,
        legacySyncStartDate: nativeLegacySecrets.legacyZhtlcSyncStartDate,
        fallbackToRecentTransactions:
            requestedZhtlcCoinIds.isNotEmpty ||
            _containsSupportedZhtlcAsset(sourceWallet.config.activatedCoins),
      );
      legacyWalletExtras = nativeLegacySecrets.walletExtras;
    } else {
      seedPhrase = await readLegacySeed(sourceWallet, legacyPassword);
      requestedZhtlcCoinIds = await _readLegacyRequestedZhtlcCoinIds(
        sourceWallet.id,
      );
      zhtlcSyncPolicy = _resolveLegacyZhtlcSyncPolicy(
        legacySyncType:
            await _legacyWalletStorage.read(_legacyZhtlcSyncTypeKey) as String?,
        legacySyncStartDate: _parseLegacySyncStartDate(
          await _legacyWalletStorage.read(_legacyZhtlcSyncStartDateKey),
        ),
        fallbackToRecentTransactions:
            requestedZhtlcCoinIds.isNotEmpty ||
            _containsSupportedZhtlcAsset(sourceWallet.config.activatedCoins),
      );
      legacyWalletExtras = await _readSharedPrefsLegacyWalletExtras();
    }

    final String suggestedTargetWalletName = await resolveUniqueWalletName(
      sanitizedTargetName,
      excludedWallet: sourceWallet,
    );
    return PreparedLegacyMigration(
      sourceWallet: sourceWallet,
      seedPhrase: seedPhrase,
      nativeLegacySecrets: nativeLegacySecrets,
      suggestedTargetWalletName: suggestedTargetWalletName,
      requiresNameConfirmation: suggestedTargetWalletName != sourceWallet.name,
      requiresNewKdfPassword: requiresNewKdfPassword,
      requestedZhtlcCoinIds: requestedZhtlcCoinIds,
      zhtlcSyncPolicy: zhtlcSyncPolicy,
      legacyWalletExtras: legacyWalletExtras,
    );
  }

  Future<LegacySpecialCaseImportResult> importPreparedLegacySpecialCases({
    required PreparedLegacyMigration migration,
    required Iterable<String> baseActivatedCoinIds,
  }) async {
    final requestedZhtlcCoinIds = migration.requestedZhtlcCoinIds.toSet();
    final candidateCoinIds = <String>{
      ...baseActivatedCoinIds,
      ...requestedZhtlcCoinIds,
    };

    final walletCoinIdsToActivate = <String>[];
    final pendingZhtlcAssets = <String>[];
    String? zcashParamsPath;

    for (final coinId in candidateCoinIds) {
      final asset = _kdfSdk.assets.findAssetsByConfigId(coinId).firstOrNull;
      if (asset == null) {
        continue;
      }

      if (asset.id.subClass != CoinSubClass.zhtlc) {
        walletCoinIdsToActivate.add(coinId);
        continue;
      }

      zcashParamsPath ??= await _ensureZcashParamsPath();
      if (zcashParamsPath == null || zcashParamsPath.trim().isEmpty) {
        pendingZhtlcAssets.add(coinId);
        continue;
      }

      final recurringSyncPolicy =
          migration.zhtlcSyncPolicy ??
          ZhtlcRecurringSyncPolicy.recentTransactions();
      await _kdfSdk.activationConfigService.saveZhtlcConfig(
        asset.id,
        ZhtlcUserConfig(
          zcashParamsPath: zcashParamsPath,
          recurringSyncPolicy: recurringSyncPolicy,
          syncParams: recurringSyncPolicy.toSyncParams(),
        ),
      );
      walletCoinIdsToActivate.add(coinId);
    }

    final legacyWalletExtras = <String, dynamic>{
      ...migration.legacyWalletExtras,
      if (migration.requestedZhtlcCoinIds.isNotEmpty)
        _legacyRequestedZhtlcCoinIdsExtrasKey: migration.requestedZhtlcCoinIds,
      if (migration.zhtlcSyncPolicy != null)
        _legacyZhtlcSyncPolicyExtrasKey: migration.zhtlcSyncPolicy!.toJson(),
      if (pendingZhtlcAssets.isNotEmpty)
        _legacyPendingZhtlcAssetsExtrasKey: pendingZhtlcAssets,
    };
    if (legacyWalletExtras.isNotEmpty) {
      await _kdfSdk.setLegacyWalletExtras(legacyWalletExtras);
    }

    return LegacySpecialCaseImportResult(
      walletCoinIdsToActivate: walletCoinIdsToActivate,
      warningMessage: pendingZhtlcAssets.isEmpty
          ? null
          : _zhtlcMigrationWarning,
    );
  }

  String? validateWalletName(String name) {
    // Disallow special characters except letters, digits, space, underscore and hyphen
    if (RegExp(r'[^\p{L}\p{M}\p{N}\s\-_]', unicode: true).hasMatch(name)) {
      return LocaleKeys.invalidWalletNameError.tr();
    }

    final trimmedName = name.trim();

    // Reject leading/trailing spaces explicitly to avoid confusion/duplicates
    if (trimmedName != name) {
      return LocaleKeys.walletCreationNameLengthError.tr();
    }

    // Check empty and length limits on trimmed input
    if (trimmedName.isEmpty || trimmedName.length > 40) {
      return LocaleKeys.walletCreationNameLengthError.tr();
    }

    return null;
  }

  /// Async uniqueness check: verifies that no existing wallet (SDK or legacy)
  /// has the same trimmed name. Returns a localized error string if taken,
  /// or null if available. Returns null on transient fetch failures so that
  /// wallet creation is not blocked by storage errors.
  Future<String?> validateWalletNameUniqueness(String name) async {
    return validateWalletNameUniquenessForSource(name: name);
  }

  Future<String?> validateWalletNameUniquenessForSource({
    required String name,
    Wallet? excludedWallet,
  }) async {
    final String trimmedName = name.trim();
    try {
      final List<Wallet> allWallets = await getWallets();
      final bool taken =
          allWallets.firstWhereOrNull(
            (wallet) =>
                wallet.name.trim() == trimmedName &&
                !_isSameWalletIdentity(wallet, excludedWallet),
          ) !=
          null;
      if (taken) {
        return LocaleKeys.walletCreationExistNameError.tr();
      }
    } catch (error, stackTrace) {
      log(
        'Failed to verify wallet name uniqueness: $error',
        path: 'wallets_repository => validateWalletNameUniquenessForSource',
        trace: stackTrace,
        isError: true,
      ).ignore();
    }
    return null;
  }

  String? validateLegacyMigrationTargetName({
    required String name,
    required Wallet sourceWallet,
  }) {
    final formatError = validateWalletName(name);
    if (formatError != null) {
      return formatError;
    }

    final String trimmedName = name.trim();

    final Iterable<Wallet> existingWallets = <Wallet>[
      ...?_cachedWallets,
      ...?_cachedLegacyWallets,
    ];
    final bool taken = existingWallets.any(
      (wallet) =>
          wallet.name.trim() == trimmedName &&
          !_isSameWalletIdentity(wallet, sourceWallet),
    );
    if (taken) {
      return LocaleKeys.walletCreationExistNameError.tr();
    }

    return null;
  }

  Future<void> resetSpecificWallet(Wallet wallet) async {
    final coinsToDeactivate = wallet.config.activatedCoins.where(
      (coin) => !enabledByDefaultCoins.contains(coin),
    );
    for (final coin in coinsToDeactivate) {
      await _mm2Api.disableCoin(coin);
    }
  }

  @Deprecated('Use the KomodoDefiSdk.auth.getMnemonicEncrypted method instead.')
  Future<void> downloadEncryptedWallet(Wallet wallet, String password) async {
    try {
      Wallet workingWallet = wallet.copy();
      if (wallet.config.seedPhrase.isEmpty) {
        final mnemonic = await _kdfSdk.auth.getMnemonicPlainText(password);
        final String encryptedSeed = await _encryptionTool.encryptData(
          password,
          mnemonic.plaintextMnemonic ?? '',
        );
        workingWallet = workingWallet.copyWith(
          config: workingWallet.config.copyWith(seedPhrase: encryptedSeed),
        );
      }
      final String data = jsonEncode(workingWallet.config);
      final String encryptedData = await _encryptionTool.encryptData(
        password,
        data,
      );
      final String sanitizedFileName = _sanitizeFileName(workingWallet.name);
      await _fileLoader.save(
        fileName: sanitizedFileName,
        data: encryptedData,
        type: LoadFileType.text,
      );
    } catch (e) {
      throw Exception('Failed to download encrypted wallet: $e');
    }
  }

  String _sanitizeFileName(String fileName) {
    return fileName.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
  }

  Future<void> renameLegacyWallet({
    required String walletId,
    required String newName,
  }) async {
    final String trimmed = newName.trim();
    // Persist to legacy storage
    final List<Map<String, dynamic>> rawLegacyWallets =
        (await _legacyWalletStorage.read(allWalletsStorageKey) as List?)
            ?.cast<Map<String, dynamic>>() ??
        [];
    bool updated = false;
    for (int i = 0; i < rawLegacyWallets.length; i++) {
      final Map<String, dynamic> data = rawLegacyWallets[i];
      if ((data['id'] as String? ?? '') == walletId) {
        data['name'] = trimmed;
        rawLegacyWallets[i] = data;
        updated = true;
        break;
      }
    }
    if (updated) {
      await _legacyWalletStorage.write(allWalletsStorageKey, rawLegacyWallets);
    }

    // Update in-memory legacy cache if available
    if (_cachedLegacyWallets != null) {
      final index = _cachedLegacyWallets!.indexWhere(
        (element) => element.id == walletId,
      );
      if (index != -1) {
        _cachedLegacyWallets![index] = _cachedLegacyWallets![index].copyWith(
          name: trimmed,
        );
        _emitCachedWalletsIfAvailable();
      }
    }
  }

  void _emitWalletsUpdate(List<Wallet> wallets) {
    if (!_walletsController.isClosed) {
      _walletsController.add(List<Wallet>.unmodifiable(wallets));
    }
  }

  void _emitCachedWalletsIfAvailable() {
    if (_cachedWallets == null || _cachedLegacyWallets == null) {
      return;
    }
    _emitWalletsUpdate(_buildCombinedCachedWallets());
  }

  List<Wallet> _buildCombinedCachedWallets() {
    return <Wallet>[...?_cachedWallets, ...?_cachedLegacyWallets];
  }

  /// Sanitizes a legacy wallet name for migration by replacing any
  /// non-alphanumeric character (Unicode letters/digits) except underscore
  /// with an underscore. This ensures compatibility with stricter name rules
  /// in the target storage/backend.
  String sanitizeLegacyMigrationName(String name) {
    final sanitized = name.replaceAll(
      RegExp(r'[^\p{L}\p{N}_]', unicode: true),
      '_',
    );
    // Avoid returning an empty string
    return sanitized.isEmpty ? '_' : sanitized;
  }

  /// Resolves a unique wallet name by appending the lowest integer suffix
  /// starting at 1 that makes the name unique across both SDK and legacy
  /// wallets. If [baseName] is already unique, it is returned unchanged.
  Future<String> resolveUniqueWalletName(
    String baseName, {
    Wallet? excludedWallet,
  }) async {
    final List<Wallet> allWallets = await getWallets();
    final Set<String> existing = allWallets
        .where((wallet) => !_isSameWalletIdentity(wallet, excludedWallet))
        .map((wallet) => wallet.name)
        .toSet();
    if (!existing.contains(baseName)) return baseName;

    int i = 1;
    while (existing.contains('${baseName}_$i')) {
      i++;
    }
    return '${baseName}_$i';
  }

  /// Convenience helper for migration: sanitize and then ensure uniqueness.
  Future<String> sanitizeAndResolveLegacyWalletName(String legacyName) async {
    final sanitized = sanitizeLegacyMigrationName(legacyName);
    return resolveUniqueWalletName(sanitized);
  }

  Future<Wallet?> findWalletByName(
    String walletName, {
    bool includeLegacyWallets = true,
  }) async {
    final List<Wallet> allWallets = includeLegacyWallets
        ? await getWallets()
        : await _loadSdkWallets();
    return allWallets.firstWhereOrNull((wallet) => wallet.name == walletName);
  }

  LegacyWalletRecord? _toNativeLegacyWalletRecord(Wallet wallet) {
    final source = wallet.legacySource;
    if (source == null || source.kind != LegacyWalletSourceKind.nativeApp) {
      return null;
    }

    return LegacyWalletRecord(
      walletId: source.originalWalletId,
      walletName: source.originalWalletName,
      activatedCoins: wallet.config.activatedCoins,
    );
  }

  AuthException _mapLegacyMigrationException(
    LegacyWalletMigrationException exception,
  ) {
    switch (exception.type) {
      case LegacyWalletMigrationExceptionType.incorrectPassword:
        return AuthException(
          exception.message,
          type: AuthExceptionType.incorrectPassword,
        );
      case LegacyWalletMigrationExceptionType.walletNotFound:
        return AuthException.notFound();
      case LegacyWalletMigrationExceptionType.unsupportedPlatform:
      case LegacyWalletMigrationExceptionType.storageAccessError:
        return AuthException(
          exception.message,
          type: AuthExceptionType.generalAuthError,
        );
    }
  }

  Future<List<Wallet>> _loadSdkWallets() async {
    return (await _kdfSdk.wallets)
        .where(
          (wallet) =>
              wallet.config.type != WalletType.trezor &&
              !wallet.name.toLowerCase().startsWith(trezorWalletNamePrefix),
        )
        .toList(growable: false);
  }

  Wallet? _findMigratedSdkWalletForSource(
    Wallet sourceWallet,
    List<Wallet> sdkWallets,
  ) {
    final source = sourceWallet.legacySource;
    if (source == null) {
      return null;
    }

    return sdkWallets.firstWhereOrNull(
      (wallet) =>
          wallet.migratedLegacySource?.identityKey == source.identityKey,
    );
  }

  Future<void> _pruneSharedPrefsLegacyWallets(List<Wallet> wallets) async {
    final Set<String> walletIds = wallets.map((wallet) => wallet.id).toSet();
    if (walletIds.isEmpty) {
      return;
    }

    final List<Map<String, dynamic>> rawLegacyWallets =
        (await _legacyWalletStorage.read(allWalletsStorageKey) as List?)
            ?.cast<Map<String, dynamic>>() ??
        <Map<String, dynamic>>[];
    rawLegacyWallets.removeWhere(
      (wallet) => walletIds.contains(wallet['id'] as String? ?? ''),
    );
    await _legacyWalletStorage.write(allWalletsStorageKey, rawLegacyWallets);
    for (final walletId in walletIds) {
      await _cleanupSharedPrefsLegacyResidue(walletId);
    }
  }

  Future<void> _cleanupNativeLegacySharedPrefsResidue(String walletId) async {
    await _cleanupSharedPrefsLegacyResidue(walletId);
  }

  Future<void> _cleanupSharedPrefsLegacyResidue(String walletId) async {
    await _legacyWalletStorage.delete(
      '$_legacyZCoinActivationRequestedKeyPrefix$walletId',
    );

    final remainingSharedPrefsWallets = await _getSharedPrefsLegacyWallets();
    final remainingNativeWallets = await _getNativeLegacyWallets();
    if (remainingSharedPrefsWallets.isEmpty && remainingNativeWallets.isEmpty) {
      await _legacyWalletStorage.delete(_legacyPassphraseSavedKey);
    }
  }

  Future<List<String>> _readLegacyRequestedZhtlcCoinIds(String walletId) async {
    final rawValue = await _legacyWalletStorage.read(
      '$_legacyZCoinActivationRequestedKeyPrefix$walletId',
    );
    if (rawValue is List) {
      return rawValue.whereType<String>().toList(growable: false);
    }
    return const <String>[];
  }

  Future<Map<String, dynamic>> _readSharedPrefsLegacyWalletExtras() async {
    final extras = <String, dynamic>{};
    Future<void> addBool(String inputKey, String outputKey) async {
      final value = await _legacyWalletStorage.read(inputKey);
      if (value is bool) {
        extras[outputKey] = value;
      }
    }

    await addBool(_legacySwitchPinKey, 'activate_pin_protection');
    await addBool(_legacySwitchPinBiometricKey, 'activate_bio_protection');
    await addBool(_legacySwitchPinLogoutKey, 'switch_pin_log_out_on_exit');
    await addBool(_legacyDisallowScreenshotKey, 'disallow_screenshot');
    await addBool(_legacyIsCamoEnabledKey, 'enable_camo');
    await addBool(_legacyIsCamoActiveKey, 'is_camo_active');

    final camoFraction = await _legacyWalletStorage.read(
      _legacyCamoFractionKey,
    );
    if (camoFraction is int) {
      extras['camo_fraction'] = camoFraction;
    }

    final camoBalance = await _legacyWalletStorage.read(_legacyCamoBalanceKey);
    if (camoBalance is String && camoBalance.isNotEmpty) {
      extras['camo_balance'] = camoBalance;
    }

    final camoSessionStartedAt = await _legacyWalletStorage.read(
      _legacyCamoSessionStartedAtKey,
    );
    if (camoSessionStartedAt is int) {
      extras['camo_session_started_at'] = camoSessionStartedAt;
    }

    return extras;
  }

  ZhtlcRecurringSyncPolicy? _resolveLegacyZhtlcSyncPolicy({
    required String? legacySyncType,
    required DateTime? legacySyncStartDate,
    required bool fallbackToRecentTransactions,
  }) {
    switch (legacySyncType) {
      case 'newTransactions':
        return ZhtlcRecurringSyncPolicy.recentTransactions();
      case 'fullSync':
        return ZhtlcRecurringSyncPolicy.earliest();
      case 'specifiedDate':
        if (legacySyncStartDate != null) {
          return ZhtlcRecurringSyncPolicy.date(
            legacySyncStartDate.toUtc().millisecondsSinceEpoch ~/ 1000,
          );
        }
        return ZhtlcRecurringSyncPolicy.recentTransactions();
    }

    if (fallbackToRecentTransactions) {
      return ZhtlcRecurringSyncPolicy.recentTransactions();
    }

    return null;
  }

  DateTime? _parseLegacySyncStartDate(dynamic rawValue) {
    if (rawValue is String && rawValue.isNotEmpty) {
      return DateTime.tryParse(rawValue)?.toUtc();
    }
    return null;
  }

  bool _containsSupportedZhtlcAsset(Iterable<String> coinIds) {
    for (final coinId in coinIds) {
      final asset = _kdfSdk.assets.findAssetsByConfigId(coinId).firstOrNull;
      if (asset?.id.subClass == CoinSubClass.zhtlc) {
        return true;
      }
    }
    return false;
  }

  Future<String?> _ensureZcashParamsPath({
    Duration timeout = const Duration(seconds: 30),
  }) async {
    if (!ZcashParamsDownloaderFactory.requiresDownload) {
      return './zcash-params';
    }

    final downloader = _zcashParamsDownloaderFactory();
    try {
      final alreadyAvailable = await downloader.areParamsAvailable().timeout(
        timeout,
      );
      if (!alreadyAvailable) {
        log(
          'Zcash params not yet downloaded; skipping during migration '
          'to avoid blocking login',
          path: 'wallets_repository => _ensureZcashParamsPath',
        ).ignore();
        return null;
      }

      return await downloader.getParamsPath().timeout(timeout);
    } catch (error, stackTrace) {
      log(
        'Failed to ensure Zcash params availability: $error',
        path: 'wallets_repository => _ensureZcashParamsPath',
        trace: stackTrace,
        isError: true,
      ).ignore();
      return null;
    } finally {
      downloader.dispose();
    }
  }

  bool _isSameWalletIdentity(Wallet wallet, Wallet? other) {
    if (other == null) {
      return false;
    }

    if (wallet.id == other.id &&
        wallet.legacySource?.kind == other.legacySource?.kind) {
      return true;
    }

    final walletKey = wallet.legacySource?.identityKey;
    final otherKey = other.legacySource?.identityKey;
    if (walletKey == null || otherKey == null) {
      return false;
    }

    return walletKey == otherKey;
  }
}
