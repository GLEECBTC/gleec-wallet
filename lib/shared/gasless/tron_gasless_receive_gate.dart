import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:web_dex/shared/constants.dart';

/// Stable, privacy-safe reasons for the GasFree receive capability decision.
///
/// These codes intentionally contain no endpoint, provider response, address,
/// or wallet data, so they are safe to use in diagnostics and metrics.
enum GaslessReceiveReasonCode {
  ready('ready'),
  assetUnsupported('asset_unsupported'),
  buildFeatureDisabled('build_feature_disabled'),
  receiveBuildDisabled('receive_build_disabled'),
  boundRelayRequired('bound_relay_required'),
  providerConfigurationInvalid('provider_configuration_invalid'),
  controlEndpointMissing('control_endpoint_missing'),
  controlEndpointInvalid('control_endpoint_invalid'),
  localBindingInvalid('local_binding_invalid'),
  remoteEnabled('remote_enabled'),
  remoteDisabled('remote_disabled'),
  remoteUnavailable('remote_unavailable'),
  remoteTimeout('remote_timeout'),
  remoteHttpRejected('remote_http_rejected'),
  remoteContentTypeInvalid('remote_content_type_invalid'),
  remoteResponseTooLarge('remote_response_too_large'),
  remoteMalformed('remote_malformed'),
  remoteSchemaMismatch('remote_schema_mismatch'),
  remoteBindingMismatch('remote_binding_mismatch'),
  remoteExpired('remote_expired'),
  remoteExpiryTooFar('remote_expiry_too_far'),
  custodyAddressMissing('custody_address_missing'),
  accountStatusUnavailable('account_status_unavailable'),
  providerUnavailable('provider_unavailable'),
  providerTemporarilyUnavailable('provider_temporarily_unavailable'),
  tokenUnsupported('token_unsupported'),
  tokenDecimalsMismatch('token_decimals_mismatch'),
  custodyAddressMismatch('custody_address_mismatch');

  const GaslessReceiveReasonCode(this.code);

  final String code;
}

enum TronGaslessReceiveGateOutcome {
  enabled,
  disabled,
  unavailable,
  invalid,
  expired,
}

class TronGaslessReceiveGateDecision {
  const TronGaslessReceiveGateDecision({
    required this.outcome,
    required this.reason,
    this.expiresAt,
  });

  final TronGaslessReceiveGateOutcome outcome;
  final GaslessReceiveReasonCode reason;
  final DateTime? expiresAt;

  bool get receiveEnabled => outcome == TronGaslessReceiveGateOutcome.enabled;
}

abstract interface class TronGaslessReceiveGate {
  Future<TronGaslessReceiveGateDecision> evaluate();

  void dispose();
}

/// Fetches the short-lived production control document for new GasFree
/// receives.
///
/// The service is deliberately fail-closed. It never returns `enabled` for a
/// redirect, transport error, non-JSON body, unknown field, stale document, or
/// document bound to a different network/provider. Existing custody access is
/// outside this service and must remain visible to callers.
class HttpTronGaslessReceiveGate implements TronGaslessReceiveGate {
  HttpTronGaslessReceiveGate({
    required String endpoint,
    required String expectedNetwork,
    required String expectedServiceProvider,
    http.Client? httpClient,
    DateTime Function()? now,
    Duration timeout = const Duration(seconds: 3),
    Duration maximumConfigValidity = const Duration(minutes: 5),
    int maximumResponseBytes = 4096,
  }) : _endpoint = endpoint,
       _expectedNetwork = expectedNetwork,
       _expectedServiceProvider = expectedServiceProvider,
       _client = httpClient ?? http.Client(),
       _ownsClient = httpClient == null,
       _now = now ?? DateTime.now,
       _timeout = timeout,
       _maximumConfigValidity = maximumConfigValidity,
       _maximumResponseBytes = maximumResponseBytes;

  static const _expectedFields = <String>{
    'schemaVersion',
    'receiveEnabled',
    'expiresAt',
    'network',
    'serviceProvider',
  };
  static const _maximumRequestTimeout = Duration(seconds: 10);
  static const _maximumAllowedValidity = Duration(minutes: 15);

  final String _endpoint;
  final String _expectedNetwork;
  final String _expectedServiceProvider;
  final http.Client _client;
  final bool _ownsClient;
  final DateTime Function() _now;
  final Duration _timeout;
  final Duration _maximumConfigValidity;
  final int _maximumResponseBytes;

  @override
  Future<TronGaslessReceiveGateDecision> evaluate() async {
    final endpoint = parseTronGaslessControlEndpoint(_endpoint);
    if (endpoint == null) {
      return TronGaslessReceiveGateDecision(
        outcome: TronGaslessReceiveGateOutcome.invalid,
        reason: _endpoint.trim().isEmpty
            ? GaslessReceiveReasonCode.controlEndpointMissing
            : GaslessReceiveReasonCode.controlEndpointInvalid,
      );
    }

    if ((_expectedNetwork != 'tron' && _expectedNetwork != 'nile') ||
        !isValidTronServiceProvider(_expectedServiceProvider) ||
        _timeout <= Duration.zero ||
        _timeout > _maximumRequestTimeout ||
        _maximumConfigValidity <= Duration.zero ||
        _maximumConfigValidity > _maximumAllowedValidity ||
        _maximumResponseBytes < 256 ||
        _maximumResponseBytes > 16 * 1024) {
      return const TronGaslessReceiveGateDecision(
        outcome: TronGaslessReceiveGateOutcome.invalid,
        reason: GaslessReceiveReasonCode.localBindingInvalid,
      );
    }

    try {
      return await _fetch(endpoint).timeout(_timeout);
    } on TimeoutException {
      return const TronGaslessReceiveGateDecision(
        outcome: TronGaslessReceiveGateOutcome.unavailable,
        reason: GaslessReceiveReasonCode.remoteTimeout,
      );
    } catch (_) {
      return const TronGaslessReceiveGateDecision(
        outcome: TronGaslessReceiveGateOutcome.unavailable,
        reason: GaslessReceiveReasonCode.remoteUnavailable,
      );
    }
  }

  Future<TronGaslessReceiveGateDecision> _fetch(Uri endpoint) async {
    final request = http.Request('GET', endpoint)
      ..followRedirects = false
      ..headers.addAll(const {
        'Accept': 'application/json',
        'Cache-Control': 'no-cache',
      });
    final response = await _client.send(request);

    if (response.statusCode != 200) {
      await _cancelBody(response.stream);
      return const TronGaslessReceiveGateDecision(
        outcome: TronGaslessReceiveGateOutcome.unavailable,
        reason: GaslessReceiveReasonCode.remoteHttpRejected,
      );
    }

    final contentType = response.headers['content-type']
        ?.split(';')
        .first
        .trim()
        .toLowerCase();
    if (contentType != 'application/json') {
      await _cancelBody(response.stream);
      return const TronGaslessReceiveGateDecision(
        outcome: TronGaslessReceiveGateOutcome.invalid,
        reason: GaslessReceiveReasonCode.remoteContentTypeInvalid,
      );
    }

    final declaredLength = int.tryParse(
      response.headers['content-length'] ?? '',
    );
    if (declaredLength != null && declaredLength > _maximumResponseBytes) {
      await _cancelBody(response.stream);
      return const TronGaslessReceiveGateDecision(
        outcome: TronGaslessReceiveGateOutcome.invalid,
        reason: GaslessReceiveReasonCode.remoteResponseTooLarge,
      );
    }

    final bodyBytes = await _readBounded(response.stream);
    if (bodyBytes == null) {
      return const TronGaslessReceiveGateDecision(
        outcome: TronGaslessReceiveGateOutcome.invalid,
        reason: GaslessReceiveReasonCode.remoteResponseTooLarge,
      );
    }

    Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(bodyBytes, allowMalformed: false));
    } catch (_) {
      return const TronGaslessReceiveGateDecision(
        outcome: TronGaslessReceiveGateOutcome.invalid,
        reason: GaslessReceiveReasonCode.remoteMalformed,
      );
    }

    if (decoded is! Map<String, dynamic> ||
        decoded.length != _expectedFields.length ||
        !_expectedFields.every(decoded.containsKey) ||
        decoded['schemaVersion'] is! int ||
        decoded['schemaVersion'] != 1 ||
        decoded['receiveEnabled'] is! bool ||
        decoded['expiresAt'] is! String ||
        decoded['network'] is! String ||
        decoded['serviceProvider'] is! String) {
      return const TronGaslessReceiveGateDecision(
        outcome: TronGaslessReceiveGateOutcome.invalid,
        reason: GaslessReceiveReasonCode.remoteSchemaMismatch,
      );
    }

    if (decoded['network'] != _expectedNetwork ||
        decoded['serviceProvider'] != _expectedServiceProvider) {
      return const TronGaslessReceiveGateDecision(
        outcome: TronGaslessReceiveGateOutcome.invalid,
        reason: GaslessReceiveReasonCode.remoteBindingMismatch,
      );
    }

    final expiresAtRaw = decoded['expiresAt'] as String;
    final isCanonicalUtcTimestamp = RegExp(
      r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,6})?Z$',
    ).hasMatch(expiresAtRaw);
    final expiresAt = isCanonicalUtcTimestamp
        ? DateTime.tryParse(expiresAtRaw)?.toUtc()
        : null;
    if (expiresAt == null) {
      return const TronGaslessReceiveGateDecision(
        outcome: TronGaslessReceiveGateOutcome.invalid,
        reason: GaslessReceiveReasonCode.remoteSchemaMismatch,
      );
    }

    final now = _now().toUtc();
    if (!expiresAt.isAfter(now)) {
      return TronGaslessReceiveGateDecision(
        outcome: TronGaslessReceiveGateOutcome.expired,
        reason: GaslessReceiveReasonCode.remoteExpired,
        expiresAt: expiresAt,
      );
    }
    if (expiresAt.difference(now) > _maximumConfigValidity) {
      return TronGaslessReceiveGateDecision(
        outcome: TronGaslessReceiveGateOutcome.invalid,
        reason: GaslessReceiveReasonCode.remoteExpiryTooFar,
        expiresAt: expiresAt,
      );
    }

    final receiveEnabled = decoded['receiveEnabled'] as bool;
    return TronGaslessReceiveGateDecision(
      outcome: receiveEnabled
          ? TronGaslessReceiveGateOutcome.enabled
          : TronGaslessReceiveGateOutcome.disabled,
      reason: receiveEnabled
          ? GaslessReceiveReasonCode.remoteEnabled
          : GaslessReceiveReasonCode.remoteDisabled,
      expiresAt: expiresAt,
    );
  }

  Future<List<int>?> _readBounded(Stream<List<int>> stream) async {
    final bytes = <int>[];
    await for (final chunk in stream) {
      if (bytes.length + chunk.length > _maximumResponseBytes) return null;
      bytes.addAll(chunk);
    }
    return bytes;
  }

  Future<void> _cancelBody(Stream<List<int>> stream) async {
    try {
      final subscription = stream.listen((_) {});
      await subscription.cancel();
    } catch (_) {
      // The decision is already fail-closed. Cleanup failure must not expose or
      // replace the stable reason with transport/provider details.
    }
  }

  @override
  void dispose() {
    if (_ownsClient) _client.close();
  }
}
