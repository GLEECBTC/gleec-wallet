import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
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
    on<LegalAgreementOpened>(_onOpened);
    on<LegalAgreementSubmitted>(_onSubmitted);
  }

  final LegalDocumentsRepository _repository;
  bool _submitted = false;

  Future<void> _onOpened(
    LegalAgreementOpened event,
    Emitter<LegalAgreementStatus> emit,
  ) async {
    final current = await _repository.hasAcceptedCurrentTerms();
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
    unawaited(_repository.recordAcceptance(surface: event.surface));
  }
}
