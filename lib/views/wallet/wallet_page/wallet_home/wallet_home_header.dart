import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:web_dex/bloc/auth_bloc/auth_bloc.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/model/wallet.dart';
import 'package:web_dex/services/feedback/feedback_ui_extension.dart';
import 'package:web_dex/shared/widgets/app_dialog.dart';
import 'package:web_dex/shared/widgets/logout_popup.dart';
import 'package:web_dex/views/settings/widgets/security_settings/security_settings_entry.dart';
import 'package:web_dex/views/swap/common/swap_palette.dart';
import 'package:web_dex/views/wallet/wallet_page/wallet_home/wallet_home_style.dart';

enum _WalletMenuItem { security, signOut }

/// The top of the wallet home: which wallet this is, with its menu, and the
/// feedback button where feedback is offered.
class WalletHomeHeader extends StatelessWidget {
  const WalletHomeHeader({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = SwapPalette.of(context);
    final name = context.select<AuthBloc, String>(
      (bloc) => bloc.state.currentUser?.wallet.displayName ?? '',
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
      child: Row(
        children: [
          Expanded(
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: _WalletMenu(name: name),
            ),
          ),
          if (context.isFeedbackAvailable)
            IconButton(
              key: const Key('wallet-home-feedback'),
              tooltip: LocaleKeys.feedback.tr(),
              color: palette.textSecondary,
              onPressed: context.showFeedback,
              icon: const Icon(Icons.bug_report_outlined),
            ),
        ],
      ),
    );
  }
}

class _WalletMenu extends StatelessWidget {
  const _WalletMenu({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    final palette = SwapPalette.of(context);
    return PopupMenuButton<_WalletMenuItem>(
      key: const Key('wallet-home-wallet-menu'),
      tooltip: name,
      color: palette.surfaceRaised,
      position: PopupMenuPosition.under,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: palette.border),
      ),
      onSelected: (item) => switch (item) {
        _WalletMenuItem.security => openSecuritySettings(),
        _WalletMenuItem.signOut => _signOut(context),
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          value: _WalletMenuItem.security,
          child: _MenuLabel(
            icon: Icons.shield_outlined,
            text: LocaleKeys.securitySettings.tr(),
          ),
        ),
        PopupMenuItem(
          value: _WalletMenuItem.signOut,
          child: _MenuLabel(
            icon: Icons.logout_rounded,
            text: LocaleKeys.logOut.tr(),
          ),
        ),
      ],
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _Avatar(name: name),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  name,
                  style: WalletHomeText.title(context),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 2),
              Icon(
                Icons.expand_more_rounded,
                size: 20,
                color: palette.textTertiary,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _signOut(BuildContext context) =>
      AppDialog.showWithCallback<void>(
        context: context,
        width: 320,
        barrierDismissible: true,
        childBuilder: (close) => LogOutPopup(onConfirm: close, onCancel: close),
      );
}

class _MenuLabel extends StatelessWidget {
  const _MenuLabel({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final palette = SwapPalette.of(context);
    return Row(
      children: [
        Icon(icon, size: 20, color: palette.textSecondary),
        const SizedBox(width: 12),
        Text(
          text,
          style: WalletHomeText.title(context)
              .copyWith(fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}

/// The wallet's initial on a brand gradient.
class _Avatar extends StatelessWidget {
  const _Avatar({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    final palette = SwapPalette.of(context);
    final initial = name.trim().isEmpty
        ? '?'
        : name.trim().characters.first.toUpperCase();
    return ExcludeSemantics(
      child: Container(
        width: 32,
        height: 32,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [palette.brandHover, palette.brandPressed],
          ),
        ),
        child: Text(
          initial,
          style: WalletHomeText.title(context).copyWith(
            fontSize: 14,
            fontWeight: FontWeight.w800,
            color: palette.onBrand,
          ),
        ),
      ),
    );
  }
}
