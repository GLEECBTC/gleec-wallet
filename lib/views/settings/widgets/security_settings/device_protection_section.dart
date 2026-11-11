import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/bloc/auth_bloc/auth_bloc.dart';
import 'package:web_dex/services/wallet_access/wallet_access_service.dart';
import 'package:web_dex/views/common/wallet_password_dialog/wallet_password_dialog.dart';
import 'package:web_dex/views/common/wallet_password_dialog/password_manager_save.dart';

/// Device access is shown separately from recovery and personal passwords.
class DeviceProtectionSection extends StatefulWidget {
  const DeviceProtectionSection({super.key});
  @override
  State<DeviceProtectionSection> createState() =>
      _DeviceProtectionSectionState();
}

class _DeviceProtectionSectionState extends State<DeviceProtectionSection> {
  WalletAccessService? _access;
  StreamSubscription<void>? _subscription;
  Future<(WalletAccessStatus, CredentialCapabilities)>? _details;
  WalletId? _walletId;
  bool _busy = false;
  String? _message;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final access = context.read<WalletAccessService?>();
    if (identical(access, _access)) return;
    _subscription?.cancel();
    _access = access;
    _subscription = access?.changes.listen((_) {
      if (mounted) setState(_refresh);
    });
  }

  void _refresh() {
    final access = _access;
    final id = _walletId;
    if (access == null || id == null) return;
    _details = (() async =>
        (await access.status(walletId: id), await access.capabilities()))();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => BlocBuilder<AuthBloc, AuthBlocState>(
    builder: (context, auth) {
      if (_access == null || auth.currentUser == null) {
        return const SizedBox.shrink();
      }
      if (_walletId != auth.currentUser!.walletId || _details == null) {
        _walletId = auth.currentUser!.walletId;
        _refresh();
      }
      return FutureBuilder<(WalletAccessStatus, CredentialCapabilities)>(
        future: _details,
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const SizedBox.shrink();
          final (status, capabilities) = snapshot.data!;
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
                      'authDeviceProtectionTitle'.tr(),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(_protectionDescription(status)),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    children: [
                      if (capabilities.deviceAuthentication &&
                          (!status.requiresAuthentication ||
                              status.protection ==
                                  CredentialProtection.password))
                        OutlinedButton.icon(
                          style: TextButton.styleFrom(
                            foregroundColor: Theme.of(
                              context,
                            ).colorScheme.onSurface,
                          ),
                          key: const Key('enable-device-unlock'),
                          onPressed: _busy
                              ? null
                              : () => _enroll(status, passkey: false),
                          icon: const Icon(Icons.fingerprint),
                          label: Text('authEnableDeviceUnlock'.tr()),
                        ),
                      if (capabilities.passkeyCandidate &&
                          status.protection != CredentialProtection.passkey)
                        OutlinedButton.icon(
                          style: TextButton.styleFrom(
                            foregroundColor: Theme.of(
                              context,
                            ).colorScheme.onSurface,
                          ),
                          key: const Key('enable-passkey-unlock'),
                          onPressed: _busy
                              ? null
                              : () => _enroll(status, passkey: true),
                          icon: const Icon(Icons.key_outlined),
                          label: Text('authEnablePasskeyUnlock'.tr()),
                        ),
                      TextButton.icon(
                        style: TextButton.styleFrom(
                          foregroundColor: Theme.of(
                            context,
                          ).colorScheme.onSurface,
                        ),
                        key: const Key('save-wallet-password'),
                        onPressed: _busy ? null : () => _savePassword(status),
                        icon: const Icon(Icons.password),
                        label: Text('authSavePassword'.tr()),
                      ),
                    ],
                  ),
                  if (capabilities.passkeyCandidate &&
                      status.protection == CredentialProtection.passkey) ...[
                    const SizedBox(height: 12),
                    Text('authReplacePasskeyDescription'.tr()),
                    const SizedBox(height: 4),
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: OutlinedButton.icon(
                        key: const Key('replace-passkey-using-password'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Theme.of(
                            context,
                          ).colorScheme.onSurface,
                        ),
                        onPressed: _busy ? null : _replacePasskey,
                        icon: const Icon(Icons.key_outlined),
                        label: Text('authReplacePasskeyUsingPassword'.tr()),
                      ),
                    ),
                  ],
                  if (status.requiresAuthentication) ...[
                    const SizedBox(height: 12),
                    Text(
                      'authLockAfterTitle'.tr(),
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 8,
                      children: [
                        for (final seconds in [0, 30])
                          ChoiceChip(
                            label: Text(
                              seconds == 0
                                  ? 'authLockImmediately'.tr()
                                  : 'authLockThirtySeconds'.tr(),
                            ),
                            selected:
                                _access!
                                    .unlockCoordinator
                                    .backgroundGrace
                                    .inSeconds ==
                                seconds,
                            onSelected: _busy
                                ? null
                                : (_) => _setGrace(seconds),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'authLockGraceDescription'.tr(),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                  if (_busy) ...[
                    const SizedBox(height: 12),
                    Semantics(
                      liveRegion: true,
                      label: 'pleaseWait'.tr(),
                      child: TickerMode(
                        enabled: !MediaQuery.disableAnimationsOf(context),
                        child: const LinearProgressIndicator(),
                      ),
                    ),
                  ],
                  if (_message != null) ...[
                    const SizedBox(height: 12),
                    Semantics(liveRegion: true, child: Text(_message!)),
                  ],
                  const SizedBox(height: 8),
                  Text(
                    'authPasswordManagerNotBackup'.tr(),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          );
        },
      );
    },
  );

  String _protectionDescription(WalletAccessStatus status) {
    if (!status.requiresAuthentication) {
      return status.protection == CredentialProtection.browserLocal
          ? 'authBrowserUnprotected'.tr()
          : 'authDeviceUnprotected'.tr();
    }
    return switch (status.protection) {
      CredentialProtection.passkey => 'authPasskeyProtected'.tr(),
      CredentialProtection.password => 'authPasswordProtected'.tr(),
      CredentialProtection.osAccountProtected => 'authOsAccountProtected'.tr(),
      _ => 'authDeviceProtected'.tr(),
    };
  }

  Future<void> _enroll(WalletAccessStatus status, {required bool passkey}) =>
      _run(() async {
        final id = _walletId!;
        final password = status.hasManagedCredential
            ? null
            : await walletPasswordDialog(context);
        if (!mounted ||
            _walletId != id ||
            (!status.hasManagedCredential && password == null)) {
          return;
        }
        if (passkey) {
          await _access!.enrollPasskey(walletId: id, password: password);
        } else {
          await _access!.enrollDevice(walletId: id, password: password);
        }
        if (mounted && _walletId == id) _message = 'authProtectionEnabled'.tr();
      });

  Future<void> _savePassword(WalletAccessStatus status) => _run(() async {
    final id = _walletId!;
    final password = status.hasManagedCredential
        ? null
        : await walletPasswordDialog(context);
    if (!mounted ||
        _walletId != id ||
        (!status.hasManagedCredential && password == null)) {
      return;
    }
    final result = await saveWalletPassword(
      context,
      access: _access!,
      walletId: id,
      password: password,
    );
    if (!mounted || _walletId != id) return;
    _message = passwordManagerOutcomeMessage(result);
  });

  Future<void> _setGrace(int seconds) => _run(() async {
    final id = _walletId;
    final authorized = await walletPasswordDialog(context);
    if (!mounted || id != _walletId || authorized == null) return;
    await _access!.setBackgroundGrace(Duration(seconds: seconds));
  });

  Future<void> _replacePasskey() => _run(() async {
    final id = _walletId!;
    final password = await walletPasswordDialog(context, passwordOnly: true);
    if (!mounted || _walletId != id || password == null) return;
    await _access!.replacePasskeyUsingPassword(
      walletId: id,
      password: password,
    );
    if (mounted && _walletId == id) _message = 'authPasskeyReplaced'.tr();
  });

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await action();
    } catch (error) {
      if (mounted) {
        _message =
            error is WalletAccessException &&
                error.failure == WalletAccessFailure.canceled
            ? 'authUnlockCanceled'.tr()
            : 'authProtectionFailed'.tr();
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _refresh();
        });
      }
    }
  }
}
