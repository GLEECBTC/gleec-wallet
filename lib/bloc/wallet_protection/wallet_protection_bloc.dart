import 'dart:async';

import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/services/wallet_access/unlock_coordinator.dart';
import 'package:web_dex/services/wallet_access/wallet_access_service.dart';

part 'wallet_protection_event.dart';
part 'wallet_protection_state.dart';

/// Non-secret presentation state for one immutable wallet. The vault remains
/// the authority for fresh authorization, session binding and persistence.
class WalletProtectionBloc
    extends Bloc<WalletProtectionEvent, WalletProtectionState> {
  WalletProtectionBloc({required this.access, required this.walletId})
    : super(const WalletProtectionState()) {
    on<WalletProtectionRefreshed>(_refresh, transformer: restartable());
    on<WalletProtectionRequested>(_request, transformer: droppable());
    _subscription = access.changes.listen((_) {
      if (!isClosed) add(const WalletProtectionRefreshed());
    });
    _wasInteractive =
        access.unlockCoordinator.state.isForeground &&
        !access.unlockCoordinator.state.isLocked &&
        !access.unlockCoordinator.hasSystemPrompt;
    _unlockSubscription = access.unlockCoordinator.changes.listen((state) {
      final interactive =
          state.isForeground &&
          !state.isLocked &&
          !access.unlockCoordinator.hasSystemPrompt;
      if (!isClosed && interactive && !_wasInteractive) {
        // System save dialogs can finish before Flutter regains focus. Recheck
        // the offer on return without launching another authentication prompt.
        add(const WalletProtectionRefreshed());
      }
      _wasInteractive = interactive;
    });
    add(const WalletProtectionRefreshed());
  }

  final WalletAccessService access;
  final WalletId walletId;
  late final StreamSubscription<void> _subscription;
  late final StreamSubscription<WalletUnlockState> _unlockSubscription;
  late bool _wasInteractive;
  String? _entryId;

  void _checkEntry(WalletAccessStatus status) {
    _entryId ??= status.entryId;
    if (status.entryId != _entryId) {
      throw const WalletAccessException(WalletAccessFailure.staleOperation);
    }
  }

  Future<void> _refresh(
    WalletProtectionRefreshed event,
    Emitter<WalletProtectionState> emit,
  ) async {
    try {
      final status = await access.status(walletId: walletId);
      final capabilities = await access.capabilities();
      if (emit.isDone) return;
      _checkEntry(status);
      emit(
        state.copyWith(
          status: status,
          capabilities: capabilities,
          loading: false,
          graceSeconds: access.unlockCoordinator.backgroundGrace.inSeconds,
        ),
      );
    } on WalletAccessException catch (error) {
      if (!emit.isDone) {
        emit(state.copyWith(loading: false, failure: error.failure));
      }
    } catch (_) {
      if (!emit.isDone) {
        emit(
          state.copyWith(
            loading: false,
            failure: WalletAccessFailure.unavailable,
          ),
        );
      }
    }
  }

  Future<void> _request(
    WalletProtectionRequested event,
    Emitter<WalletProtectionState> emit,
  ) async {
    if (state.loading || state.busy || state.status == null) return;
    final allowed = switch (event.action) {
      WalletProtectionAction.passkey => state.canCreatePasskey,
      WalletProtectionAction.device => state.canEnableDevice,
      WalletProtectionAction.replacePasskey =>
        state.status?.protection == CredentialProtection.passkey &&
            state.capabilities?.passkeyCandidate == true,
      WalletProtectionAction.grace =>
        state.status?.requiresAuthentication == true &&
            const [0, 30].contains(event.graceSeconds),
    };
    if (!allowed) {
      emit(state.copyWith(failure: WalletAccessFailure.unavailable));
      return;
    }
    emit(state.copyWith(busy: true, clearNotice: true));
    try {
      final ensureCurrent = access.captureSensitiveOperation(walletId);
      final current = await access.status(walletId: walletId);
      ensureCurrent();
      _checkEntry(current);
      switch (event.action) {
        case WalletProtectionAction.passkey:
          await access.enrollPasskey(
            walletId: walletId,
            password: event.password,
          );
        case WalletProtectionAction.device:
          await access.enrollDevice(
            walletId: walletId,
            password: event.password,
          );
        case WalletProtectionAction.replacePasskey:
          final password = event.password;
          if (password == null) {
            throw const WalletAccessException(
              WalletAccessFailure.incorrectPassword,
            );
          }
          await access.replacePasskeyUsingPassword(
            walletId: walletId,
            password: password,
          );
        case WalletProtectionAction.grace:
          await access.authorize(
            walletId: walletId,
            password: event.password,
            reason: 'Change automatic wallet locking',
          );
          final ensureCurrent = access.captureSensitiveOperation(walletId);
          ensureCurrent();
          await access.setBackgroundGrace(
            Duration(seconds: event.graceSeconds!),
          );
          ensureCurrent();
      }
      if (emit.isDone) return;
      final status = await access.status(walletId: walletId);
      if (emit.isDone) return;
      _checkEntry(status);
      emit(
        state.copyWith(
          status: status,
          busy: false,
          completed: event.action,
          graceSeconds: access.unlockCoordinator.backgroundGrace.inSeconds,
          clearFailure: true,
        ),
      );
    } on WalletAccessException catch (error) {
      if (!emit.isDone) {
        emit(state.copyWith(busy: false, failure: error.failure));
      }
    } catch (_) {
      if (!emit.isDone) {
        emit(
          state.copyWith(busy: false, failure: WalletAccessFailure.unavailable),
        );
      }
    }
  }

  @override
  Future<void> close() async {
    await _subscription.cancel();
    await _unlockSubscription.cancel();
    return super.close();
  }
}
