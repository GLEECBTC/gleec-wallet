import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show AssetBundle;
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart'
    show GaslessServiceKomodoProxy, TronGaslessProviderConfig, RpcDispatchGuard;
import 'package:web_dex/mm2/mm2_api/rpc/version/version_request.dart';
import 'package:web_dex/mm2/mm2_api/rpc/version/version_response.dart';
import 'package:web_dex/app_config/kdf_data_directory.dart';
import 'package:web_dex/app_config/solana_build_config.dart';
import 'package:web_dex/services/wallet_access/wallet_operation_gate.dart';
import 'package:web_dex/shared/constants.dart';
import 'package:web_dex/shared/swap/lifi_integrator_policy.dart';
import 'package:web_dex/shared/gasless/tron_gasless_policy.dart';
import 'package:web_dex/shared/utils/utils.dart';

final MM2 mm2 = MM2();

TronGaslessProviderConfig buildGleecTronGaslessProviderConfig({
  required String baseUrl,
  required String serviceProvider,
}) {
  return TronGaslessProviderConfig(
    baseUrl: baseUrl.trim(),
    service: const GaslessServiceKomodoProxy(),
    serviceProvider: serviceProvider.trim(),
    requestTimeoutMs: 10000,
  );
}

final class MM2 {
  MM2({
    KomodoDefiSdk? sdk,
    SolanaBuildConfig solana = SolanaBuildConfig.environment,
    AssetBundle? assets,
  }) : _solana = solana,
       _assetBundle = assets {
    solana.validate();
    _kdfSdk =
        sdk ??
        createSdk(
          config: KomodoDefiSdkConfig(
            solanaCapabilities: solana.capabilities,
            // Only a candidate's catalog snapshot is frozen and isolated;
            // production keeps the updatable catalog and default storage.
            assetsAutoUpdate: !solana.isCandidate,
            assetsStorageNamespace: solana.isCandidate
                ? solana.storageNamespace
                : null,
            initialActivationPolicy: ActivationPolicySnapshot(
              status: ActivationPolicyStatus.loading,
            ),
            // Syncing pre-activation coin states is not yet implemented,
            // so we disable it for now.
            // TODO: sync pre-activation of coins (show activating coins in list)
            preActivateHistoricalAssets: false,
            preActivateDefaultAssets: false,
            tronGaslessProvider: _tronGaslessProviderConfig(),
            assetConfigTransform: applyGleecTronGaslessActivationConfig,
            lifiProxyUrl: _lifiProxyUrl(),
            lifiIntegrator: gleecLifiIntegratorConfig(),
            desktopDataDirectory: gleecKdfDesktopDataDirectory,
          ),
          onLog: _handleSdkLog,
        );
  }

  /// Builds the SDK. Tests swap it to see the configuration the app passes.
  @visibleForTesting
  static KomodoDefiSdk Function({
    KomodoDefiSdkConfig? config,
    void Function(String)? onLog,
  })
  createSdk = ({config, onLog}) => KomodoDefiSdk(config: config, onLog: onLog);

  String? _lifiProxyUrl() {
    final url = validatedLifiProxyUrl(lifiProxyUrl);
    if (url == null && lifiProxyUrl.trim().isNotEmpty) {
      // Not the value itself: it may be the credential that got it refused.
      log(
        'LIFI_PROXY_URL ignored: it must be HTTPS, without credentials, a '
        'query or a fragment. Routed swaps use the public LI.FI API.',
      ).ignore();
    }
    return url;
  }

  TronGaslessProviderConfig? _tronGaslessProviderConfig() {
    if (!hasValidTronGaslessProviderConfig) return null;

    final baseUrl = tronGaslessBaseUrl.trim();

    // GasFree requires server-side credentials, so route through KDF's
    // komodo_proxy rail (libp2p-key auth, no secrets on the client). The base
    // URL is the GasFree endpoint itself (the proxy's /gasfree mount); KDF
    // preserves it as-is and appends api/v1/...; see [tronGaslessBaseUrl].
    return buildGleecTronGaslessProviderConfig(
      baseUrl: baseUrl,
      serviceProvider: tronGaslessServiceProvider.trim(),
    );
  }

  final SolanaBuildConfig _solana;
  // Null reads the app's root bundle.
  final AssetBundle? _assetBundle;
  late final KomodoDefiSdk _kdfSdk;
  Future<KomodoDefiSdk>? _initialization;

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

  /// Every caller observes the same initialization, including its failure.
  /// A failed catalog or engine check must never turn into a usable SDK on a
  /// later call, and must not create a second unobserved error future.
  Future<KomodoDefiSdk> initialize() => _initialization ??= _initialize();

  Future<KomodoDefiSdk> _initialize() async {
    if (kIsWeb) {
      _solana.verifyPreviewOrigin(Uri.base);
    }
    await _solana.verifyCatalog(bundle: _assetBundle);
    await _kdfSdk.initialize();
    // Hack to ensure that kdf is running in noauth mode
    await _kdfSdk.auth.getUsers();
    if (_solana.enabled) await _verifySolanaEngine();

    return _kdfSdk;
  }

  /// Refuses a KDF other than the one this build packaged, or a candidate's
  /// manifest engine.
  Future<void> _verifySolanaEngine() async {
    final engineVersion = await version();
    if (engineVersion.isEmpty) {
      // An error reply has no result; it says nothing about which engine runs.
      throw StateError(
        'KDF did not report its version, so the Solana engine check could not '
        'run.',
      );
    }
    final expected = await _solana.expectedEngineCommit(bundle: _assetBundle);
    if (!_solana.isCandidate &&
        expected != SolanaBuildConfig.productionEngineCommit) {
      log(
        'Solana runs on KDF $expected, not on the reviewed production engine '
        '${SolanaBuildConfig.productionEngineCommit}.',
        path: 'mm2 => initialize',
      ).ignore();
    }
    _solana.verifyEngineVersion(engineVersion, expectedCommit: expected);
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

      final method = jsonRequest['method'];
      if (method is String && _userMutationMethods.contains(method)) {
        final permit = WalletOperationGate.instance.capture();
        return await RpcDispatchGuard.run(
          permit.ensureCurrent,
          () => _kdfSdk.client.executeRpc(jsonRequest),
          methods: {method},
        );
      }
      return await _kdfSdk.client.executeRpc(jsonRequest);
    } catch (e) {
      log('RPC call error: $e', path: 'mm2 => call', isError: true).ignore();
      rethrow;
    }
  }

  // These calls initiate user work. Status polling and work already accepted
  // inside KDF deliberately stay outside the application lock authority.
  static const _userMutationMethods = {
    'withdraw',
    'task::withdraw::init',
    'withdraw_nft',
    'send_raw_transaction',
    'sell',
    'buy',
    'setprice',
    'cancel_order',
    'cancel_all_orders',
    'recover_funds_of_swap',
    'start_simple_market_maker_bot',
    'stop_simple_market_maker_bot',
    'task::routed_swap::init',
    'task::routed_swap::cancel',
  };

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
