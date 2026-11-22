import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:komodo_ui_kit/komodo_ui_kit.dart';
import 'package:web_dex/bloc/auth_bloc/auth_bloc.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/model/wallet.dart';
import 'package:web_dex/services/wallet_access/wallet_access_service.dart';
import 'package:web_dex/views/common/wallet_access/wallet_access_feedback.dart';
import 'package:web_dex/views/common/wallet_password_dialog/wallet_password_dialog.dart';
import 'package:web_dex/views/settings/widgets/security_settings/security_action_plate.dart';
import 'package:web_dex/views/settings/widgets/security_settings/security_section_card.dart';

/// Renames only the visible label. Engine identity and credential lookup remain
/// bound to the immutable WalletId passed to the access service.
class WalletDisplayNameSection extends StatefulWidget {
  const WalletDisplayNameSection({super.key});
  @override
  State<WalletDisplayNameSection> createState() =>
      _WalletDisplayNameSectionState();
}

class _WalletDisplayNameSectionState extends State<WalletDisplayNameSection> {
  final _name = TextEditingController();
  WalletId? _walletId;
  String _currentName = '';
  String _sourceName = '';
  bool _editing = false;
  bool _busy = false;
  String? _message;
  WalletAccessTone _tone = WalletAccessTone.info;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => BlocBuilder<AuthBloc, AuthBlocState>(
    builder: (context, auth) {
      final user = auth.currentUser;
      final access = context.read<WalletAccessService?>();
      if (user == null || access == null || user.wallet.isHW) {
        return const SizedBox.shrink();
      }
      if (_walletId != user.walletId) {
        _walletId = user.walletId;
        _currentName = user.wallet.displayName;
        _sourceName = user.wallet.displayName;
        _name.text = _currentName;
        _editing = false;
        _busy = false;
        _message = null;
      } else if (!_editing && _sourceName != user.wallet.displayName) {
        _sourceName = user.wallet.displayName;
        _currentName = user.wallet.displayName;
        _name.text = _currentName;
      }
      final notice = _message == null
          ? null
          : WalletAccessNotice(text: _message!, tone: _tone);
      if (!_editing) {
        return LayoutBuilder(
          builder: (context, constraints) => SecurityActionPlate(
            icon: const Icon(Icons.badge_outlined),
            title: 'authWalletName'.tr(),
            description: _currentName,
            status: notice,
            trailingWidget: SecuritySecondaryButton(
              key: const Key('rename-wallet'),
              width: SecurityActionPlate.isWide(context, constraints)
                  ? SecurityActionPlate.actionWidth
                  : double.infinity,
              icon: const Icon(Icons.edit_outlined),
              text: 'authRenameWallet'.tr(),
              onPressed: () => setState(() {
                _editing = true;
                _message = null;
              }),
            ),
          ),
        );
      }
      return SecurityActionPlate(
        icon: const Icon(Icons.badge_outlined),
        title: 'authWalletName'.tr(),
        description: 'authRenameWalletDescription'.tr(),
        details: _NameForm(
          controller: _name,
          busy: _busy,
          failed: _message != null && _tone == WalletAccessTone.error,
          notice: notice,
          onChanged: () {
            if (_message != null) setState(() => _message = null);
          },
          onSave: () => _save(access),
          onCancel: () => setState(() {
            _name.text = _currentName;
            _editing = false;
            _message = null;
          }),
        ),
      );
    },
  );

  String? _validate(String name) {
    if (name.isEmpty) return 'authRenameWalletNameRequired'.tr();
    if (name.runes.length > 64 ||
        RegExp(r'[\u0000-\u001f\u007f-\u009f  ]').hasMatch(name)) {
      return 'authRenameWalletNameInvalid'.tr();
    }
    return null;
  }

  void _show(String message, WalletAccessTone tone) => setState(() {
    _message = message;
    _tone = tone;
  });

  Future<void> _save(WalletAccessService access) async {
    if (_busy) return;
    final id = _walletId;
    if (id == null) return;
    final name = _name.text.trim();
    if (_validate(name) case final problem?) {
      _show(problem, WalletAccessTone.error);
      return;
    }
    if (name == _currentName) {
      setState(() => _editing = false);
      return;
    }
    setState(() {
      _busy = true;
      _message = null;
    });
    String? password;
    try {
      final status = await access.status(walletId: id);
      if (!mounted || _walletId != id) return;
      password = status.hasManagedCredential
          ? null
          : await walletPasswordDialog(context);
      if (!mounted ||
          _walletId != id ||
          (!status.hasManagedCredential && password == null)) {
        return;
      }
      await access.renameDisplayName(
        walletId: id,
        name: name,
        password: password,
      );
      if (!mounted || _walletId != id) return;
      setState(() {
        _currentName = name;
        _name.text = name;
        _editing = false;
        _message = 'authRenameWalletSaved'.tr();
        _tone = WalletAccessTone.success;
      });
    } catch (error) {
      if (!mounted || _walletId != id) return;
      final failure = error is WalletAccessException ? error.failure : null;
      _show(
        switch (failure) {
          WalletAccessFailure.invalidName => 'authRenameWalletNameInvalid'.tr(),
          WalletAccessFailure.nameAlreadyUsed =>
            'authRenameWalletNameUsed'.tr(),
          WalletAccessFailure.canceled ||
          WalletAccessFailure.busy ||
          WalletAccessFailure.staleOperation => walletAccessFailureText(
            error,
            passwordEntered: password != null,
            unlocking: false,
          ),
          _ => 'authRenameWalletFailed'.tr(),
        },
        // Cancelling is the user's own choice, not a fault.
        failure == WalletAccessFailure.canceled
            ? WalletAccessTone.info
            : WalletAccessTone.error,
      );
    } finally {
      if (mounted && _walletId == id) setState(() => _busy = false);
    }
  }
}

class _NameForm extends StatelessWidget {
  const _NameForm({
    required this.controller,
    required this.busy,
    required this.failed,
    required this.notice,
    required this.onChanged,
    required this.onSave,
    required this.onCancel,
  });

  final TextEditingController controller;
  final bool busy;
  final bool failed;
  final Widget? notice;
  final VoidCallback onChanged;
  final VoidCallback onSave;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final problemBorder = failed
        ? OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Theme.of(context).colorScheme.error),
          )
        : null;
    // Kept enabled while saving: both would drop keyboard focus if disabled,
    // and a save that fails should leave the user where they were.
    final save = UiPrimaryButton(
      key: const Key('save-wallet-display-name'),
      expandForText: true,
      onPressed: onSave,
      text: busy ? LocaleKeys.pleaseWait.tr() : 'authSaveWalletName'.tr(),
    );
    final cancel = UiUnderlineTextButton(
      expandForText: true,
      onPressed: busy ? null : onCancel,
      text: LocaleKeys.cancel.tr(),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final beside =
            constraints.maxWidth >= 420 &&
            MediaQuery.textScalerOf(context).scale(1) <= 1.5;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            UiTextFormField(
              key: const Key('wallet-display-name-input'),
              controller: controller,
              autofocus: true,
              readOnly: busy,
              maxLength: 64,
              textInputAction: TextInputAction.done,
              labelText: 'authWalletName'.tr(),
              enabledBorder: problemBorder,
              focusedBorder: problemBorder,
              onChanged: (_) => onChanged(),
              onFieldSubmitted: (_) => onSave(),
            ),
            if (notice != null) ...[const SizedBox(height: 4), notice!],
            const SizedBox(height: 12),
            if (beside)
              Row(
                children: [
                  SizedBox(width: SecurityActionPlate.actionWidth, child: save),
                  const SizedBox(width: 12),
                  SizedBox(width: 140, child: cancel),
                ],
              )
            else ...[
              save,
              const SizedBox(height: 4),
              cancel,
            ],
          ],
        );
      },
    );
  }
}
