import 'package:flutter/foundation.dart';
import 'package:web_dex/features/unified_swap/infrastructure/unified_swap_config.dart';

enum UnifiedSwapChainFamily { evm, tron, utxo, solana, sui, other, unknown }

enum UnifiedSwapAssetKind { native, token, unknown }

enum UnifiedSwapWalletKind {
  softwareIguana,
  softwareHd,
  hardware,
  walletConnect,
  metaMask,
  other,
  unknown,
}

enum UnifiedSwapSourceSelectorKind { active, hd, unknown }

enum UnifiedSwapComplianceDecision { allowed, blocked, unknown }

enum UnifiedSwapExecutorKind { evmSoftwareKey, unsupported, unknown }

enum UnifiedSwapExecutionMode { signOnly, signAndBroadcast, unknown }

enum UnifiedSwapCapabilityDenial {
  unauthenticated,
  unsupportedWallet,
  invalidSourceIdentity,
  sourceNotActivated,
  sourceBlocked,
  destinationBlocked,
  capabilityUnavailable,
  capabilityIdentityMismatch,
  unsupportedSelector,
  unsupportedExecutor,
  quoteDisabled,
  initDisabled,
}

@immutable
class UnifiedSwapAssetIdentity {
  const UnifiedSwapAssetIdentity({
    required this.ticker,
    required this.chainFamily,
    required this.chainId,
    required this.kind,
    required this.decimals,
    this.contractAddress,
    this.rawChainFamilyDiscriminator,
    this.rawKindDiscriminator,
  });

  final String ticker;
  final UnifiedSwapChainFamily chainFamily;
  final String chainId;
  final UnifiedSwapAssetKind kind;
  final int decimals;
  final String? contractAddress;
  final String? rawChainFamilyDiscriminator;
  final String? rawKindDiscriminator;

  bool get isValidEvmV1 {
    if (ticker.isEmpty ||
        ticker.trim() != ticker ||
        ticker.length > 64 ||
        chainFamily != UnifiedSwapChainFamily.evm ||
        !RegExp(r'^[1-9][0-9]*$').hasMatch(chainId) ||
        decimals < 0 ||
        decimals > 255) {
      return false;
    }
    switch (kind) {
      case UnifiedSwapAssetKind.native:
        return contractAddress == null;
      case UnifiedSwapAssetKind.token:
        return contractAddress != null &&
            RegExp(r'^0x[0-9a-fA-F]{40}$').hasMatch(contractAddress!);
      case UnifiedSwapAssetKind.unknown:
        return false;
    }
  }

  bool sameIdentity(UnifiedSwapAssetIdentity other) =>
      ticker == other.ticker &&
      chainFamily == other.chainFamily &&
      chainId == other.chainId &&
      kind == other.kind &&
      decimals == other.decimals &&
      _normalizedContract == other._normalizedContract &&
      rawChainFamilyDiscriminator == other.rawChainFamilyDiscriminator &&
      rawKindDiscriminator == other.rawKindDiscriminator;

  String? get _normalizedContract => contractAddress?.toLowerCase();
}

@immutable
class UnifiedSwapRuntimeCapability {
  const UnifiedSwapRuntimeCapability({
    required this.source,
    required this.destination,
    required this.routeSupported,
    required this.sourceSelector,
    required this.executor,
    this.supportedModes = const [],
    this.isUnknownVariant = false,
  });

  final UnifiedSwapAssetIdentity source;
  final UnifiedSwapAssetIdentity destination;
  final bool routeSupported;
  final UnifiedSwapSourceSelectorKind sourceSelector;
  final UnifiedSwapExecutorKind executor;
  final List<UnifiedSwapExecutionMode> supportedModes;
  final bool isUnknownVariant;

  bool get canSignAndBroadcast =>
      supportedModes.contains(UnifiedSwapExecutionMode.signAndBroadcast) &&
      !supportedModes.contains(UnifiedSwapExecutionMode.unknown);
}

@immutable
class UnifiedSwapCapabilityContext {
  const UnifiedSwapCapabilityContext({
    required this.authenticated,
    required this.walletKind,
    required this.source,
    required this.destination,
    required this.sourceActivated,
    required this.sourceCompliance,
    required this.destinationCompliance,
    required this.capability,
  });

  final bool authenticated;
  final UnifiedSwapWalletKind walletKind;
  final UnifiedSwapAssetIdentity source;
  final UnifiedSwapAssetIdentity destination;
  final bool sourceActivated;
  final UnifiedSwapComplianceDecision sourceCompliance;
  final UnifiedSwapComplianceDecision destinationCompliance;
  final UnifiedSwapRuntimeCapability? capability;
}

@immutable
class UnifiedSwapCapabilityDecision {
  const UnifiedSwapCapabilityDecision.allowed() : denial = null;
  const UnifiedSwapCapabilityDecision.denied(this.denial);

  final UnifiedSwapCapabilityDenial? denial;
  bool get isAllowed => denial == null;
}

/// Intersects product switches, wallet/compliance policy, and exact KDF
/// capability data. Every missing or unknown input fails closed.
class UnifiedSwapCapabilityPolicy {
  const UnifiedSwapCapabilityPolicy();

  UnifiedSwapCapabilityDecision evaluate(
    UnifiedSwapCapabilityContext context, {
    required UnifiedSwapConfig config,
    required bool forExecution,
  }) {
    if (!context.authenticated) {
      return const UnifiedSwapCapabilityDecision.denied(
        UnifiedSwapCapabilityDenial.unauthenticated,
      );
    }
    if (context.walletKind != UnifiedSwapWalletKind.softwareIguana &&
        context.walletKind != UnifiedSwapWalletKind.softwareHd) {
      return const UnifiedSwapCapabilityDecision.denied(
        UnifiedSwapCapabilityDenial.unsupportedWallet,
      );
    }
    if (!context.source.isValidEvmV1) {
      return const UnifiedSwapCapabilityDecision.denied(
        UnifiedSwapCapabilityDenial.invalidSourceIdentity,
      );
    }
    if (!context.sourceActivated) {
      return const UnifiedSwapCapabilityDecision.denied(
        UnifiedSwapCapabilityDenial.sourceNotActivated,
      );
    }
    if (context.sourceCompliance != UnifiedSwapComplianceDecision.allowed) {
      return const UnifiedSwapCapabilityDecision.denied(
        UnifiedSwapCapabilityDenial.sourceBlocked,
      );
    }
    if (context.destinationCompliance !=
        UnifiedSwapComplianceDecision.allowed) {
      return const UnifiedSwapCapabilityDecision.denied(
        UnifiedSwapCapabilityDenial.destinationBlocked,
      );
    }
    final capability = context.capability;
    if (capability == null ||
        capability.isUnknownVariant ||
        !capability.routeSupported) {
      return const UnifiedSwapCapabilityDecision.denied(
        UnifiedSwapCapabilityDenial.capabilityUnavailable,
      );
    }
    if (!capability.source.sameIdentity(context.source) ||
        !capability.destination.sameIdentity(context.destination)) {
      return const UnifiedSwapCapabilityDecision.denied(
        UnifiedSwapCapabilityDenial.capabilityIdentityMismatch,
      );
    }
    if (capability.sourceSelector != UnifiedSwapSourceSelectorKind.active &&
        capability.sourceSelector != UnifiedSwapSourceSelectorKind.hd) {
      return const UnifiedSwapCapabilityDecision.denied(
        UnifiedSwapCapabilityDenial.unsupportedSelector,
      );
    }
    if (capability.executor != UnifiedSwapExecutorKind.evmSoftwareKey) {
      return const UnifiedSwapCapabilityDecision.denied(
        UnifiedSwapCapabilityDenial.unsupportedExecutor,
      );
    }
    if (!capability.canSignAndBroadcast) {
      return const UnifiedSwapCapabilityDecision.denied(
        UnifiedSwapCapabilityDenial.unsupportedExecutor,
      );
    }
    if (!config.canQuote) {
      return const UnifiedSwapCapabilityDecision.denied(
        UnifiedSwapCapabilityDenial.quoteDisabled,
      );
    }
    if (forExecution && !config.canExecute) {
      return const UnifiedSwapCapabilityDecision.denied(
        UnifiedSwapCapabilityDenial.initDisabled,
      );
    }
    return const UnifiedSwapCapabilityDecision.allowed();
  }
}
