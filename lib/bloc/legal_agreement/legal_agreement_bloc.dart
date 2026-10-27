import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:logging/logging.dart';
import 'package:web_dex/services/legal_documents/legal_document.dart';
import 'package:web_dex/services/legal_documents/legal_documents_repository.dart';

sealed class LegalAgreementEvent extends Equatable {
  const LegalAgreementEvent();
  @override
  List<Object?> get props => [];
}

class LegalAgreementOpened extends LegalAgreementEvent {
  const LegalAgreementOpened();
}

class LegalAgreementRetried extends LegalAgreementEvent {
  const LegalAgreementRetried();
}

class LegalAgreementSubmitted extends LegalAgreementEvent {
  const LegalAgreementSubmitted(this.surface, {required this.snapshot});
  final String surface;
  final LegalConsentSnapshot? snapshot;
  @override
  List<Object?> get props => [surface, snapshot];
}

enum LegalAgreementStatus {
  loading,
  initial,
  current,
  updated,
  unavailable,
  placeholder,
}

class LegalAgreementState extends Equatable {
  const LegalAgreementState(this.status, [this.snapshot]);
  final LegalAgreementStatus status;
  final LegalConsentSnapshot? snapshot;
  @override
  List<Object?> get props => [status, snapshot];
}

class LegalAgreementBloc
    extends Bloc<LegalAgreementEvent, LegalAgreementState> {
  LegalAgreementBloc(this._repository)
    : super(const LegalAgreementState(LegalAgreementStatus.loading)) {
    on<LegalAgreementOpened>(_onOpened, transformer: restartable());
    on<LegalAgreementRetried>(_onRetried, transformer: droppable());
    on<LegalAgreementSubmitted>(_onSubmitted);
    _changes = _repository.changes.listen((_) {
      if (!isClosed && !_submitted) add(const LegalAgreementOpened());
    });
  }

  final LegalDocumentsRepository _repository;
  final _log = Logger('LegalAgreementBloc');
  late final StreamSubscription<void> _changes;
  bool _submitted = false;

  LegalConsentSnapshot? get presentedSnapshot => state.snapshot;
  bool get canSubmit => _repository.canSubmit(presentedSnapshot);
  bool get documentsAvailable => presentedSnapshot?.isAvailable ?? false;

  Future<void> _onOpened(
    LegalAgreementOpened event,
    Emitter<LegalAgreementState> emit,
  ) async {
    if (_submitted) return;
    try {
      var snapshot = await _repository.loadConsentSnapshot();
      if (!snapshot.isAvailable) {
        if (emit.isDone || _submitted) return;
        emit(const LegalAgreementState(LegalAgreementStatus.loading));
        await _repository.refreshConsentDocuments();
        snapshot = await _repository.loadConsentSnapshot();
      } else {
        unawaited(_repository.refreshConsentDocuments());
      }
      if (emit.isDone || _submitted) return;
      if (!snapshot.isAvailable) {
        emit(
          LegalAgreementState(
            snapshot.status == LegalDocumentStatus.placeholder
                ? LegalAgreementStatus.placeholder
                : LegalAgreementStatus.unavailable,
            snapshot,
          ),
        );
        return;
      }
      // Publish the full document identity even if acceptance lookup is slow.
      emit(LegalAgreementState(LegalAgreementStatus.initial, snapshot));
      final current = await _repository.hasAcceptedCurrentTerms(
        snapshot: snapshot,
      );
      final previous = current ? null : await _repository.readAcceptance();
      if (emit.isDone || _submitted) return;
      emit(
        LegalAgreementState(
          current
              ? LegalAgreementStatus.current
              : previous == null
              ? LegalAgreementStatus.initial
              : LegalAgreementStatus.updated,
          snapshot,
        ),
      );
    } catch (error, stackTrace) {
      _log.warning('Could not load consent documents', error, stackTrace);
      if (!emit.isDone && !_submitted) {
        emit(const LegalAgreementState(LegalAgreementStatus.unavailable));
      }
    }
  }

  Future<void> _onRetried(
    LegalAgreementRetried event,
    Emitter<LegalAgreementState> emit,
  ) async {
    if (_submitted) return;
    if (!documentsAvailable) {
      emit(const LegalAgreementState(LegalAgreementStatus.loading));
    }
    await _repository.refreshConsentDocuments(force: true);
    if (!isClosed && !_submitted) add(const LegalAgreementOpened());
  }

  void _onSubmitted(
    LegalAgreementSubmitted event,
    Emitter<LegalAgreementState> emit,
  ) {
    if (_submitted || !_repository.canSubmit(event.snapshot)) return;
    _submitted = true;
    final snapshot = event.snapshot;
    // Freeze what was actually presented; never await later text after a bypass.
    if (snapshot == null || !snapshot.isAvailable) return;
    unawaited(
      _repository.recordAcceptance(surface: event.surface, snapshot: snapshot),
    );
  }

  @override
  Future<void> close() async {
    await _changes.cancel();
    await super.close();
  }
}
