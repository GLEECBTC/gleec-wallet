import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:web_dex/bloc/legal_agreement/legal_agreement_bloc.dart';
import 'package:web_dex/bloc/legal_documents/legal_document_bloc.dart';
import 'package:web_dex/services/legal_documents/legal_document.dart';
import 'package:web_dex/services/legal_documents/legal_documents_repository.dart';
import 'package:web_dex/shared/constants.dart';
import 'package:web_dex/shared/swap/swap_terms_repository.dart';
import '../../support/legal_documents_fixture.dart';

http.Response _markdown(String text, {String? etag}) => http.Response.bytes(
  utf8.encode(text),
  200,
  headers: {
    'content-type': 'text/markdown; charset=utf-8',
    if (etag != null) 'etag': etag,
  },
);

void main() {
  group('Remote legal hosting', () {
    test('uses the five fixed root URLs and decodes UTF-8 bytes', () async {
      final urls = <String>[];
      final repo = LegalDocumentsRepository(
        storage: LegalFixtureStorage(populated: false),
        httpClient: MockClient((r) async {
          urls.add(r.url.toString());
          return _markdown('# Gleec — café ⚖');
        }),
      );
      addTearDown(repo.dispose);
      await repo.refreshDocuments(LegalDocumentType.values);
      expect(urls.toSet(), {
        'https://privacy.gleec.com/eula_gleec_wallet.md',
        'https://privacy.gleec.com/tos_gleec_wallet.md',
        'https://privacy.gleec.com/privacy_notice_gleec_wallet.md',
        'https://privacy.gleec.com/kyc_due_diligence_policy_gleec_wallet.md',
        'https://privacy.gleec.com/tos_lifi_gleec_wallet.md',
      });
      final snapshot = await repo.loadSnapshot(swapConsentDocuments);
      expect(snapshot.isAvailable, isTrue);
      expect(
        snapshot.documents[LegalDocumentType.eula]!.markdown,
        '# Gleec — café ⚖',
      );
    });

    test(
      'cold-start 404s fetch, block consent, and retry without waiting for throttle',
      () async {
        var available = false;
        var calls = 0;
        final repo = LegalDocumentsRepository(
          storage: LegalFixtureStorage(populated: false),
          bypassGate: false,
          httpClient: MockClient((_) async {
            calls++;
            return available
                ? _markdown('# Full terms')
                : http.Response('Not found', 404);
          }),
        );
        addTearDown(repo.dispose);
        final bloc = LegalAgreementBloc(repo);
        addTearDown(bloc.close);
        expect(bloc.state.status, LegalAgreementStatus.loading);
        expect(bloc.canSubmit, isTrue);
        expect(bloc.canComplete, isFalse);
        final failed = bloc.stream.firstWhere(
          (s) => s.status == LegalAgreementStatus.unavailable,
        );
        bloc.add(const LegalAgreementOpened());
        await failed;
        expect(calls, 2);
        expect(bloc.canSubmit, isFalse);
        bloc.add(
          LegalAgreementSubmitted('blocked', snapshot: bloc.presentedSnapshot),
        );
        await Future<void>.delayed(Duration.zero);
        expect(await repo.readAcceptance(), isNull);
        available = true;
        final ready = bloc.stream.firstWhere(
          (s) => s.snapshot?.isAvailable ?? false,
        );
        bloc.add(const LegalAgreementRetried());
        await ready;
        expect(calls, 4);
        expect(bloc.canSubmit, isTrue);
      },
    );

    for (final (label, response) in [
      ('empty body', _markdown('  \n')),
      (
        'HTML MIME',
        http.Response(
          '<html>error</html>',
          200,
          headers: {'content-type': 'text/html'},
        ),
      ),
      (
        'disguised HTML',
        _markdown('<!-- proxy -->\n<!DOCTYPE html><html>404</html>'),
      ),
      ('JSON error', _markdown('{"error":"not found"}')),
      (
        'invalid UTF-8',
        http.Response.bytes(
          [0xc3, 0x28],
          200,
          headers: {'content-type': 'text/plain'},
        ),
      ),
      ('server failure', http.Response('Unavailable', 503)),
    ]) {
      test('$label never replaces valid cached text', () async {
        final storage = LegalFixtureStorage();
        final repo = LegalDocumentsRepository(
          storage: storage,
          httpClient: MockClient((_) async => response),
        );
        addTearDown(repo.dispose);
        final before = await repo.loadConsentSnapshot();
        await repo.refreshConsentDocuments();
        expect(
          (await repo.loadConsentSnapshot()).documentShas,
          before.documentShas,
        );
        expect(repo.canSubmit(await repo.loadConsentSnapshot()), isTrue);
        await storage.delete(LegalDocumentType.eula.cacheKey);
        await repo.refreshFromRemote(LegalDocumentType.eula);
        expect(
          (await repo.loadPreferredContent(LegalDocumentType.eula)).status,
          LegalDocumentStatus.unavailable,
        );
      });
    }

    test('Markdown starting with a link is valid', () {
      expect(isLegalMarkdown('[Gleec](https://gleec.com/)\n\nTerms.'), isTrue);
    });

    test(
      'offline uses validated legacy cache and rejects corrupt cache',
      () async {
        final storage = LegalFixtureStorage();
        final repo = LegalDocumentsRepository(
          storage: storage,
          httpClient: MockClient(
            (_) async => throw http.ClientException('offline'),
          ),
        );
        addTearDown(repo.dispose);
        final before = await repo.loadConsentSnapshot();
        await repo.refreshConsentDocuments();
        expect((await repo.loadConsentSnapshot()).isAvailable, isTrue);
        expect(
          (await repo.loadConsentSnapshot()).documentShas,
          before.documentShas,
        );
        (storage.values[LegalDocumentType.eula.cacheKey] as Map)['sha'] =
            'corrupt';
        expect((await repo.loadConsentSnapshot()).isAvailable, isFalse);
      },
    );

    test(
      'placeholder is explicit and cannot overwrite full cache or be accepted',
      () async {
        final storage = LegalFixtureStorage(populated: false);
        final repo = LegalDocumentsRepository(
          storage: storage,
          httpClient: MockClient(
            (_) async => _markdown('$legalPlaceholderMarker\n# Pending'),
          ),
        );
        addTearDown(repo.dispose);
        await repo.refreshDocuments(swapConsentDocuments);
        final missing = await repo.loadSnapshot(swapConsentDocuments);
        expect(missing.status, LegalDocumentStatus.placeholder);
        expect(missing.documentShas, isEmpty);
        expect(storage.values, isEmpty);
        await repo.recordAcceptance(surface: 'placeholder', snapshot: missing);
        expect(await repo.readAcceptance(), isNull);
        storage.values.addAll(LegalFixtureStorage().values);
        final before = await repo.loadSnapshot(swapConsentDocuments);
        await repo.refreshDocuments(swapConsentDocuments, force: true);
        expect(
          (await repo.loadSnapshot(swapConsentDocuments)).documentShas,
          before.documentShas,
        );
      },
    );

    test(
      'ETag revalidation retains content and new content changes acceptance',
      () async {
        final storage = LegalFixtureStorage(populated: false);
        final requests = <http.Request>[];
        var revision = 1;
        final repo = LegalDocumentsRepository(
          storage: storage,
          httpClient: MockClient((r) async {
            requests.add(r);
            if (r.headers['if-none-match'] == '"v$revision"') {
              return http.Response('', 304);
            }
            return _markdown('# Revision $revision', etag: '"v$revision"');
          }),
        );
        addTearDown(repo.dispose);
        await repo.refreshConsentDocuments();
        final before = await repo.loadConsentSnapshot();
        await repo.recordAcceptance(surface: 'initial', snapshot: before);
        expect(await repo.hasAcceptedCurrentTerms(), isTrue);
        await repo.refreshConsentDocuments(force: true);
        expect(
          requests.skip(2).map((r) => r.headers['if-none-match']),
          everyElement('"v1"'),
        );
        expect(
          (await repo.loadConsentSnapshot()).documentShas,
          before.documentShas,
        );
        revision = 2;
        await repo.refreshConsentDocuments(force: true);
        expect(await repo.hasAcceptedCurrentTerms(), isFalse);
        expect(
          before.documents[LegalDocumentType.eula]!.markdown,
          '# Revision 1',
        );
      },
    );

    test(
      'old endpoint ETags and orphaned 304s do not create available terms',
      () async {
        final storage = LegalFixtureStorage();
        final cached = storage.values[LegalDocumentType.eula.cacheKey] as Map;
        cached['etag'] = 'old-github-tag';
        cached['url'] = 'https://api.github.com/old';
        final repo = LegalDocumentsRepository(
          storage: storage,
          httpClient: MockClient((r) async {
            expect(r.headers['if-none-match'], isNull);
            return http.Response('', 304);
          }),
        );
        addTearDown(repo.dispose);
        await repo.refreshFromRemote(LegalDocumentType.eula);
        expect(
          (await repo.loadPreferredContent(LegalDocumentType.eula)).isAvailable,
          isTrue,
        );
        await storage.delete(LegalDocumentType.eula.cacheKey);
        await repo.refreshFromRemote(LegalDocumentType.eula);
        expect(
          (await repo.loadPreferredContent(LegalDocumentType.eula)).isAvailable,
          isFalse,
        );
      },
    );

    test(
      'the viewer starts on an empty device and retry makes it readable',
      () async {
        var available = false;
        final repo = LegalDocumentsRepository(
          storage: LegalFixtureStorage(populated: false),
          httpClient: MockClient(
            (_) async =>
                available ? _markdown('# Readable') : http.Response('', 404),
          ),
        );
        addTearDown(repo.dispose);
        final bloc = LegalDocumentBloc(repo, LegalDocumentType.privacyNotice);
        addTearDown(bloc.close);
        final missing = bloc.stream.firstWhere(
          (s) => s.status == LegalDocumentStatus.unavailable,
        );
        bloc.add(const LegalDocumentRequested());
        await missing;
        available = true;
        final full = bloc.stream.firstWhere((s) => s.isAvailable);
        bloc.add(const LegalDocumentRequested(retry: true));
        expect((await full).markdown, '# Readable');
      },
    );

    for (final bypass in [false, true]) {
      for (final placeholder in [false, true]) {
        test(
          'bypass=$bypass placeholder=$placeholder never manufactures consent',
          () async {
            final storage = LegalFixtureStorage(populated: false);
            final repo = LegalDocumentsRepository(
              storage: storage,
              bypassGate: bypass,
              httpClient: MockClient(
                (_) async => placeholder
                    ? _markdown('$legalPlaceholderMarker\n# Pending')
                    : http.Response('', 404),
              ),
            );
            addTearDown(repo.dispose);
            await repo.refreshDocuments(swapConsentDocuments);
            final snapshot = await repo.loadSnapshot(swapConsentDocuments);
            final terms = SwapTermsRepository(
              legalDocuments: repo,
              storage: storage,
              walletKey: () async => 'test',
            );
            expect(repo.canSubmit(snapshot), bypass);
            expect(terms.canSubmit(snapshot), bypass);
            await repo.recordAcceptance(surface: 'test', snapshot: snapshot);
            await terms.recordAcceptance(snapshot: snapshot);
            expect(await repo.readAcceptance(), isNull);
            expect(await terms.hasAccepted(), isFalse);
            expect(storage.values, isEmpty);
          },
        );
      }
    }

    test('compile-time bypass matches the build define', () {
      const configured = bool.fromEnvironment('BYPASS_LEGAL_DOCUMENT_GATE');
      expect(kBypassLegalDocumentGate, configured);
      final repo = LegalDocumentsRepository(
        storage: LegalFixtureStorage(populated: false),
        httpClient: MockClient((_) async => http.Response('', 404)),
      );
      addTearDown(repo.dispose);
      expect(repo.canSubmit(null), configured);
    });

    test(
      'submission records the clicked snapshot after a background change',
      () async {
        var changed = false;
        final repo = LegalDocumentsRepository(
          storage: LegalFixtureStorage(),
          httpClient: MockClient((request) async {
            final document = LegalDocumentType.values.singleWhere(
              (d) => d.url == request.url.toString(),
            );
            return _markdown(
              changed ? '# Changed terms' : legalFixtureText(document),
            );
          }),
        );
        addTearDown(repo.dispose);
        final bloc = LegalAgreementBloc(repo);
        addTearDown(bloc.close);
        final ready = bloc.stream.firstWhere(
          (s) => s.snapshot?.isAvailable ?? false,
        );
        bloc.add(const LegalAgreementOpened());
        final original = (await ready).snapshot!;
        await repo.refreshConsentDocuments();
        changed = true;
        final updated = bloc.stream.firstWhere(
          (s) => s.snapshot?.isAvailable == true && s.snapshot != original,
        );
        await repo.refreshConsentDocuments(force: true);
        await updated;
        expect(
          bloc.presentedSnapshot!.documentShas,
          isNot(original.documentShas),
        );
        bloc.add(LegalAgreementSubmitted('clicked', snapshot: original));
        await Future<void>.delayed(Duration.zero);
        expect(
          (await repo.readAcceptance())!.documentShas,
          original.documentShas,
        );
        expect(() => original.documents.clear(), throwsUnsupportedError);
        expect(() => original.documentShas.clear(), throwsUnsupportedError);
        expect(
          () => original.requiredDocuments.clear(),
          throwsUnsupportedError,
        );
      },
    );
  });
}
