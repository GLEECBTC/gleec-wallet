import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/bloc/analytics/analytics_bloc.dart';
import 'package:web_dex/bloc/auth_bloc/auth_bloc.dart';
import 'package:web_dex/bloc/coins_bloc/coins_bloc.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/model/main_menu_value.dart';
import 'package:web_dex/model/wallet.dart';
import 'package:web_dex/router/state/routing_state.dart';
import 'package:web_dex/views/common/hw_wallet_dialog/hw_dialog_init.dart';
import 'package:web_dex/views/common/hw_wallet_dialog/trezor_steps/trezor_dialog_error.dart';
import 'package:web_dex/views/common/hw_wallet_dialog/trezor_steps/trezor_dialog_in_progress.dart';
import 'package:web_dex/views/common/hw_wallet_dialog/trezor_steps/trezor_dialog_message.dart';
import 'package:web_dex/views/common/hw_wallet_dialog/trezor_steps/trezor_dialog_pin_pad.dart';
import 'package:web_dex/views/common/hw_wallet_dialog/trezor_steps/trezor_dialog_select_wallet.dart';
import 'package:web_dex/views/common/hw_wallet_dialog/trezor_steps/trezor_dialog_success.dart';
import 'package:web_dex/views/wallets_manager/wallets_manager_events_factory.dart';

class HardwareWalletsManager extends StatelessWidget {
  const HardwareWalletsManager({
    super.key,
    required this.close,
    required this.onSuccess,
    required this.eventType,
  });

  final WalletsManagerEventType eventType;
  final VoidCallback close;
  final void Function(Wallet) onSuccess;

  @override
  Widget build(BuildContext context) {
    return HardwareWalletsManagerView(
      close: close,
      onSuccess: onSuccess,
      eventType: eventType,
    );
  }
}

class HardwareWalletsManagerView extends StatefulWidget {
  const HardwareWalletsManagerView({
    super.key,
    required this.eventType,
    required this.close,
    required this.onSuccess,
  });
  final WalletsManagerEventType eventType;
  final VoidCallback close;
  final void Function(Wallet) onSuccess;

  @override
  State<HardwareWalletsManagerView> createState() =>
      _HardwareWalletsManagerViewState();
}

class _HardwareWalletsManagerViewState
    extends State<HardwareWalletsManagerView> {
  bool _didHandleSuccessfulLogin = false;

  @override
  void initState() {
    context.read<AuthBloc>().add(AuthTrezorCancelled());
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<AuthBloc, AuthBlocState>(
      listener: (context, state) {
        final status = state.status;
        final user = state.currentUser;
        if (status == AuthenticationStatus.completed &&
            user != null &&
            !_didHandleSuccessfulLogin) {
          _didHandleSuccessfulLogin = true;
          _successfulTrezorLogin(context, user);
        }
      },
      child: BlocSelector<AuthBloc, AuthBlocState, AuthException?>(
        selector: (state) => state.authError,
        builder: (context, error) {
          if (error != null) {
            return TrezorDialogError(error.message);
          }

          return _HardwareWalletManagerPopupContent(widget: widget);
        },
      ),
    );
  }

  void _successfulTrezorLogin(BuildContext context, KdfUser kdfUser) {
    context.read<CoinsBloc>().add(CoinsSessionStarted(kdfUser));
    context.read<AnalyticsBloc>().logEvent(
      walletsManagerEventsFactory.createEvent(
        widget.eventType,
        WalletsManagerEventMethod.hardware,
      ),
    );

    routingState.selectedMenu = MainMenuValue.wallet;
    widget.onSuccess(kdfUser.wallet);
  }
}

class _HardwareWalletManagerPopupContent extends StatelessWidget {
  const _HardwareWalletManagerPopupContent({required this.widget});

  final HardwareWalletsManagerView widget;

  @override
  Widget build(BuildContext context) {
    return BlocSelector<AuthBloc, AuthBlocState, AuthenticationState?>(
      selector: (state) => state.authenticationState,
      builder: (context, state) {
        final initStatus = state?.status;
        switch (initStatus) {
          case null:
            return HwDialogInit(close: widget.close);

          case AuthenticationStatus.initializing:
          case AuthenticationStatus.authenticating:
            return TrezorDialogInProgress(initStatus, onClose: widget.close);

          case AuthenticationStatus.pinRequired:
            return TrezorDialogPinPad(
              onComplete: (String pin) {
                context.read<AuthBloc>().add(AuthTrezorPinProvided(pin));
              },
              onClose: () async {
                context.read<AuthBloc>().add(const AuthTrezorCancelled());
              },
            );
          case AuthenticationStatus.passphraseRequired:
            return TrezorDialogSelectWallet(
              onComplete: (String passphrase) {
                context.read<AuthBloc>().add(
                  AuthTrezorPassphraseProvided(passphrase),
                );
              },
            );

          case AuthenticationStatus.waitingForDevice:
          case AuthenticationStatus.waitingForDeviceConfirmation:
            return TrezorDialogMessage(
              '${LocaleKeys.userActionRequired.tr()}:'
              '${LocaleKeys.followTrezorInstructions.tr()}',
            );

          case AuthenticationStatus.error:
            return TrezorDialogError(state?.error ?? LocaleKeys.unknown.tr());

          case AuthenticationStatus.completed:
            return TrezorDialogSuccess(onClose: widget.close);

          default:
            return TrezorDialogMessage(initStatus.name);
        }
      },
    );
  }
}
