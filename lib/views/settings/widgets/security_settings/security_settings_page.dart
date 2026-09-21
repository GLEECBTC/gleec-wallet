import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/app_config/app_config.dart' show excludedAssetList;
import 'package:web_dex/bloc/auth_bloc/auth_bloc.dart';
import 'package:web_dex/bloc/security_settings/private_key_export_bloc.dart';
import 'package:web_dex/bloc/security_settings/private_key_export_event.dart';
import 'package:web_dex/bloc/coins_bloc/coins_bloc.dart';
import 'package:web_dex/bloc/security_settings/security_settings_bloc.dart';
import 'package:web_dex/bloc/security_settings/security_settings_event.dart';
import 'package:web_dex/bloc/security_settings/security_settings_state.dart';
import 'package:web_dex/common/screen.dart';
import 'package:web_dex/mm2/mm2_api/mm2_api.dart';
import 'package:web_dex/mm2/mm2_api/rpc/show_priv_key/show_priv_key_request.dart';
import 'package:web_dex/model/coin.dart';
import 'package:web_dex/views/common/page_header/page_header.dart';
import 'package:web_dex/views/common/pages/page_layout.dart';
import 'package:web_dex/views/common/wallet_password_dialog/wallet_password_dialog.dart';
import 'package:web_dex/views/settings/widgets/common/settings_content_wrapper.dart';
import 'package:web_dex/views/settings/widgets/security_settings/password_update_page.dart';
import 'package:web_dex/views/settings/widgets/security_settings/security_settings_main_page.dart';
import 'package:web_dex/views/settings/widgets/security_settings/seed_settings/seed_confirm_success.dart';
import 'package:web_dex/views/settings/widgets/security_settings/seed_settings/seed_confirmation/seed_confirmation.dart';
import 'package:web_dex/views/settings/widgets/security_settings/seed_settings/seed_show.dart';
import 'package:web_dex/views/settings/widgets/security_settings/private_key_settings/private_key_show.dart';
import 'package:web_dex/views/settings/widgets/security_settings/private_key_settings/private_key_export_flow_listener.dart';
import 'package:web_dex/services/security/private_key_export_service.dart';
import 'package:web_dex/services/security/private_key_export_delivery.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:web_dex/bloc/trading_status/trading_status_bloc.dart';

/// Page navigation and the legacy seed flow. Private-key operations are owned
/// by a separate, screen-scoped [PrivateKeyExportBloc].
class SecuritySettingsPage extends StatefulWidget {
  const SecuritySettingsPage({required this.onBackPressed, super.key});

  final VoidCallback onBackPressed;

  @override
  State<SecuritySettingsPage> createState() => _SecuritySettingsPageState();
}

class _SecuritySettingsPageState extends State<SecuritySettingsPage> {
  String _seed = '';
  AuthSessionContext? _seedSession;
  StreamSubscription<AuthSessionContext?>? _seedSessionSubscription;
  SecuritySettingsBloc? _seedFlowBloc;
  final Map<Coin, String> _privKeys = {};

  @override
  void dispose() {
    // Ensure sensitive data is cleared when widget is disposed
    _clearAllSensitiveData();
    _seedSessionSubscription?.cancel();
    super.dispose();
  }

  /// Drops the legacy seed flow's references when its screen is left.
  void _clearAllSensitiveData() {
    _seed = '';
    _seedSession = null;
    _privKeys.clear();
  }

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider<SecuritySettingsBloc>(
          create: (context) => SecuritySettingsBloc(
            SecuritySettingsState.initialState(),
            kdfSdk: context.read<KomodoDefiSdk>(),
          ),
        ),
        BlocProvider<PrivateKeyExportBloc>(
          create: (context) => PrivateKeyExportBloc(
            service: SdkPrivateKeyExportService(context.read<KomodoDefiSdk>()),
            delivery: PlatformPrivateKeyExportDelivery(),
            permanentlyExcludedAssetIds: excludedAssetList,
          ),
        ),
      ],
      child: PrivateKeyExportFlowListener(
        child: MultiBlocListener(
          listeners: [
            BlocListener<AuthBloc, AuthBlocState>(
              listener: (context, state) {
                if (!state.isSignedIn) {
                  context.read<PrivateKeyExportBloc>().add(
                    const PrivateKeyExportAuthenticationLost(),
                  );
                }
              },
            ),
            BlocListener<SecuritySettingsBloc, SecuritySettingsState>(
              listenWhen: (previous, current) =>
                  previous.step == SecuritySettingsStep.privateKeyShow &&
                  current.step != SecuritySettingsStep.privateKeyShow,
              listener: (context, state) {
                context.read<PrivateKeyExportBloc>().add(
                  const PrivateKeyExportCancelled(),
                );
              },
            ),
          ],
          child: BlocBuilder<SecuritySettingsBloc, SecuritySettingsState>(
            builder: (BuildContext context, SecuritySettingsState state) {
              final Widget content = _buildContent(context, state.step);
              if (isMobile) {
                return _SecuritySettingsPageMobile(
                  content: content,
                  onBackButtonPressed: () =>
                      _handleBackButton(context, state.step),
                );
              }
              return content;
            },
          ),
        ),
      ),
    );
  }

  /// Handles back button navigation based on current step.
  void _handleBackButton(BuildContext context, SecuritySettingsStep step) {
    switch (step) {
      case SecuritySettingsStep.securityMain:
        widget.onBackPressed();
        break;
      case SecuritySettingsStep.seedConfirm:
        context.read<SecuritySettingsBloc>().add(const ShowSeedEvent());
        break;
      case SecuritySettingsStep.seedShow:
      case SecuritySettingsStep.seedSuccess:
      case SecuritySettingsStep.privateKeyShow:
      case SecuritySettingsStep.passwordUpdate:
        context.read<SecuritySettingsBloc>().add(const ResetEvent());
        break;
    }
  }

  /// Builds the appropriate content widget based on the current step.
  Widget _buildContent(BuildContext context, SecuritySettingsStep step) {
    switch (step) {
      case SecuritySettingsStep.securityMain:
        _clearAllSensitiveData(); // Clear data when returning to main
        return SecuritySettingsMainPage(
          onViewSeedPressed: onViewSeedPressed,
          onViewPrivateKeysPressed: onViewPrivateKeysPressed,
        );

      case SecuritySettingsStep.seedShow:
        return SeedShow(seedPhrase: _seed, privKeys: _privKeys);

      case SecuritySettingsStep.seedConfirm:
        final session = _seedSession;
        if (session == null) return const SizedBox.shrink();
        return SeedConfirmation(seedPhrase: _seed, session: session);

      case SecuritySettingsStep.seedSuccess:
        _clearAllSensitiveData(); // Clear data after successful seed backup
        return const SeedConfirmSuccess();

      case SecuritySettingsStep.privateKeyShow:
        return const PrivateKeyShow();

      case SecuritySettingsStep.passwordUpdate:
        _clearAllSensitiveData(); // Clear data when changing password
        return const PasswordUpdatePage();
    }
  }

  /// Handles seed phrase export - uses existing legacy approach.
  ///
  /// Private-key export has a separate, screen-scoped BLoC.
  Future<void> onViewSeedPressed(BuildContext context) async {
    final securitySettingsBloc = context.read<SecuritySettingsBloc>();
    final coinsBloc = context.read<CoinsBloc>();
    final mm2Api = RepositoryProvider.of<Mm2Api>(context);
    final kdfSdk = RepositoryProvider.of<KomodoDefiSdk>(context);
    final AuthSessionContext session;
    try {
      session = await kdfSdk.auth.captureSessionContext();
    } on AuthSessionChangedException {
      return;
    }
    if (!context.mounted) return;

    final String? pass = await walletPasswordDialog(context);
    if (pass == null || !mounted) return;
    if (!kdfSdk.auth.isSessionContextCurrent(session)) return;

    final mnemonic = await kdfSdk.auth.getMnemonicPlainText(pass);
    if (!mounted || !kdfSdk.auth.isSessionContextCurrent(session)) {
      return;
    }

    final privateKeys = <Coin, String>{};
    final parentCoins = coinsBloc.state.walletCoins.values.where(
      (coin) =>
          !coin.id.isChildAsset &&
          coin.id.subClass != CoinSubClass.sia &&
          // TRON keys must stay unavailable in this legacy seed backup path
          // until KDF supports exporting them correctly.
          coin.id.subClass != CoinSubClass.trx &&
          coin.id.subClass != CoinSubClass.trc20,
    );
    for (final coin in parentCoins) {
      final result = await mm2Api.showPrivKey(
        ShowPrivKeyRequest(coin: coin.abbr),
      );
      if (!mounted || !kdfSdk.auth.isSessionContextCurrent(session)) {
        return;
      }
      if (result != null) {
        privateKeys[coin] = result.privKey;
      }
    }

    await _seedSessionSubscription?.cancel();
    if (!mounted || !kdfSdk.auth.isSessionContextCurrent(session)) return;
    _seed = mnemonic.plaintextMnemonic ?? '';
    _seedSession = session;
    _seedFlowBloc = securitySettingsBloc;
    _seedSessionSubscription = kdfSdk.auth.watchSessionContext().listen((_) {
      final original = _seedSession;
      if (original != null && !kdfSdk.auth.isSessionContextCurrent(original)) {
        _clearAllSensitiveData();
        final bloc = _seedFlowBloc;
        if (bloc != null && !bloc.isClosed) bloc.add(const ResetEvent());
      }
    });
    _privKeys
      ..clear()
      ..addAll(privateKeys);
    securitySettingsBloc.add(const ShowSeedEvent());
  }

  void onViewPrivateKeysPressed(BuildContext context) {
    final tradingState = context.read<TradingStatusBloc>().state;
    final blockedAssets = switch (tradingState) {
      TradingStatusLoadSuccess s => Set<AssetId>.of(s.disallowedAssets),
      _ => const <AssetId>{},
    };
    context.read<PrivateKeyExportBloc>().add(
      PrivateKeyExportRequested(blockedAssets: blockedAssets),
    );
  }
}

/// Mobile wrapper for security settings page.
class _SecuritySettingsPageMobile extends StatelessWidget {
  const _SecuritySettingsPageMobile({
    required this.content,
    required this.onBackButtonPressed,
  });

  final Widget content;
  final VoidCallback onBackButtonPressed;

  @override
  Widget build(BuildContext context) {
    return PageLayout(
      header: PageHeader(
        title: LocaleKeys.securitySettings.tr(),
        onBackButtonPressed: onBackButtonPressed,
      ),
      content: Flexible(child: SettingsContentWrapper(child: content)),
    );
  }
}
