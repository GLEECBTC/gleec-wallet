import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:web_dex/bloc/legal_agreement/legal_agreement_bloc.dart';
import 'package:web_dex/services/legal_documents/legal_acceptance.dart';
import 'package:web_dex/services/legal_documents/legal_document.dart';
import 'package:web_dex/services/legal_documents/legal_documents_repository.dart';
import '../../support/legal_documents_fixture.dart';

class _Repository extends Fake implements LegalDocumentsRepository {
  _Repository({this.current = false, this.previous = false, this.lookup});
  final bool current;
  final bool previous;
  final Future<bool>? lookup;
  final submissions = <String>[];
  final write = Completer<void>();

  @override
  Stream<void> get changes => const Stream.empty();

  @override
  Future<void> refreshConsentDocuments({bool force = false}) async {}

  @override
  bool canSubmit(LegalConsentSnapshot? snapshot) =>
      snapshot?.isAvailable ?? false;

  @override
  Future<LegalConsentSnapshot> loadConsentSnapshot() async =>
      legalFixtureSnapshot(documents: walletConsentDocuments);

  @override
  Future<bool> hasAcceptedCurrentTerms({
    LegalConsentSnapshot? snapshot,
  }) async => lookup ?? current;

  @override
  Future<LegalAcceptance?> readAcceptance() async => previous
      ? LegalAcceptance(
          termsVersion: 0,
          acceptedAt: DateTime(2020),
          surface: 'old-form',
          documentShas: {},
        )
      : null;

  @override
  Future<void> recordAcceptance({
    required String surface,
    LegalConsentSnapshot? snapshot,
  }) {
    submissions.add(surface);
    return write.future;
  }
}

void main() {
  group('LegalAgreementBloc', () {
    for (final (current, previous, expected) in [
      (false, false, LegalAgreementStatus.initial),
      (true, true, LegalAgreementStatus.current),
      (false, true, LegalAgreementStatus.updated),
    ]) {
      test('reports $expected without accepting', () async {
        final repository = _Repository(current: current, previous: previous);
        final bloc = LegalAgreementBloc(repository)
          ..add(const LegalAgreementOpened());
        await Future<void>.delayed(Duration.zero);
        expect(bloc.state.status, expected);
        expect(repository.submissions, isEmpty);
        await bloc.close();
      });
    }

    test('submits once without waiting for lookup or storage', () async {
      final lookup = Completer<bool>();
      final repository = _Repository(previous: true, lookup: lookup.future);
      final bloc = LegalAgreementBloc(repository)
        ..add(const LegalAgreementOpened());
      await Future<void>.delayed(Duration.zero);
      bloc
        ..add(
          LegalAgreementSubmitted(
            'wallet-creation',
            snapshot: bloc.presentedSnapshot,
          ),
        )
        ..add(
          LegalAgreementSubmitted(
            'wallet-creation',
            snapshot: bloc.presentedSnapshot,
          ),
        );
      await Future<void>.delayed(Duration.zero);
      expect(repository.submissions, ['wallet-creation']);
      expect(repository.write.isCompleted, isFalse);
      lookup.complete(false);
      await Future<void>.delayed(Duration.zero);
      expect(bloc.state.status, LegalAgreementStatus.initial);
      repository.write.complete();
      await bloc.close();
    });

    test(
      'closing while status loads never emits or records acceptance',
      () async {
        final lookup = Completer<bool>();
        final repository = _Repository(previous: true, lookup: lookup.future);
        final bloc = LegalAgreementBloc(repository)
          ..add(const LegalAgreementOpened());
        await Future<void>.delayed(Duration.zero);
        final closing = bloc.close();
        lookup.complete(false);
        await closing;
        expect(repository.submissions, isEmpty);
      },
    );
  });
}
