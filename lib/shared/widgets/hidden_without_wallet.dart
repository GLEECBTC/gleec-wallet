import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:web_dex/bloc/auth_bloc/auth_bloc.dart';
import 'package:web_dex/model/wallet.dart';

class HiddenWithoutWallet extends StatelessWidget {
  const HiddenWithoutWallet({
    super.key,
    required this.child,
    this.isHiddenForHw = false,
    this.isHiddenElse = true,
    this.showWhenNoWalletInDebugMode = false,
  });
  final Widget child;
  final bool isHiddenForHw;
  final bool isHiddenElse;

  /// When true, [child] is still shown with no active wallet if [kDebugMode]
  /// is on (e.g. export logs from settings while logged out in dev builds).
  final bool showWhenNoWalletInDebugMode;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AuthBloc, AuthBlocState>(
      builder: (context, state) {
        final Wallet? currentWallet = state.currentUser?.wallet;
        if (currentWallet == null) {
          final allowWithoutWallet = showWhenNoWalletInDebugMode && kDebugMode;
          if (!allowWithoutWallet && isHiddenElse) {
            return const SizedBox.shrink();
          }
        }

        if (isHiddenForHw && currentWallet?.isHW == true) {
          return const SizedBox.shrink();
        }

        return child;
      },
    );
  }
}
