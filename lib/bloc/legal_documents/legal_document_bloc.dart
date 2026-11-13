import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:web_dex/services/legal_documents/legal_document.dart';
import 'package:web_dex/services/legal_documents/legal_documents_repository.dart';

class LegalDocumentRequested extends Equatable {
  const LegalDocumentRequested({this.retry = false});
  final bool retry;
  @override
  List<Object?> get props => [retry];
}

class LegalDocumentBloc
    extends Bloc<LegalDocumentRequested, LegalDocumentContent> {
  LegalDocumentBloc(
    this._repository,
    this.document, {
    LegalDocumentContent? content,
  }) : _pinned = content?.isAvailable == true ? content : null,
       super(
         content ??
             const LegalDocumentContent.unavailable(
               status: LegalDocumentStatus.loading,
             ),
       ) {
    on<LegalDocumentRequested>(_onRequested, transformer: restartable());
  }
  final LegalDocumentsRepository _repository;
  final LegalDocumentType document;
  final LegalDocumentContent? _pinned;

  Future<void> _onRequested(
    LegalDocumentRequested event,
    Emitter<LegalDocumentContent> emit,
  ) async {
    if (_pinned case final pinned?) {
      emit(pinned);
      return;
    }
    final cached = await _repository.loadPreferredContent(document);
    if (emit.isDone) return;
    emit(
      cached.isAvailable || state.status != LegalDocumentStatus.loading
          ? cached
          : const LegalDocumentContent.unavailable(
              status: LegalDocumentStatus.loading,
            ),
    );
    await _repository.refreshFromRemote(document, force: event.retry);
    final result = await _repository.loadPreferredContent(document);
    if (!emit.isDone) emit(result);
  }
}
