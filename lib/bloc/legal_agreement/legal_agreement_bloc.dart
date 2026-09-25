import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:logging/logging.dart';
import 'package:web_dex/services/legal_documents/legal_document.dart';
import 'package:web_dex/services/legal_documents/legal_documents_repository.dart';

sealed class LegalAgreementEvent {
  const LegalAgreementEvent();
}

class LegalAgreementOpened extends LegalAgreementEvent {
  const LegalAgreementOpened();
}

/// Dispatched only by the form action named in the adjacent legal notice.
class LegalAgreementSubmitted extends LegalAgreementEvent {
  const LegalAgreementSubmitted(this.surface);

  final String surface;
}

enum LegalAgreementStatus { initial, current, updated }

/// Legal status adds context to the form; it never inserts a navigation gate.
class LegalAgreementBloc
    extends Bloc<LegalAgreementEvent, LegalAgreementStatus> {
  LegalAgreementBloc(this._repository) : super(LegalAgreementStatus.initial) {
    on<LegalAgreementOpened>(_onOpened, transformer: restartable());
    on<LegalAgreementSubmitted>(_onSubmitted);
    _changes = _repository.changes.listen((_) {
      if (!isClosed && !_submitted) add(const LegalAgreementOpened());
    });
  }

  final LegalDocumentsRepository _repository;
  final _log = Logger('LegalAgreementBloc');
  bool _submitted = false;
  late final StreamSubscription<void> _changes;
  Future<LegalConsentSnapshot>? _openingSnapshot;
  LegalConsentSnapshot? _presentedSnapshot;

  LegalConsentSnapshot? get presentedSnapshot => _presentedSnapshot;

  Future<void> _onOpened(
    LegalAgreementOpened event,
    Emitter<LegalAgreementStatus> emit,
  ) async {
    if (_submitted) return;
    final opening = _repository.loadConsentSnapshot();
    _openingSnapshot = opening;
    final LegalConsentSnapshot snapshot;
    try {
      snapshot = await opening;
    } catch (error, stackTrace) {
      _log.warning('Could not load consent documents', error, stackTrace);
      return;
    }
    if (emit.isDone || _submitted) return;
    _presentedSnapshot = snapshot;
    unawaited(_repository.refreshConsentDocuments());
    final current = await _repository.hasAcceptedCurrentTerms(
      snapshot: snapshot,
    );
    final previous = current ? null : await _repository.readAcceptance();
    if (emit.isDone || _submitted) return;
    emit(
      current
          ? LegalAgreementStatus.current
          : previous == null
          ? LegalAgreementStatus.initial
          : LegalAgreementStatus.updated,
    );
  }

  void _onSubmitted(
    LegalAgreementSubmitted event,
    Emitter<LegalAgreementStatus> emit,
  ) {
    if (_submitted) return;
    _submitted = true;
    // The repository logs storage failures. Access to a wallet must not depend
    // on persistence or on the status lookup finishing before the user submits.
    final snapshot = _presentedSnapshot;
    final opening = _openingSnapshot ?? _repository.loadConsentSnapshot();
    unawaited(() async {
      try {
        await _repository.recordAcceptance(
          surface: event.surface,
          snapshot: snapshot ?? await opening,
        );
      } catch (error, stackTrace) {
        _log.warning(
          'Could not record the presented consent',
          error,
          stackTrace,
        );
      }
    }());
  }

  @override
  Future<void> close() async {
    await _changes.cancel();
    await super.close();
  }
}
