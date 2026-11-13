import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:web_dex/bloc/auth_bloc/auth_bloc.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_bloc.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_state.dart';
import 'package:web_dex/model/authorize_mode.dart';
import 'package:web_dex/shared/swap/swap_services.dart';
import 'package:web_dex/shared/widgets/connect_wallet/connect_wallet_button.dart';
import 'package:web_dex/views/wallets_manager/wallets_manager_events_factory.dart';

/// Signs in from the swap form, which then reopens on the same pair and
/// amount instead of the app moving on to Wallet.
///
/// [openManager] stands in for the app's wallet manager in tests.
Future<void> connectWalletFromSwap(
  BuildContext context, {
  Future<void> Function(BuildContext context)? openManager,
}) async {
  // Read now: signing in rebuilds the form and unmounts [context].
  final services = context.read<SwapServices>();
  final auth = context.read<AuthBloc?>();
  final form = context.read<UnifiedSwapBloc>().state;
  final amount = form.inputText.trim();
  services.beginSignIn((
    pay: form.pay?.id,
    receive: form.receive?.id,
    amount: amount.isEmpty ? null : amount,
    fiat: form.amountMode == SwapAmountMode.fiat,
  ));
  try {
    await (openManager ?? _openWalletManager)(context);
  } finally {
    services.endSignIn(signedIn: auth?.state.mode == AuthorizeMode.logIn);
  }
}

Future<void> _openWalletManager(BuildContext context) =>
    showConnectWalletDialog(context, eventType: WalletsManagerEventType.dex);
