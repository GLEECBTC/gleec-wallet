// ignore_for_file: invalid_use_of_visible_for_testing_member
import 'dart:async';
import 'package:fake_async/fake_async.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_event.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_state.dart';
import 'package:web_dex/services/legal_documents/legal_document.dart';
import 'package:web_dex/services/legal_documents/legal_documents_repository.dart';
import 'package:web_dex/shared/swap/swap_terms_repository.dart';
import 'package:web_dex/views/swap/review/swap_review_view.dart';
import '../../support/legal_documents_fixture.dart';

import 'swap_bloc_fakes.dart';
import 'swap_entry_ui_fakes.dart';
import 'swap_test_fixtures.dart';

void main() {
  for (final outcome in [
    'success',
    'failure',
    'closed',
    'reopened',
    'policyRefresh',
  ]) {
    test('routed swap waits for pending documents: $outcome', () {
      fakeAsync((async) {
        final response = Completer<http.Response>();
        final repository = LegalDocumentsRepository(
          storage: LegalFixtureStorage(populated: false),
          bypassGate: false,
          httpClient: MockClient((_) => response.future),
        );
        final h = SwapBlocHarness(async, legalDocuments: repository);
        try {
          final bloc = h.inReview();
          expect(bloc.state.review!.legalLoading, isTrue);
          expect(bloc.state.review!.canStart, isTrue);
          bloc.add(const UnifiedSwapStartRequested());
          bloc.add(const UnifiedSwapStartRequested());
          h.settle();
          expect(h.routedExecutor.started, isEmpty);
          expect(
            h.storage.values.values.map(SwapTermsAcceptance.tryParse).nonNulls,
            isEmpty,
          );
          if (outcome == 'closed' || outcome == 'reopened') {
            bloc.add(const UnifiedSwapReviewClosed());
            h.settle();
            if (outcome == 'reopened') {
              bloc.add(const UnifiedSwapReviewOpened());
              h.settle();
            }
          }
          if (outcome == 'policyRefresh') {
            bloc.add(
              const UnifiedSwapCapabilitiesChanged(
                tradingEnabled: false,
                tradingStatusLoading: true,
                clockValid: true,
              ),
            );
            h.settle();
            bloc.add(
              const UnifiedSwapCapabilitiesChanged(
                tradingEnabled: true,
                clockValid: true,
              ),
            );
            h.settle();
          }
          response.complete(
            outcome == 'failure'
                ? http.Response('', 404)
                : http.Response(
                    '# Published full terms',
                    200,
                    headers: {'content-type': 'text/markdown'},
                  ),
          );
          h.settle();
          expect(
            h.routedExecutor.started,
            outcome == 'success' ? hasLength(1) : isEmpty,
          );
          final acceptances = h.storage.values.values
              .map(SwapTermsAcceptance.tryParse)
              .nonNulls;
          expect(acceptances, outcome == 'success' ? hasLength(1) : isEmpty);
          if (outcome == 'failure') {
            expect(bloc.state.review!.canStart, isFalse);
            expect(bloc.state.review!.showLegalFailure, isTrue);
          }
          if (outcome == 'reopened' || outcome == 'policyRefresh') {
            expect(bloc.state.review!.legalLoading, isFalse);
            expect(bloc.state.review!.canStart, isTrue);
          }
        } finally {
          h.dispose();
        }
      });
    });
  }
  for (final bypass in [false, true]) {
    for (final placeholder in [false, true]) {
      test('routed swap guard bypass=$bypass placeholder=$placeholder', () {
        fakeAsync((async) {
          var online = false;
          final legalStorage = LegalFixtureStorage(populated: false);
          final repository = LegalDocumentsRepository(
            storage: legalStorage,
            bypassGate: bypass,
            httpClient: MockClient(
              (_) async => online
                  ? http.Response(
                      '# Published terms',
                      200,
                      headers: {'content-type': 'text/markdown'},
                    )
                  : placeholder
                  ? http.Response(
                      '$legalPlaceholderMarker\n# Pending',
                      200,
                      headers: {'content-type': 'text/markdown'},
                    )
                  : http.Response('', 404),
            ),
          );
          final h = SwapBlocHarness(async, legalDocuments: repository);
          try {
            final bloc = h.inReview();
            expect(bloc.state.review!.canStart, bypass);
            bloc.add(const UnifiedSwapStartRequested());
            h.settle();
            expect(h.routedExecutor.started, bypass ? hasLength(1) : isEmpty);
            expect(
              h.storage.values.values
                  .map(SwapTermsAcceptance.tryParse)
                  .nonNulls,
              isEmpty,
            );
            if (!bypass) {
              online = true;
              bloc.add(const UnifiedSwapLegalRequested(retry: true));
              h.settle();
              expect(
                bloc.state.review!.canStart,
                isTrue,
                reason: '${bloc.state.review} ${legalStorage.values}',
              );
              final presented = bloc.state.review!.legalSnapshot!;
              bloc.add(const UnifiedSwapStartRequested());
              h.settle();
              expect(h.routedExecutor.started, hasLength(1));
              final acceptance = h.storage.values.values
                  .map(SwapTermsAcceptance.tryParse)
                  .nonNulls
                  .single;
              expect(acceptance.documentShas, presented.documentShas);
              expect(acceptance.documentShas, hasLength(3));
            }
          } finally {
            h.dispose();
          }
        });
      });
    }
  }

  group('Routed swap legal UI', () {
    setUpSwapUi();
    for (final status in [
      LegalDocumentStatus.loading,
      LegalDocumentStatus.unavailable,
      LegalDocumentStatus.placeholder,
    ]) {
      testWidgets(
        '$status shows failure only after retrieval resolves and recovers',
        (tester) async {
          final bloc = RecordingSwapBloc();
          addTearDown(bloc.close);
          final services = FakeSwapServices();
          final missing = LegalConsentSnapshot.fromDocuments({
            for (final d in swapConsentDocuments)
              d: LegalDocumentContent.unavailable(status: status),
          }, requiredDocuments: swapConsentDocuments);
          final state = swapPricedForm().copyWith(
            view: UnifiedSwapView.review,
            review: SwapReview(
              quote: quoteOf(),
              status: SwapReviewStatus.ready,
              legalSnapshot: missing,
              legalLoading: status == LegalDocumentStatus.loading,
            ),
          );
          bloc.emit(state);
          await pumpSwapUi(
            tester,
            const SwapReviewView(),
            bloc: bloc,
            services: services,
            size: const Size(360, 800),
          );
          final button = find.byKey(const Key('swap-start'));
          final pending = status == LegalDocumentStatus.loading;
          expect(swapButtonEnabled(tester, find.text('Start swap')), pending);
          expect(
            find.byKey(const Key('legal-documents-unavailable')),
            pending ? findsNothing : findsOneWidget,
          );
          expect(
            find.byTooltip(
              'The legal documentation could not be retrieved. Please consult Gleec’s online legal documentation before proceeding.',
            ),
            pending ? findsNothing : findsOneWidget,
          );
          await tester.tap(button);
          expect(
            bloc.events,
            pending ? [const UnifiedSwapStartRequested()] : isEmpty,
          );
          bloc.events.clear();
          if (status != LegalDocumentStatus.loading) {
            await tester.tap(find.byKey(const Key('legal-documents-retry')));
            expect(bloc.events, [const UnifiedSwapLegalRequested(retry: true)]);
          }
          await emitSwapState(
            tester,
            bloc,
            state.copyWith(
              review: state.review!.copyWith(
                legalSnapshot: legalFixtureSnapshot(),
                legalLoading: false,
              ),
            ),
          );
          expect(swapButtonEnabled(tester, find.text('Start swap')), isTrue);
          expect(
            find.byKey(const Key('legal-documents-unavailable')),
            findsNothing,
          );
          expect(tester.takeException(), isNull);
        },
      );
    }
  });
}
