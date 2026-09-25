import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';
import 'package:web_dex/bloc/security_settings/private_key_export_event.dart';
import 'package:web_dex/bloc/security_settings/private_key_export_state.dart';
import 'package:web_dex/services/security/private_key_export_delivery.dart';
import 'package:web_dex/services/security/private_key_export_document.dart';
import 'package:web_dex/services/security/private_key_export_service.dart';

/// Owns one settings screen's export. No password is retained in state.
class PrivateKeyExportBloc
    extends Bloc<PrivateKeyExportEvent, PrivateKeyExportState> {
  PrivateKeyExportBloc({
    required PrivateKeyExportService service,
    required PrivateKeyExportDelivery delivery,
    Set<String> permanentlyExcludedAssetIds = const {},
  }) : _service = service,
       _delivery = delivery,
       _permanentlyExcludedAssetIds = Set.unmodifiable(
         permanentlyExcludedAssetIds,
       ),
       super(const PrivateKeyExportState()) {
    on<PrivateKeyExportRequested>(_request);
    on<PrivateKeyExportPasswordSubmitted>(_submitPassword);
    on<PrivateKeyExportCancelled>((_, emit) => _clear(emit));
    on<PrivateKeyExportAuthenticationLost>((_, emit) => _clear(emit));
    on<PrivateKeyExportSessionCheckRequested>(_checkSession);
    on<PrivateKeyExportVisibilityChanged>(_changeVisibility);
    on<PrivateKeyExportKeyVisibilityToggled>(_toggleKeyVisibility);
    on<PrivateKeyExportBlockedAssetsChanged>((event, emit) {
      if (state.phase != PrivateKeyExportPhase.ready || state.isDelivering) {
        return;
      }
      _qrRevision++;
      emit(
        state.copyWith(
          includeBlockedAssets: event.include,
          clearQr: true,
          revealedKeys: const {},
        ),
      );
    });
    on<PrivateKeyExportDeliveryRequested>(_deliver);
    on<PrivateKeyExportQrRequested>(_showQr);
    on<PrivateKeyExportQrClosed>((_, emit) {
      _qrRevision++;
      emit(state.copyWith(clearQr: true));
    });
    _subscription = _service.sessionChanges.listen(
      (_) => _onSessionInvalidated(),
      onError: (Object _, StackTrace __) => _onSessionInvalidated(),
    );
  }

  final PrivateKeyExportService _service;
  final PrivateKeyExportDelivery _delivery;
  final Set<String> _permanentlyExcludedAssetIds;
  StreamSubscription<void>? _subscription;
  PrivateKeyExportAccess? _access;
  int _generation = 0;
  int _visibilityRevision = 0;
  int _qrRevision = 0;
  bool _checking = false;
  bool _closing = false;

  void _onSessionInvalidated() {
    if (!_closing && !isClosed) {
      add(const PrivateKeyExportAuthenticationLost());
    }
  }

  bool _current(int operation, Emitter<PrivateKeyExportState> emit) =>
      !_closing && !isClosed && !emit.isDone && operation == _generation;

  void _clear(
    Emitter<PrivateKeyExportState> emit, {
    PrivateKeyExportError? error,
  }) {
    _access = null;
    emit(
      PrivateKeyExportState(
        operationId: ++_generation,
        phase: error == null
            ? PrivateKeyExportPhase.idle
            : PrivateKeyExportPhase.failed,
        error: error,
      ),
    );
  }

  Future<void> _request(
    PrivateKeyExportRequested event,
    Emitter<PrivateKeyExportState> emit,
  ) async {
    if (state.phase != PrivateKeyExportPhase.idle &&
        state.phase != PrivateKeyExportPhase.failed) {
      return;
    }
    final operation = ++_generation;
    emit(
      PrivateKeyExportState(
        operationId: operation,
        phase: PrivateKeyExportPhase.starting,
        blockedAssets: event.blockedAssets,
        permanentlyExcludedAssetIds: _permanentlyExcludedAssetIds,
      ),
    );
    try {
      final access = await _service.begin();
      if (!_current(operation, emit)) return;
      _service.ensureCurrentSync(access);
      _access = access;
      emit(
        state.copyWith(
          phase: PrivateKeyExportPhase.awaitingPassword,
          walletName: access.walletName,
        ),
      );
    } catch (_) {
      if (_current(operation, emit)) {
        _clear(emit, error: PrivateKeyExportError.unavailable);
      }
    }
  }

  Future<void> _submitPassword(
    PrivateKeyExportPasswordSubmitted event,
    Emitter<PrivateKeyExportState> emit,
  ) async {
    final access = _access;
    final operation = _generation;
    if (event.operationId != operation ||
        access == null ||
        state.phase != PrivateKeyExportPhase.awaitingPassword) {
      return;
    }
    emit(
      state.copyWith(phase: PrivateKeyExportPhase.exporting, clearError: true),
    );
    try {
      final result = await _service.authenticateAndExport(
        access,
        event.password,
      );
      if (!_current(operation, emit)) return;
      await _requireCurrent(operation, access);
      if (!_current(operation, emit)) return;
      _requireCurrentSync(operation, access);
      emit(state.copyWith(phase: PrivateKeyExportPhase.ready, result: result));
    } on PrivateKeyExportException catch (error) {
      if (!_current(operation, emit)) return;
      if (error.reason == PrivateKeyExportError.incorrectPassword) {
        emit(
          state.copyWith(
            phase: PrivateKeyExportPhase.awaitingPassword,
            error: error.reason,
          ),
        );
      } else {
        _clear(emit, error: error.reason);
      }
    } catch (_) {
      if (_current(operation, emit)) {
        _clear(emit, error: PrivateKeyExportError.unavailable);
      }
    }
  }

  void _requireCurrentSync(int operation, PrivateKeyExportAccess access) {
    if (_closing ||
        isClosed ||
        operation != _generation ||
        !identical(access, _access)) {
      throw const PrivateKeyExportException(
        PrivateKeyExportError.sessionChanged,
      );
    }
    _service.ensureCurrentSync(access);
  }

  Future<void> _requireCurrent(
    int operation,
    PrivateKeyExportAccess access,
  ) async {
    _requireCurrentSync(operation, access);
    await _service.ensureCurrent(access);
    _requireCurrentSync(operation, access);
  }

  Future<void> _checkSession(
    PrivateKeyExportSessionCheckRequested event,
    Emitter<PrivateKeyExportState> emit,
  ) async {
    final access = _access;
    if (access == null || _checking) return;
    _checking = true;
    final operation = _generation;
    try {
      await _requireCurrent(operation, access);
    } catch (_) {
      if (_current(operation, emit)) {
        _clear(emit, error: PrivateKeyExportError.sessionChanged);
      }
    } finally {
      _checking = false;
    }
  }

  Future<void> _changeVisibility(
    PrivateKeyExportVisibilityChanged event,
    Emitter<PrivateKeyExportState> emit,
  ) async {
    if (state.phase != PrivateKeyExportPhase.ready) return;
    final visibilityRevision = ++_visibilityRevision;
    if (!event.visible) {
      emit(
        state.copyWith(showKeys: false, clearQr: true, revealedKeys: const {}),
      );
      return;
    }
    final operation = _generation;
    final access = _access;
    if (access == null) return;
    try {
      await _requireCurrent(operation, access);
      if (_current(operation, emit) &&
          visibilityRevision == _visibilityRevision) {
        _requireCurrentSync(operation, access);
        emit(state.copyWith(showKeys: true));
      }
    } catch (_) {
      if (_current(operation, emit)) {
        _clear(emit, error: PrivateKeyExportError.sessionChanged);
      }
    }
  }

  Future<void> _toggleKeyVisibility(
    PrivateKeyExportKeyVisibilityToggled event,
    Emitter<PrivateKeyExportState> emit,
  ) async {
    if (!state.showKeys ||
        state.phase != PrivateKeyExportPhase.ready ||
        state.keyAt(event.assetId, event.keyIndex) == null) {
      return;
    }
    final reference = (event.assetId, event.keyIndex);
    if (state.revealedKeys.contains(reference)) {
      emit(
        state.copyWith(
          revealedKeys: {...state.revealedKeys}..remove(reference),
        ),
      );
      return;
    }
    final access = _access;
    final operation = _generation;
    final visibility = _visibilityRevision;
    if (access == null) return;
    try {
      await _requireCurrent(operation, access);
      if (_current(operation, emit) &&
          state.showKeys &&
          visibility == _visibilityRevision &&
          state.keyAt(event.assetId, event.keyIndex) != null) {
        _requireCurrentSync(operation, access);
        emit(state.copyWith(revealedKeys: {...state.revealedKeys, reference}));
      }
    } catch (_) {
      if (_current(operation, emit)) {
        _clear(emit, error: PrivateKeyExportError.sessionChanged);
      }
    }
  }

  Future<void> _showQr(
    PrivateKeyExportQrRequested event,
    Emitter<PrivateKeyExportState> emit,
  ) async {
    if (!state.canDeliver ||
        state.keyAt(event.assetId, event.keyIndex) == null) {
      return;
    }
    final access = _access;
    final operation = _generation;
    final visibility = _visibilityRevision;
    final qrRevision = ++_qrRevision;
    if (access == null) return;
    try {
      await _requireCurrent(operation, access);
      if (_current(operation, emit) &&
          state.canDeliver &&
          visibility == _visibilityRevision &&
          qrRevision == _qrRevision &&
          state.keyAt(event.assetId, event.keyIndex) != null) {
        _requireCurrentSync(operation, access);
        emit(state.copyWith(qrKey: (event.assetId, event.keyIndex)));
      }
    } catch (_) {
      if (_current(operation, emit)) {
        _clear(emit, error: PrivateKeyExportError.sessionChanged);
      }
    }
  }

  Future<void> _deliver(
    PrivateKeyExportDeliveryRequested event,
    Emitter<PrivateKeyExportState> emit,
  ) async {
    final access = _access;
    final result = state.result;
    if (!state.canDeliver || access == null || result == null) return;
    final operation = _generation;
    final asset = event.assetId;
    final index = event.keyIndex;
    final singleKey = asset == null || index == null
        ? null
        : state.keyAt(asset, index);
    if (asset != null &&
        (singleKey == null || event.action != PrivateKeyExportAction.copy)) {
      return;
    }
    final content = singleKey == null
        ? privateKeyExportDocument(result, excludedAssets: state.excludedAssets)
        : SensitiveString(singleKey.privateKey);
    _qrRevision++;
    emit(
      state.copyWith(
        isDelivering: true,
        clearQr: true,
        clearDelivery: true,
        deliveryFailed: false,
      ),
    );
    try {
      final outcome = await _delivery.deliver(
        action: event.action,
        content: content,
        beforeWrite: () => _requireCurrent(operation, access),
        beforeCommit: () => _requireCurrentSync(operation, access),
      );
      if (!_current(operation, emit)) return;
      await _requireCurrent(operation, access);
      if (!_current(operation, emit)) return;
      _requireCurrentSync(operation, access);
      emit(
        state.copyWith(
          isDelivering: false,
          deliveryOutcome: outcome,
          deliveryRevision: state.deliveryRevision + 1,
          hasExported:
              state.hasExported ||
              outcome == PrivateKeyExportDeliveryOutcome.completed,
        ),
      );
    } on PrivateKeyExportException catch (error) {
      if (_current(operation, emit)) _clear(emit, error: error.reason);
    } catch (_) {
      if (_current(operation, emit)) {
        emit(
          state.copyWith(
            isDelivering: false,
            deliveryFailed: true,
            deliveryRevision: state.deliveryRevision + 1,
          ),
        );
      }
    }
  }

  @override
  Future<void> close() async {
    _closing = true;
    _access = null;
    // Drop the retained secret result before asynchronous subscription disposal.
    // ignore: invalid_use_of_visible_for_testing_member
    emit(PrivateKeyExportState(operationId: ++_generation));
    await _subscription?.cancel();
    return super.close();
  }
}
