import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:web_dex/bloc/trading_status/trading_status_bloc.dart';
import 'package:komodo_ui_kit/komodo_ui_kit.dart';
import 'package:web_dex/bloc/auth_bloc/auth_bloc.dart';
import 'package:web_dex/bloc/coins_bloc/coins_bloc.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/model/wallet.dart';

class LogOutPopup extends StatelessWidget {
  const LogOutPopup({
    super.key,
    required this.onConfirm,
    required this.onCancel,
    this.title,
    this.description,
    this.confirmLabel,
  });
  final VoidCallback onCancel;
  final VoidCallback onConfirm;

  /// Names what signing out is for, when it is a step towards something else
  /// (switching or recovering a wallet). Defaults to the plain sign-out copy.
  final String? title;

  /// Replaces the default question. What signing out interrupts is still
  /// added below it for a wallet that can trade.
  final String? description;
  final String? confirmLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final body = theme.textTheme.bodyMedium?.copyWith(
      fontSize: 14,
      fontWeight: FontWeight.w500,
      color: theme.colorScheme.onSurface,
    );
    return BlocBuilder<AuthBloc, AuthBlocState>(
      builder: (context, state) {
        final walletType = state.currentUser?.wallet.config.type;
        final softwareWallet =
            walletType == WalletType.iguana ||
            walletType == WalletType.hdwallet;
        final interruptsTrading =
            softwareWallet &&
            context.watch<TradingStatusBloc>().state.isEnabled;
        final description = this.description;
        return ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Semantics(
                header: true,
                child: Text(
                  title ?? LocaleKeys.logoutPopupTitle.tr(),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleLarge,
                ),
              ),
              if (description != null) ...[
                const SizedBox(height: 12),
                Text(description, textAlign: TextAlign.center, style: body),
                if (interruptsTrading) ...[
                  const SizedBox(height: 8),
                  Text(
                    'authSignOutActivityWarning'.tr(),
                    textAlign: TextAlign.center,
                    style: body,
                  ),
                ],
              ] else if (softwareWallet) ...[
                const SizedBox(height: 12),
                Text(
                  interruptsTrading
                      ? LocaleKeys.logoutPopupDescription.tr()
                      : LocaleKeys.logoutPopupDescriptionWalletOnly.tr(),
                  textAlign: TextAlign.center,
                  style: body,
                ),
              ],
              const SizedBox(height: 24),
              UiPrimaryButton(
                key: const Key('popup-confirm-logout-button'),
                expandForText: true,
                text: confirmLabel ?? LocaleKeys.logOut.tr(),
                onPressed: () => _onConfirmLogout(context),
              ),
              const SizedBox(height: 8),
              UiUnderlineTextButton(
                key: const Key('popup-cancel-logout-button'),
                expandForText: true,
                text: LocaleKeys.cancel.tr(),
                onPressed: onCancel,
              ),
            ],
          ),
        );
      },
    );
  }

  void _onConfirmLogout(BuildContext context) {
    final auth = context.read<AuthBloc>();
    final coins = context.read<CoinsBloc>();
    // A failed durable sign-out leaves the existing session locked and usable.
    // Only tear down its coin projection after auth confirms removal. The auth
    // coordinator disconnects engine streams before shutting down KDF.
    unawaited(
      auth.stream
          .firstWhere(
            (state) =>
                !state.isLoading &&
                (state.currentUser == null || state.authError != null),
          )
          .then((state) {
            if (state.currentUser == null &&
                auth.state.currentUser == null &&
                !coins.isClosed) {
              coins.add(CoinsSessionEnded());
            }
          })
          .catchError((Object _) {}),
    );
    auth.add(const AuthSignOutRequested());
    onConfirm();
  }
}
