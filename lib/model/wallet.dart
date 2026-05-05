import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:logging/logging.dart';
import 'package:uuid/uuid.dart';
import 'package:web_dex/app_config/app_config.dart';

final Logger _walletModelLog = Logger('WalletModel');

class Wallet {
  Wallet({
    required this.id,
    required this.name,
    required this.config,
    this.legacySource,
    this.migratedLegacySource,
    this.legacyWalletExtras,
  });

  factory Wallet.fromJson(Map<String, dynamic> json) => Wallet(
    id: json['id'] as String? ?? '',
    name: json['name'] as String? ?? '',
    config: WalletConfig.fromJson(
      json['config'] as Map<String, dynamic>? ?? {},
    ),
  );

  /// Creates a wallet from a name and the optional parameters.
  /// [name] - The name of the wallet.
  /// [walletType] - The [WalletType] of the wallet. Defaults to [WalletType.iguana].
  /// [activatedCoins] - The list of activated coins. If not provided, the
  /// default list of enabled coins ([enabledByDefaultCoins]) will be used.
  /// [hasBackup] - Whether the wallet has been backed up. Defaults to false.
  factory Wallet.fromName({
    required String name,
    WalletType walletType = WalletType.hdwallet,
    List<String>? activatedCoins,
    bool hasBackup = false,
  }) {
    return Wallet(
      id: const Uuid().v1(),
      name: name,
      config: WalletConfig(
        activatedCoins: activatedCoins ?? enabledByDefaultCoins,
        hasBackup: hasBackup,
        type: walletType,
        seedPhrase: '',
        provenance: WalletProvenance.generated,
        createdAt: DateTime.now(),
      ),
    );
  }

  /// Creates a wallet from a name and the optional parameters.
  factory Wallet.fromConfig({
    required String name,
    required WalletConfig config,
  }) {
    return Wallet(id: const Uuid().v1(), name: name, config: config);
  }

  String id;
  String name;
  WalletConfig config;
  LegacyWalletSource? legacySource;
  MigratedLegacyWalletSource? migratedLegacySource;
  Map<String, dynamic>? legacyWalletExtras;

  bool get isHW =>
      config.type != WalletType.iguana && config.type != WalletType.hdwallet;
  bool get isLegacyWallet => config.isLegacyWallet;
  bool get isNativeLegacyWallet =>
      legacySource?.kind == LegacyWalletSourceKind.nativeApp;
  bool get isSharedPrefsLegacyWallet => isLegacyWallet && !isNativeLegacyWallet;
  bool get hasIncompleteNativeLegacyCleanup =>
      migratedLegacySource?.kind == LegacyWalletSourceKind.nativeApp &&
      migratedLegacySource?.cleanupStatus ==
          LegacyMigrationCleanupStatus.incomplete;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'name': name,
    'config': config.toJson(),
  };

  Wallet copy() {
    return Wallet(
      id: id,
      name: name,
      config: config.copy(),
      legacySource: legacySource,
      migratedLegacySource: migratedLegacySource,
      legacyWalletExtras: legacyWalletExtras == null
          ? null
          : Map<String, dynamic>.from(legacyWalletExtras!),
    );
  }

  Wallet copyWith({
    String? id,
    String? name,
    WalletConfig? config,
    LegacyWalletSource? legacySource,
    MigratedLegacyWalletSource? migratedLegacySource,
    Map<String, dynamic>? legacyWalletExtras,
  }) {
    return Wallet(
      id: id ?? this.id,
      name: name ?? this.name,
      config: config ?? this.config.copy(),
      legacySource: legacySource ?? this.legacySource,
      migratedLegacySource: migratedLegacySource ?? this.migratedLegacySource,
      legacyWalletExtras: legacyWalletExtras ?? this.legacyWalletExtras,
    );
  }
}

class LegacyWalletSource {
  const LegacyWalletSource({
    required this.kind,
    required this.originalWalletName,
    required this.originalWalletId,
  });

  final LegacyWalletSourceKind kind;
  final String originalWalletName;
  final String originalWalletId;

  String get identityKey => '${kind.name}:$originalWalletId';
}

enum LegacyWalletSourceKind { sharedPrefs, nativeApp }

enum LegacyMigrationCleanupStatus {
  complete,
  incomplete;

  factory LegacyMigrationCleanupStatus.fromJson(String? value) {
    switch (value) {
      case 'incomplete':
        return LegacyMigrationCleanupStatus.incomplete;
      case 'complete':
      default:
        return LegacyMigrationCleanupStatus.complete;
    }
  }
}

class MigratedLegacyWalletSource {
  const MigratedLegacyWalletSource({
    required this.kind,
    required this.originalWalletName,
    required this.originalWalletId,
    required this.cleanupStatus,
  });

  final LegacyWalletSourceKind kind;
  final String originalWalletName;
  final String originalWalletId;
  final LegacyMigrationCleanupStatus cleanupStatus;

  String get identityKey => '${kind.name}:$originalWalletId';
}

class WalletConfig {
  WalletConfig({
    required this.seedPhrase,
    required this.activatedCoins,
    required this.hasBackup,
    this.pubKey,
    this.type = WalletType.iguana,
    this.isLegacyWallet = false,
    this.provenance = WalletProvenance.unknown,
    this.createdAt,
  });

  factory WalletConfig.fromJson(Map<String, dynamic> json) {
    return WalletConfig(
      type: WalletType.fromJson(
        json['type'] as String? ?? WalletType.iguana.name,
      ),
      seedPhrase: json['seed_phrase'] as String? ?? '',
      pubKey: json['pub_key'] as String?,
      activatedCoins: List<String>.from(
        json['activated_coins'] as List? ?? <String>[],
      ).toList(),
      hasBackup: json['has_backup'] as bool? ?? false,
      provenance: WalletProvenance.fromJson(
        json['wallet_provenance'] as String? ?? json['provenance'] as String?,
      ),
      createdAt: _parseCreatedAt(
        json['wallet_created_at'] ?? json['created_at'],
      ),
    );
  }

  String seedPhrase;
  String? pubKey;
  List<String> activatedCoins;
  bool hasBackup;
  WalletType type;
  bool isLegacyWallet;
  WalletProvenance provenance;
  DateTime? createdAt;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'type': type.name,
      'seed_phrase': seedPhrase,
      'pub_key': pubKey,
      'activated_coins': activatedCoins,
      'has_backup': hasBackup,
      'provenance': provenance.name,
      'created_at': createdAt?.millisecondsSinceEpoch,
    };
  }

  WalletConfig copy() {
    return WalletConfig(
      activatedCoins: [...activatedCoins],
      hasBackup: hasBackup,
      type: type,
      seedPhrase: seedPhrase,
      pubKey: pubKey,
      // Preserve legacy flag when copying config; losing this flag breaks
      // legacy login flow and can hide the wallet from lists.
      isLegacyWallet: isLegacyWallet,
      provenance: provenance,
      createdAt: createdAt,
    );
  }

  WalletConfig copyWith({
    String? seedPhrase,
    String? pubKey,
    List<String>? activatedCoins,
    bool? hasBackup,
    WalletType? type,
    bool? isLegacyWallet,
    WalletProvenance? provenance,
    DateTime? createdAt,
  }) {
    return WalletConfig(
      seedPhrase: seedPhrase ?? this.seedPhrase,
      pubKey: pubKey ?? this.pubKey,
      activatedCoins: activatedCoins ?? [...this.activatedCoins],
      hasBackup: hasBackup ?? this.hasBackup,
      type: type ?? this.type,
      isLegacyWallet: isLegacyWallet ?? this.isLegacyWallet,
      provenance: provenance ?? this.provenance,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  static DateTime? _parseCreatedAt(dynamic value) {
    if (value is int) {
      return DateTime.fromMillisecondsSinceEpoch(value);
    }
    if (value is String) {
      final asInt = int.tryParse(value);
      if (asInt != null) {
        return DateTime.fromMillisecondsSinceEpoch(asInt);
      }
    }
    return null;
  }
}

enum WalletType {
  iguana,
  hdwallet,
  trezor,
  metamask,
  keplr;

  factory WalletType.fromJson(String json) {
    switch (json) {
      case 'trezor':
        return WalletType.trezor;
      case 'metamask':
        return WalletType.metamask;
      case 'keplr':
        return WalletType.keplr;
      case 'hdwallet':
        return WalletType.hdwallet;
      default:
        return WalletType.iguana;
    }
  }
}

enum WalletProvenance {
  generated,
  imported,
  unknown;

  factory WalletProvenance.fromJson(String? value) {
    switch (value) {
      case 'generated':
        return WalletProvenance.generated;
      case 'imported':
      case 'restored':
      case 'migrated':
        return WalletProvenance.imported;
      default:
        return WalletProvenance.unknown;
    }
  }
}

extension KdfUserWalletExtension on KdfUser {
  Wallet get wallet {
    final walletType = _walletTypeFromMetadataOrAuth(this);
    final provenance = _walletProvenanceFromMetadata(this);
    final createdAt = _walletCreatedAtFromMetadata(this);
    final migratedLegacySource = _migratedLegacySourceFromMetadata(this);
    return Wallet(
      id: walletId.name,
      name: walletId.name,
      config: WalletConfig(
        seedPhrase: '',
        pubKey: walletId.pubkeyHash,
        activatedCoins:
            metadata.valueOrNull<List<String>>('activated_coins') ?? [],
        hasBackup: metadata['has_backup'] as bool? ?? false,
        type: walletType,
        provenance: provenance,
        createdAt: createdAt,
      ),
      migratedLegacySource: migratedLegacySource,
      legacyWalletExtras: _legacyWalletExtrasFromMetadata(this),
    );
  }
}

extension KdfSdkWalletExtension on KomodoDefiSdk {
  Future<Iterable<Wallet>> get wallets async =>
      (await auth.getUsers()).map((user) => user.wallet);
}

WalletType _walletTypeFromMetadataOrAuth(KdfUser user) {
  final metadataType = user.metadata['type'];
  if (metadataType is String && metadataType.isNotEmpty) {
    return WalletType.fromJson(metadataType);
  }

  return user.walletId.isHd ? WalletType.hdwallet : WalletType.iguana;
}

WalletProvenance _walletProvenanceFromMetadata(KdfUser user) {
  final metadataProvenance = user.metadata['wallet_provenance'];
  if (metadataProvenance is String && metadataProvenance.isNotEmpty) {
    return WalletProvenance.fromJson(metadataProvenance);
  }

  final isImported = user.metadata['isImported'];
  if (isImported is bool) {
    return isImported ? WalletProvenance.imported : WalletProvenance.generated;
  }

  return WalletProvenance.unknown;
}

DateTime? _walletCreatedAtFromMetadata(KdfUser user) {
  final createdAtRaw = user.metadata['wallet_created_at'];
  if (createdAtRaw is int) {
    return DateTime.fromMillisecondsSinceEpoch(createdAtRaw);
  }
  if (createdAtRaw is String) {
    final createdAtMs = int.tryParse(createdAtRaw);
    if (createdAtMs != null) {
      return DateTime.fromMillisecondsSinceEpoch(createdAtMs);
    }
  }
  return null;
}

const String legacySourceKindMetadataKey = 'legacy_source_kind';
const String legacySourceWalletIdMetadataKey = 'legacy_source_wallet_id';
const String legacySourceWalletNameMetadataKey = 'legacy_source_wallet_name';
const String legacyCleanupStatusMetadataKey = 'legacy_cleanup_status';
const String legacyWalletExtrasMetadataKey = 'legacy_wallet_extras_v1';

MigratedLegacyWalletSource? _migratedLegacySourceFromMetadata(KdfUser user) {
  final metadataKind = user.metadata[legacySourceKindMetadataKey];
  final metadataWalletId = user.metadata[legacySourceWalletIdMetadataKey];
  final metadataWalletName = user.metadata[legacySourceWalletNameMetadataKey];

  final bool hasKind = metadataKind is String && metadataKind.isNotEmpty;
  final bool hasId = metadataWalletId is String && metadataWalletId.isNotEmpty;
  final bool hasName =
      metadataWalletName is String && metadataWalletName.isNotEmpty;

  if (!hasKind || !hasId || !hasName) {
    final int presentCount = [hasKind, hasId, hasName].where((v) => v).length;
    if (presentCount > 0) {
      _walletModelLog.warning(
        'Partial migration linkage metadata for wallet '
        '"${user.walletId.name}": '
        'kind=${hasKind ? metadataKind : "MISSING"}, '
        'walletId=${hasId ? metadataWalletId : "MISSING"}, '
        'walletName=${hasName ? metadataWalletName : "MISSING"}. '
        'Legacy wallet may still appear as unmigrated.',
      );
    }
    return null;
  }

  final kind = switch (metadataKind) {
    'sharedPrefs' => LegacyWalletSourceKind.sharedPrefs,
    'nativeApp' => LegacyWalletSourceKind.nativeApp,
    _ => null,
  };
  if (kind == null) {
    return null;
  }

  return MigratedLegacyWalletSource(
    kind: kind,
    originalWalletName: metadataWalletName,
    originalWalletId: metadataWalletId,
    cleanupStatus: LegacyMigrationCleanupStatus.fromJson(
      user.metadata[legacyCleanupStatusMetadataKey] as String?,
    ),
  );
}

Map<String, dynamic>? _legacyWalletExtrasFromMetadata(KdfUser user) {
  final rawExtras = user.metadata[legacyWalletExtrasMetadataKey];
  if (rawExtras is Map<String, dynamic> && rawExtras.isNotEmpty) {
    return Map<String, dynamic>.from(rawExtras);
  }
  if (rawExtras is Map && rawExtras.isNotEmpty) {
    return rawExtras.map<String, dynamic>(
      (key, value) => MapEntry(key.toString(), value),
    );
  }
  return null;
}
