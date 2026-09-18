import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:web_dex/bloc/legal_agreement/legal_agreement_bloc.dart';
import 'package:web_dex/services/legal_documents/legal_acceptance.dart';
import 'package:web_dex/services/legal_documents/legal_documents_repository.dart';

class _Repository extends Fake implements LegalDocumentsRepository {
  _Repository({this.current = false, this.previous = false, this.lookup});
  final bool current;
  final bool previous;
  final Future<bool>? lookup;
  final submissions = <String>[];
  final write = Completer<void>();

  @override
  Future<bool> hasAcceptedCurrentTerms() async => lookup ?? current;

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
  Future<void> recordAcceptance({required String surface}) {
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
        expect(bloc.state, expected);
        expect(repository.submissions, isEmpty);
        await bloc.close();
      });
    }

    test('submits once without waiting for lookup or storage', () async {
      final lookup = Completer<bool>();
      final repository = _Repository(previous: true, lookup: lookup.future);
      final bloc = LegalAgreementBloc(repository)
        ..add(const LegalAgreementOpened())
        ..add(const LegalAgreementSubmitted('wallet-creation'))
        ..add(const LegalAgreementSubmitted('wallet-creation'));
      await Future<void>.delayed(Duration.zero);
      expect(repository.submissions, ['wallet-creation']);
      expect(repository.write.isCompleted, isFalse);
      lookup.complete(false);
      await Future<void>.delayed(Duration.zero);
      expect(bloc.state, LegalAgreementStatus.initial);
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
