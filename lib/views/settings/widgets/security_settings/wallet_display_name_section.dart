import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/bloc/auth_bloc/auth_bloc.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/model/wallet.dart';
import 'package:web_dex/services/wallet_access/wallet_access_service.dart';
import 'package:web_dex/views/common/wallet_password_dialog/wallet_password_dialog.dart';

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
  final _form = GlobalKey<FormState>();
  WalletId? _walletId;
  String _currentName = '';
  String _sourceName = '';
  bool _editing = false;
  bool _busy = false;
  String? _message;
  bool _failed = false;

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
      return Card(
        elevation: 0,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(
                header: true,
                child: Text(
                  'authWalletName'.tr(),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              const SizedBox(height: 8),
              if (!_editing) ...[
                Text(
                  _currentName,
                  key: const Key('settings-wallet-display-name'),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    style: TextButton.styleFrom(
                      foregroundColor: Theme.of(context).colorScheme.onSurface,
                    ),
                    key: const Key('rename-wallet'),
                    icon: const Icon(Icons.edit_outlined),
                    label: Text('authRenameWallet'.tr()),
                    onPressed: () => setState(() {
                      _editing = true;
                      _message = null;
                    }),
                  ),
                ),
              ] else
                Form(
                  key: _form,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text('authRenameWalletDescription'.tr()),
                      const SizedBox(height: 12),
                      TextFormField(
                        key: const Key('wallet-display-name-input'),
                        controller: _name,
                        autofocus: true,
                        enabled: !_busy,
                        maxLength: 64,
                        textInputAction: TextInputAction.done,
                        decoration: InputDecoration(
                          labelText: 'authWalletName'.tr(),
                        ),
                        validator: (value) {
                          final name = value?.trim() ?? '';
                          if (name.isEmpty) {
                            return 'authRenameWalletNameRequired'.tr();
                          }
                          if (name.runes.length > 64 ||
                              RegExp(
                                r'[\u0000-\u001f\u007f-\u009f\u2028\u2029]',
                              ).hasMatch(name)) {
                            return 'authRenameWalletNameInvalid'.tr();
                          }
                          return null;
                        },
                        onFieldSubmitted: (_) => _save(access),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 12,
                        runSpacing: 8,
                        children: [
                          FilledButton(
                            key: const Key('save-wallet-display-name'),
                            onPressed: _busy ? null : () => _save(access),
                            child: Text(
                              _busy
                                  ? LocaleKeys.pleaseWait.tr()
                                  : 'authSaveWalletName'.tr(),
                            ),
                          ),
                          TextButton(
                            style: TextButton.styleFrom(
                              foregroundColor: Theme.of(
                                context,
                              ).colorScheme.onSurface,
                            ),
                            onPressed: _busy
                                ? null
                                : () => setState(() {
                                    _name.text = _currentName;
                                    _editing = false;
                                    _message = null;
                                  }),
                            child: Text(LocaleKeys.cancel.tr()),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              if (_message != null) ...[
                const SizedBox(height: 8),
                Semantics(
                  liveRegion: true,
                  child: Text(
                    _message!,
                    style: _failed
                        ? TextStyle(color: Theme.of(context).colorScheme.error)
                        : null,
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    },
  );

  Future<void> _save(WalletAccessService access) async {
    if (_busy || !(_form.currentState?.validate() ?? false)) return;
    final id = _walletId;
    if (id == null) return;
    final name = _name.text.trim();
    if (name == _currentName) {
      setState(() => _editing = false);
      return;
    }
    setState(() {
      _busy = true;
      _message = null;
      _failed = false;
    });
    try {
      final status = await access.status(walletId: id);
      if (!mounted || _walletId != id) return;
      final password = status.hasManagedCredential
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
      });
    } catch (error) {
      if (!mounted || _walletId != id) return;
      setState(() {
        _failed = true;
        _message = switch (error) {
          WalletAccessException(failure: WalletAccessFailure.canceled) =>
            'authUnlockCanceled'.tr(),
          WalletAccessException(failure: WalletAccessFailure.invalidName) =>
            'authRenameWalletNameInvalid'.tr(),
          WalletAccessException(failure: WalletAccessFailure.nameAlreadyUsed) =>
            'authRenameWalletNameUsed'.tr(),
          _ => 'authRenameWalletFailed'.tr(),
        };
      });
    } finally {
      if (mounted && _walletId == id) setState(() => _busy = false);
    }
  }
}
