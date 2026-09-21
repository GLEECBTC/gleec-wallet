import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:web_dex/bloc/legal_agreement/legal_agreement_bloc.dart';
import 'package:web_dex/services/legal_documents/legal_document.dart';
import 'package:web_dex/services/legal_documents/legal_documents_repository.dart';
import 'package:web_dex/services/storage/base_storage.dart';

class _Storage implements BaseStorage {
  final data = <String, dynamic>{};
  bool failWrites = false;
  @override
  Future<dynamic> read(String key) async => data[key];
  @override
  Future<bool> write(String key, dynamic value) async {
    if (failWrites) return false;
    data[key] = value;
    return true;
  }

  @override
  Future<bool> delete(String key) async {
    data.remove(key);
    return true;
  }
}

class _Assets extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async =>
      ByteData.sublistView(utf8.encode('# Bundled $key'));
}

http.Response _document(String text) => http.Response(
  jsonEncode({'content': base64Encode(utf8.encode(text))}),
  200,
);

void main() {
  group('Background legal refresh', () {
    test(
      'a refused cache write retains content and uses the failure retry',
      () async {
        var now = DateTime.utc(2026, 9, 15);
        var requests = 0;
        final storage = _Storage()..failWrites = true;
        final repo = LegalDocumentsRepository(
          storage: storage,
          assetBundle: _Assets(),
          clock: () => now,
          httpClient: MockClient((_) async {
            requests++;
            return _document('# Updated');
          }),
        );
        addTearDown(repo.dispose);
        final before = await repo.loadConsentSnapshot();
        await repo.refreshConsentDocuments();
        expect(
          (await repo.loadConsentSnapshot()).documentShas,
          before.documentShas,
        );
        expect(requests, 2);
        await repo.refreshConsentDocuments();
        expect(requests, 2);
        storage.failWrites = false;
        now = now.add(const Duration(minutes: 1));
        await repo.refreshConsentDocuments();
        expect(requests, 4);
        expect(
          (await repo.loadConsentSnapshot()).documentShas,
          isNot(before.documentShas),
        );
      },
    );
    test(
      'coalesces startup/form/resume and throttles a successful check',
      () async {
        var now = DateTime.utc(2026, 9, 15);
        var calls = 0;
        final pending = Completer<void>();
        final repo = LegalDocumentsRepository(
          storage: _Storage(),
          assetBundle: _Assets(),
          clock: () => now,
          httpClient: MockClient((request) async {
            calls++;
            await pending.future;
            return _document('# Remote ${request.url.path}');
          }),
        );
        addTearDown(repo.dispose);
        final refreshes = List.generate(
          3,
          (_) => repo.refreshConsentDocuments(),
        );
        await Future<void>.delayed(Duration.zero);
        expect(calls, 2);
        pending.complete();
        await Future.wait(refreshes);
        await repo.refreshConsentDocuments();
        expect(calls, 2);
        now = now.add(const Duration(minutes: 15));
        await repo.refreshConsentDocuments();
        expect(calls, 4);
      },
    );

    test(
      'offline fallback retries after one minute without losing text',
      () async {
        var now = DateTime.utc(2026, 9, 15);
        var calls = 0;
        final repo = LegalDocumentsRepository(
          storage: _Storage(),
          assetBundle: _Assets(),
          clock: () => now,
          httpClient: MockClient((_) async {
            calls++;
            return http.Response('unavailable', 503);
          }),
        );
        addTearDown(repo.dispose);
        final before = await repo.loadConsentSnapshot();
        await repo.refreshConsentDocuments();
        await repo.refreshConsentDocuments();
        expect(calls, 2);
        expect(
          (await repo.loadConsentSnapshot()).documentShas,
          before.documentShas,
        );
        now = now.add(const Duration(minutes: 1));
        await repo.refreshConsentDocuments();
        expect(calls, 4);
      },
    );

    test(
      'an open form discovers updated terms without opening a viewer',
      () async {
        final pending = Completer<void>();
        final repo = LegalDocumentsRepository(
          storage: _Storage(),
          assetBundle: _Assets(),
          httpClient: MockClient((request) async {
            await pending.future;
            return _document('# Changed ${request.url.path}');
          }),
        );
        addTearDown(repo.dispose);
        await repo.recordAcceptance(surface: 'old-form');
        final bloc = LegalAgreementBloc(repo)
          ..add(const LegalAgreementOpened());
        addTearDown(bloc.close);
        await bloc.stream.firstWhere(
          (state) => state == LegalAgreementStatus.current,
        );
        final updated = bloc.stream.firstWhere(
          (state) => state == LegalAgreementStatus.updated,
        );
        pending.complete();
        await updated.timeout(const Duration(seconds: 2));
        expect(
          bloc.presentedSnapshot!.documents[LegalDocumentType.eula]!.markdown,
          startsWith('# Changed'),
        );
      },
    );

    test(
      'submission retains presented text while a remote refresh completes',
      () async {
        final pending = Completer<void>();
        final repo = LegalDocumentsRepository(
          storage: _Storage(),
          assetBundle: _Assets(),
          httpClient: MockClient((request) async {
            await pending.future;
            return _document('# Changed ${request.url.path}');
          }),
        );
        addTearDown(repo.dispose);
        final before = await repo.loadConsentSnapshot();
        final bloc = LegalAgreementBloc(repo)
          ..add(const LegalAgreementOpened());
        addTearDown(bloc.close);
        await Future<void>.delayed(Duration.zero);
        bloc.add(const LegalAgreementSubmitted('wallet-login'));
        await Future<void>.delayed(Duration.zero);
        pending.complete();
        await repo.refreshConsentDocuments();
        expect(
          (await repo.readAcceptance())!.documentShas,
          before.documentShas,
        );
        expect(await repo.hasAcceptedCurrentTerms(), isFalse);
      },
    );

    test('disposed repositories ignore a late successful response', () async {
      final response = Completer<http.Response>();
      final storage = _Storage();
      final repo = LegalDocumentsRepository(
        storage: storage,
        assetBundle: _Assets(),
        httpClient: MockClient((_) => response.future),
      );
      final refresh = repo.refreshConsentDocuments();
      await Future<void>.delayed(Duration.zero);
      repo.dispose();
      response.complete(_document('# Too late'));
      await refresh;
      expect(storage.data, isEmpty);
    });
  });
}
