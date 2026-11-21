import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:web_dex/services/wallet_access/wallet_access_service.dart';

/// Discoverable even after the last wallet was removed from the engine catalog.
class WalletCredentialCleanupNotice extends StatefulWidget {
  const WalletCredentialCleanupNotice({super.key});
  @override
  State<WalletCredentialCleanupNotice> createState() =>
      _WalletCredentialCleanupNoticeState();
}

class _WalletCredentialCleanupNoticeState
    extends State<WalletCredentialCleanupNotice> {
  WalletAccessService? _access;
  StreamSubscription<void>? _changes;
  Future<bool>? _pending;
  bool _busy = false;
  String? _error;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final access = context.read<WalletAccessService?>();
    if (identical(_access, access)) return;
    _access = access;
    _changes?.cancel();
    _pending = access?.hasPendingCredentialCleanup;
    _changes = access?.changes.listen((_) {
      if (mounted) {
        setState(() => _pending = access.hasPendingCredentialCleanup);
      }
    });
  }

  @override
  void dispose() {
    _changes?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<bool>(
    future: _pending,
    builder: (context, snapshot) {
      if (snapshot.data != true) return const SizedBox.shrink();
      return Card(
        key: const Key('wallet-credential-cleanup-notice'),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('authCredentialCleanupPending'.tr()),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Semantics(liveRegion: true, child: Text(_error!)),
              ],
              TextButton(
                onPressed: _busy ? null : _retry,
                child: Text('authRetryCredentialCleanup'.tr()),
              ),
              if (_busy) const LinearProgressIndicator(),
            ],
          ),
        ),
      );
    },
  );
  Future<void> _retry() async {
    if (_busy || _access == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _access!.retryCredentialCleanup();
    } catch (error) {
      if (mounted) {
        _error =
            error is WalletAccessException &&
                error.failure == WalletAccessFailure.canceled
            ? 'authUnlockCanceled'.tr()
            : 'authCredentialCleanupPending'.tr();
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _pending = _access!.hasPendingCredentialCleanup;
        });
      }
    }
  }
}
