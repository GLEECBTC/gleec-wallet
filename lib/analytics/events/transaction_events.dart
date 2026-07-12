import 'package:komodo_defi_types/komodo_defi_type_utils.dart';
import 'package:web_dex/bloc/analytics/analytics_event.dart';

import '../../bloc/analytics/analytics_repo.dart';

// E14: Send flow started
// ------------------------------------------

/// E14: Send flow started
/// Measures when a user initiates a send transaction. Business category: Transactions.
/// Provides insights on transaction funnel start and popular send assets.
class SendInitiatedEventData extends AnalyticsEventData {
  const SendInitiatedEventData({
    required this.asset,
    required this.network,
    required this.amount,
    required this.hdType,
  });

  final String asset;
  final String network;
  final double amount;
  final String hdType;

  @override
  String get name => 'send_initiated';

  @override
  JsonMap get parameters => {
    'asset': asset,
    'network': network,
    'amount': amount,
    'hd_type': hdType,
  };
}

/// E14: Send flow started
class AnalyticsSendInitiatedEvent extends AnalyticsSendDataEvent {
  AnalyticsSendInitiatedEvent({
    required String asset,
    required String network,
    required double amount,
    required String hdType,
  }) : super(
         SendInitiatedEventData(
           asset: asset,
           network: network,
           amount: amount,
           hdType: hdType,
         ),
       );
}

// E15: On-chain send completed
// ------------------------------------------

/// E15: On-chain send completed
/// Measures when an on-chain send transaction is completed successfully. Business category: Transactions.
/// Provides insights on successful sends, volume, and average size.
class SendSucceededEventData extends AnalyticsEventData {
  const SendSucceededEventData({
    required this.asset,
    required this.network,
    required this.amount,
    required this.hdType,
  });

  final String asset;
  final String network;
  final double amount;
  final String hdType;

  @override
  String get name => 'send_success';

  @override
  JsonMap get parameters => {
    'asset': asset,
    'network': network,
    'amount': amount,
    'hd_type': hdType,
  };
}

/// E15: On-chain send completed
class AnalyticsSendSucceededEvent extends AnalyticsSendDataEvent {
  AnalyticsSendSucceededEvent({
    required String asset,
    required String network,
    required double amount,
    required String hdType,
  }) : super(
         SendSucceededEventData(
           asset: asset,
           network: network,
           amount: amount,
           hdType: hdType,
         ),
       );
}

// E16: Send failed / cancelled
// ------------------------------------------

/// E16: Send failed / cancelled
/// Measures when a send transaction fails or is cancelled. Business category: Transactions.
/// Provides insights on error hotspots and UX/network issues.
class SendFailedEventData extends AnalyticsEventData {
  const SendFailedEventData({
    required this.asset,
    required this.network,
    required this.failureReason,
    required this.hdType,
  });

  final String asset;
  final String network;
  final String failureReason;
  final String hdType;

  @override
  String get name => 'send_failure';

  @override
  JsonMap get parameters => {
    'asset': asset,
    'network': network,
    'failure_reason': _formatFailureReason(reason: failureReason),
    'hd_type': hdType,
  };
}

/// E16: Send failed / cancelled
class AnalyticsSendFailedEvent extends AnalyticsSendDataEvent {
  AnalyticsSendFailedEvent({
    required String asset,
    required String network,
    required String failureReason,
    required String hdType,
  }) : super(
         SendFailedEventData(
           asset: asset,
           network: network,
           failureReason: failureReason,
           hdType: hdType,
         ),
       );
}

/// Privacy-minimized lifecycle telemetry for the GasFree rail.
///
/// GasFree authorization and relay data is financially sensitive. This event
/// deliberately excludes asset identifiers, wallet type, addresses, amounts,
/// fees, provider messages, trace IDs, and signed payloads.
class GaslessTransferAnalyticsEventData extends AnalyticsEventData {
  const GaslessTransferAnalyticsEventData({
    required this.stage,
    required this.code,
    required this.retryable,
  });

  final String stage;
  final String code;
  final bool retryable;

  @override
  String get name => 'gasless_transfer_transition';

  @override
  JsonMap get parameters => {
    'stage': _stableAnalyticsToken(stage),
    'code': _stableFailureToken(code) ?? 'unknown',
    'rail': 'tron_gasfree',
    'retryable': retryable,
  };
}

// E17: Swap order submitted
// ------------------------------------------

/// E17: Swap order submitted
/// Measures when a swap order is submitted. Business category: Trading (DEX).
/// Provides insights on DEX funnel start and pair demand.
class SwapInitiatedEventData extends AnalyticsEventData {
  const SwapInitiatedEventData({
    required this.asset,
    required this.secondaryAsset,
    required this.network,
    required this.secondaryNetwork,
    required this.hdType,
  });

  final String asset;
  final String secondaryAsset;
  final String network;
  final String secondaryNetwork;
  final String hdType;

  @override
  String get name => 'swap_initiated';

  @override
  JsonMap get parameters => {
    'asset': asset,
    'secondary_asset': secondaryAsset,
    'network': network,
    'secondary_network': secondaryNetwork,
    'hd_type': hdType,
  };
}

/// E17: Swap order submitted
class AnalyticsSwapInitiatedEvent extends AnalyticsSendDataEvent {
  AnalyticsSwapInitiatedEvent({
    required String asset,
    required String secondaryAsset,
    required String network,
    required String secondaryNetwork,
    required String hdType,
  }) : super(
         SwapInitiatedEventData(
           asset: asset,
           secondaryAsset: secondaryAsset,
           network: network,
           secondaryNetwork: secondaryNetwork,
           hdType: hdType,
         ),
       );
}

// E18: Atomic swap succeeded
// ------------------------------------------

/// E18: Atomic swap succeeded
/// Measures when an atomic swap is completed successfully. Business category: Trading (DEX).
/// Provides insights on trading volume and fee revenue.
class SwapSucceededEventData extends AnalyticsEventData {
  const SwapSucceededEventData({
    required this.asset,
    required this.secondaryAsset,
    required this.network,
    required this.secondaryNetwork,
    required this.amount,
    required this.fee,
    required this.hdType,
    this.durationMs,
  });

  final String asset;
  final String secondaryAsset;
  final String network;
  final String secondaryNetwork;
  final double amount;
  final double fee;
  final String hdType;
  final int? durationMs;

  @override
  String get name => 'swap_success';

  @override
  JsonMap get parameters => {
    'asset': asset,
    'secondary_asset': secondaryAsset,
    'network': network,
    'secondary_network': secondaryNetwork,
    'amount': amount,
    'fee': fee,
    'hd_type': hdType,
    if (durationMs != null) 'duration_ms': durationMs,
  };
}

/// E18: Atomic swap succeeded
class AnalyticsSwapSucceededEvent extends AnalyticsSendDataEvent {
  AnalyticsSwapSucceededEvent({
    required String asset,
    required String secondaryAsset,
    required String network,
    required String secondaryNetwork,
    required double amount,
    required double fee,
    required String hdType,
    int? durationMs,
  }) : super(
         SwapSucceededEventData(
           asset: asset,
           secondaryAsset: secondaryAsset,
           network: network,
           secondaryNetwork: secondaryNetwork,
           amount: amount,
           fee: fee,
           hdType: hdType,
           durationMs: durationMs,
         ),
       );
}

// E19: Swap failed
// ------------------------------------------

/// E19: Swap failed
/// Measures when an atomic swap fails. Business category: Trading (DEX).
/// Provides insights on liquidity gaps and technical/UX blockers.
class SwapFailedEventData extends AnalyticsEventData {
  const SwapFailedEventData({
    required this.asset,
    required this.secondaryAsset,
    required this.network,
    required this.secondaryNetwork,
    required this.failureStage,
    this.failureDetail,
    required this.hdType,
    this.durationMs,
  });

  final String asset;
  final String secondaryAsset;
  final String network;
  final String secondaryNetwork;
  final String failureStage;
  final String? failureDetail;
  final String hdType;
  final int? durationMs;

  @override
  String get name => 'swap_failure';

  @override
  JsonMap get parameters => {
    'asset': asset,
    'secondary_asset': secondaryAsset,
    'network': network,
    'secondary_network': secondaryNetwork,
    'failure_reason': _formatFailureReason(
      stage: failureStage,
      reason: failureDetail,
    ),
    'hd_type': hdType,
    if (durationMs != null) 'duration_ms': durationMs,
  };
}

/// E19: Swap failed
class AnalyticsSwapFailedEvent extends AnalyticsSendDataEvent {
  AnalyticsSwapFailedEvent({
    required String asset,
    required String secondaryAsset,
    required String network,
    required String secondaryNetwork,
    required String failureStage,
    String? failureDetail,
    required String hdType,
    int? durationMs,
  }) : super(
         SwapFailedEventData(
           asset: asset,
           secondaryAsset: secondaryAsset,
           network: network,
           secondaryNetwork: secondaryNetwork,
           failureStage: failureStage,
           failureDetail: failureDetail,
           hdType: hdType,
           durationMs: durationMs,
         ),
       );
}

String _formatFailureReason({String? stage, String? reason, String? code}) {
  final parts = <String>[];

  String? sanitizeStage(String? value) {
    if (value == null) return null;
    final normalized = value.trim().toLowerCase().replaceAll(
      RegExp(r'[^a-z0-9_.-]+'),
      '_',
    );
    if (normalized.isEmpty) return null;
    return normalized.length > 48 ? normalized.substring(0, 48) : normalized;
  }

  final sanitizedStage = sanitizeStage(stage);
  final sanitizedReason = _stableFailureToken(reason);
  final sanitizedCode = _stableFailureToken(code);

  if (sanitizedStage != null) {
    parts.add('stage:$sanitizedStage');
  }
  if (sanitizedReason != null) {
    parts.add('reason:$sanitizedReason');
  }
  if (sanitizedCode != null && sanitizedCode != sanitizedReason) {
    parts.add('code:$sanitizedCode');
  }

  if (parts.isEmpty) {
    return 'reason:unknown';
  }
  return parts.join('|');
}

/// Converts potentially sensitive transport/provider messages into a bounded
/// analytics category. Raw GasFree errors can contain addresses, signed
/// payload fields, upstream URLs, or correlation data and must never leave the
/// device as analytics dimensions.
String? _stableFailureToken(String? raw) {
  if (raw == null || raw.trim().isEmpty) return null;
  final value = raw.toLowerCase();

  const stableCodes = {
    'started',
    'confirmed',
    'rejected_before_relay',
    'failed_final',
  };
  if (stableCodes.contains(value.trim())) return value.trim();

  if (value.contains('cancel')) return 'cancelled';
  if (value.contains('timeout') || value.contains('timed out')) {
    return 'timeout';
  }
  if (value.contains('insufficient') ||
      value.contains('not enough') ||
      value.contains('below fee')) {
    return 'insufficient_funds';
  }
  if (value.contains('expired') || value.contains('deadline')) {
    return 'authorization_expired';
  }
  if (value.contains('pending') || value.contains('in progress')) {
    return 'transfer_pending';
  }
  if (value.contains('mismatch') ||
      value.contains('tamper') ||
      value.contains('invalid signature')) {
    return 'security_mismatch';
  }
  if (value.contains('unauthor') ||
      value.contains('forbidden') ||
      value.contains('authentication') ||
      RegExp(r'(^|\D)(401|403)(\D|$)').hasMatch(value)) {
    return 'authentication_failed';
  }
  if (value.contains('unsupported') || value.contains('no such coin')) {
    return 'unsupported';
  }
  if (value.contains('invalid address')) return 'invalid_address';
  if (value.contains('unavailable') ||
      value.contains('provider') ||
      value.contains('relay') ||
      value.contains('connection') ||
      value.contains('network')) {
    return 'service_unavailable';
  }

  return 'unknown';
}

String _stableAnalyticsToken(String raw) {
  final token = raw.trim().toLowerCase().replaceAll(
    RegExp(r'[^a-z0-9_.-]+'),
    '_',
  );
  if (token.isEmpty) return 'unknown';
  return token.length <= 48 ? token : token.substring(0, 48);
}
