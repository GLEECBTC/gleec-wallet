import 'dart:async';

import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';
import 'package:web_dex/features/unified_swap/infrastructure/unified_swap_config.dart';
import 'package:web_dex/mm2/mm2_api/rpc/version/version_request.dart';
import 'package:web_dex/mm2/mm2_api/rpc/version/version_response.dart';
import 'package:web_dex/shared/utils/utils.dart';

final MM2 mm2 = MM2();

final class MM2 {
  MM2() {
    final unifiedSwap = UnifiedSwapConfig.fromEnvironment();
    _kdfSdk = KomodoDefiSdk(
      config: KomodoDefiSdkConfig(
        // Syncing pre-activation coin states is not yet implemented,
        // so we disable it for now.
        // TODO: sync pre-activation of coins (show activating coins in list)
        preActivateHistoricalAssets: false,
        preActivateDefaultAssets: false,
        externalExecution: _externalExecutionConfig(unifiedSwap),
      ),
      onLog: _handleSdkLog,
    );
  }

  late final KomodoDefiSdk _kdfSdk;
  bool _isInitializing = false;
  final Completer<KomodoDefiSdk> _initCompleter = Completer<KomodoDefiSdk>();

  Future<bool> isSignedIn() => _kdfSdk.auth.isSignedIn();

  /// Dispose the SDK and clean up resources
  Future<void> dispose() async {
    try {
      await _kdfSdk.dispose();
      log('KomodoDefiSdk disposed successfully');
    } catch (e) {
      log('Error disposing KomodoDefiSdk: $e', isError: true);
    }
  }

  Future<KomodoDefiSdk> initialize() async {
    if (_initCompleter.isCompleted) return _kdfSdk;
    if (_isInitializing) return _initCompleter.future;

    try {
      _isInitializing = true;

      await _kdfSdk.initialize();
      // Hack to ensure that kdf is running in noauth mode
      await _kdfSdk.auth.getUsers();

      _initCompleter.complete(_kdfSdk);
      return _kdfSdk;
    } catch (e) {
      _initCompleter.completeError(e);
      rethrow;
    } finally {
      _isInitializing = false;
    }
  }

  Future<String> version() async {
    final JsonMap responseJson = await call(VersionRequest());
    final VersionResponse response = VersionResponse.fromJson(responseJson);

    return response.result;
  }

  @Deprecated(
    'Use KomodoDefiSdk.client.rpc or KomodoDefiSdk.client.executeRpc '
    'instead. This method is the legacy way of calling RPC methods which '
    'injects an empty user password into the legacy models which override '
    'the legacy base RPC request model',
  )
  Future<JsonMap> call(dynamic request) async {
    try {
      final dynamic requestWithUserpass = _assertPass(request);
      final JsonMap jsonRequest = requestWithUserpass is Map
          ? JsonMap.from(requestWithUserpass)
          // ignore: avoid_dynamic_calls
          : (requestWithUserpass?.toJson != null
                // ignore: avoid_dynamic_calls
                ? requestWithUserpass.toJson() as JsonMap
                : requestWithUserpass as JsonMap);

      return await _kdfSdk.client.executeRpc(jsonRequest);
    } catch (e) {
      log('RPC call error: $e', path: 'mm2 => call', isError: true).ignore();
      rethrow;
    }
  }

  // this is a necessary evil for now becuase of the RPC models that override
  // or use the `late String? userpass` field, which would require refactoring
  // most of the RPC models and directly affected code.
  dynamic _assertPass(dynamic req) {
    if (req is List) {
      for (final dynamic element in req) {
        // ignore: avoid_dynamic_calls
        element.userpass = '';
      }
    } else {
      if (req is Map) {
        req['userpass'] = '';
      } else {
        // ignore: avoid_dynamic_calls
        req.userpass = '';
      }
    }

    return req;
  }

  void _handleSdkLog(String message) {
    log(message, path: 'KomodoDefiSdk').ignore();
  }
}

ExternalExecutionStartupConfig _externalExecutionConfig(
  UnifiedSwapConfig config,
) {
  if (!config.canStartKdfExternalExecution) {
    return const ExternalExecutionStartupConfig();
  }
  final transport = switch (config.transport) {
    UnifiedSwapLifiTransport.gleecProxy => LifiTransport.gleecProxy(
      config.proxyUrl!,
    ),
    UnifiedSwapLifiTransport.direct => const LifiTransport.direct(),
    UnifiedSwapLifiTransport.invalid => throw StateError(
      'Invalid Li.Fi transport reached KDF startup',
    ),
  };
  return ExternalExecutionStartupConfig(
    lifi: LifiStartupConfig(
      enabled: config.kdfLifiEnabled,
      caseAEnabled: config.kdfLifiCaseAEnabled,
      transport: transport,
      allowDirectNonProduction: config.allowDirectLifiNonProduction,
    ),
  );
}

// 0 - MM2 is not running yet.
// 1 - MM2 is running, but no context yet.
// 2 - MM2 is running, but no RPC yet.
// 3 - MM2's RPC is up.
enum MM2Status {
  isNotRunningYet,
  runningWithoutContext,
  runningWithoutRPC,
  rpcIsUp;

  static MM2Status fromInt(int status) {
    switch (status) {
      case 0:
        return isNotRunningYet;
      case 1:
        return runningWithoutContext;
      case 2:
        return runningWithoutRPC;
      case 3:
        return rpcIsUp;
      default:
        return isNotRunningYet;
    }
  }
}
