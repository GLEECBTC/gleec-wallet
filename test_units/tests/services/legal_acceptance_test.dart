import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:web_dex/services/legal_documents/legal_acceptance.dart';
import 'package:web_dex/services/legal_documents/legal_document.dart';
import 'package:web_dex/services/legal_documents/legal_documents_repository.dart';
import 'package:web_dex/services/storage/base_storage.dart';
import 'package:web_dex/shared/constants.dart';

const _eula = '# EULA\n';
const _terms = '# Terms\n';
// Independently obtained with `git hash-object --stdin` for the fixture bytes.
const _eulaSha = '9e15fa12cac2bbb29df42fe2f278b9f557a91160';
const _termsSha = '24fe58f74d4fb2a38a4520c547a9716718eb1d6b';
// Historical bundled identities are pinned independently of the implementation.
// The legal text itself is maintained outside Git.
const _legacyDocumentHashes = {
  'legal_document_eula': 'a34507cab4663f718cd126ff32d2c045c7bad755',
  'legal_document_terms_of_service': '8922a38ea6f88795ba4f4fa747db92f6ca8c2206',
};

http.Response _remoteDocument(String markdown, {String? sha}) => http.Response(
  markdown,
  200,
  headers: {'content-type': 'text/markdown; charset=utf-8'},
);

/// A real in-memory store.
///
/// Deliberately not `MockStorage`, whose `read` returns the *key* rather than
/// null for a missing entry - which would make every "no record" case look like
/// a record.
class _MemoryStorage implements BaseStorage {
  final Map<String, dynamic> values = {};

  @override
  Future<bool> write(String key, dynamic value) async {
    values[key] = value;
    return true;
  }

  @override
  Future<dynamic> read(String key) async => values[key];

  @override
  Future<bool> delete(String key) async {
    values.remove(key);
    return true;
  }
}

/// Consent matching consumes an already-validated snapshot. Content validation
/// and identical/changed fetches use synthetic Markdown in the tests below.
class _ValidatedConsentSnapshot extends Fake implements LegalConsentSnapshot {
  _ValidatedConsentSnapshot(this.documentShas);

  @override
  final Map<String, String> documentShas;

  @override
  bool covers(Iterable<LegalDocumentType> required) =>
      required.every((document) => documentShas.containsKey(document.cacheKey));
}

void main() => testLegalAcceptance();

void testLegalAcceptance() {
  group('LegalAcceptance', () {
    test('round-trips through JSON', () {
      final original = LegalAcceptance(
        termsVersion: 3,
        acceptedAt: DateTime.utc(2026, 8, 19, 10, 30),
        surface: 'onboarding',
        documentShas: const {'legal_document_eula': 'abc123'},
      );

      final restored = LegalAcceptance.fromJson(original.toJson());

      expect(restored.termsVersion, 3);
      expect(restored.acceptedAt, DateTime.utc(2026, 8, 19, 10, 30));
      expect(restored.surface, 'onboarding');
      expect(restored.documentShas['legal_document_eula'], 'abc123');
    });

    test('a corrupt record degrades instead of throwing', () {
      final restored = LegalAcceptance.fromJson(const {
        'terms_version': 'not a number',
        'accepted_at': 'nonsense',
        'document_shas': 'not a map',
      });

      expect(restored.termsVersion, 0);
      expect(restored.surface, 'unknown');
      expect(restored.documentShas, isEmpty);
    });

    test('legacy null document hashes remain absent', () {
      final restored = LegalAcceptance.fromJson(const {
        'terms_version': kCurrentTermsVersion,
        'document_shas': {
          'legal_document_eula': null,
          'legal_document_terms_of_service': _termsSha,
        },
      });

      expect(restored.documentShas['legal_document_eula'], isNull);
      expect(
        restored.documentShas['legal_document_terms_of_service'],
        _termsSha,
      );
    });
  });

  group('LegalDocumentsRepository acceptance', () {
    late _MemoryStorage storage;
    late LegalDocumentsRepository repo;
    late http.Response remoteResponse;

    void storeLegacyAcceptance({required Map<String, dynamic> documentShas}) {
      storage.values['legal_acceptance_v1'] = {
        'terms_version': kCurrentTermsVersion,
        'accepted_at': DateTime.utc(2026).toIso8601String(),
        'surface': 'onboarding',
        'document_shas': documentShas,
      };
    }

    setUp(() {
      storage = _MemoryStorage();
      storage.values.addAll({
        LegalDocumentType.eula.cacheKey: {'markdown': _eula, 'sha': _eulaSha},
        LegalDocumentType.termsOfService.cacheKey: {
          'markdown': _terms,
          'sha': _termsSha,
        },
      });
      remoteResponse = _remoteDocument(_eula, sha: _eulaSha);
      repo = LegalDocumentsRepository(
        storage: storage,
        httpClient: MockClient((_) async => remoteResponse),
      );
    });

    tearDown(() => repo.dispose());

    test('no record means the terms have not been accepted', () async {
      expect(await repo.hasAcceptedCurrentTerms(), isFalse);
      expect(await repo.readAcceptance(), isNull);
    });

    test('recording acceptance satisfies the current terms', () async {
      await repo.recordAcceptance(surface: 'onboarding');

      expect(await repo.hasAcceptedCurrentTerms(), isTrue);
      final record = await repo.readAcceptance();
      expect(record?.surface, 'onboarding');
      expect(record?.termsVersion, kCurrentTermsVersion);
    });

    test('cached acceptance records the Git content hashes', () async {
      await repo.recordAcceptance(surface: 'onboarding');

      expect((await repo.readAcceptance())?.documentShas, {
        'legal_document_eula': _eulaSha,
        'legal_document_terms_of_service': _termsSha,
      });
    });

    for (final document in [
      LegalDocumentType.eula,
      LegalDocumentType.termsOfService,
    ]) {
      test(
        'first identical fetch of ${document.name} preserves acceptance',
        () async {
          await repo.recordAcceptance(surface: 'onboarding');
          remoteResponse = document == LegalDocumentType.eula
              ? _remoteDocument(_eula, sha: _eulaSha)
              : _remoteDocument(_terms, sha: _termsSha);

          final refreshed = await repo.refreshFromRemote(document);

          expect(refreshed, isNull);
          expect(await repo.hasAcceptedCurrentTerms(), isTrue);
          // The same persisted record also works after restarting the repository.
          final reopened = LegalDocumentsRepository(storage: storage);
          addTearDown(reopened.dispose);
          expect(await reopened.hasAcceptedCurrentTerms(), isTrue);
        },
      );

      test(
        'first changed fetch of ${document.name} invalidates acceptance',
        () async {
          await repo.recordAcceptance(surface: 'onboarding');
          remoteResponse = document == LegalDocumentType.eula
              ? _remoteDocument(
                  '# Updated EULA\n',
                  sha: 'aa654e2f168f87016796b80e8e79260ebee4995b',
                )
              : _remoteDocument(
                  '# Updated Terms\n',
                  sha: '6a942b5d8a46cfaee401e2d3b81feb6407ed826c',
                );

          await repo.refreshFromRemote(document);

          expect(await repo.hasAcceptedCurrentTerms(), isFalse);
          await repo.recordAcceptance(surface: 'wallet-creation');
          expect(await repo.hasAcceptedCurrentTerms(), isTrue);
        },
      );
    }

    test(
      'offline acceptance survives recovery with identical documents',
      () async {
        remoteResponse = http.Response('Unavailable', 503);
        expect(await repo.refreshFromRemote(LegalDocumentType.eula), isNull);
        await repo.recordAcceptance(surface: 'onboarding');
        expect(await repo.hasAcceptedCurrentTerms(), isTrue);

        remoteResponse = _remoteDocument(_eula, sha: _eulaSha);
        await repo.refreshFromRemote(LegalDocumentType.eula);

        expect(await repo.hasAcceptedCurrentTerms(), isTrue);
      },
    );

    test('legacy bundled records match historical document hashes', () async {
      storeLegacyAcceptance(
        documentShas: {
          'legal_document_eula': 'bundled',
          'legal_document_terms_of_service': 'bundled',
        },
      );
      expect(
        await repo.hasAcceptedCurrentTerms(
          snapshot: _ValidatedConsentSnapshot(_legacyDocumentHashes),
        ),
        isTrue,
      );
      expect((await repo.readAcceptance())?.documentShas, {
        'legal_document_eula': 'bundled',
        'legal_document_terms_of_service': 'bundled',
      });
    });

    for (final document in walletConsentDocuments) {
      test(
        'legacy bundled records reject updated ${document.name} hash',
        () async {
          storeLegacyAcceptance(
            documentShas: {
              'legal_document_eula': 'bundled',
              'legal_document_terms_of_service': 'bundled',
            },
          );
          expect(
            await repo.hasAcceptedCurrentTerms(
              snapshot: _ValidatedConsentSnapshot({
                ..._legacyDocumentHashes,
                document.cacheKey: document == LegalDocumentType.eula
                    ? _eulaSha
                    : _termsSha,
              }),
            ),
            isFalse,
          );
        },
      );
    }

    test('legacy bundled records reject changed fetched content', () async {
      storeLegacyAcceptance(
        documentShas: {
          'legal_document_eula': 'bundled',
          'legal_document_terms_of_service': 'bundled',
        },
      );
      remoteResponse = _remoteDocument(
        '# Updated EULA\n',
        sha: 'aa654e2f168f87016796b80e8e79260ebee4995b',
      );

      await repo.refreshFromRemote(LegalDocumentType.eula);

      expect(await repo.hasAcceptedCurrentTerms(), isFalse);
    });

    for (final hashes in <Map<String, dynamic>>[
      {},
      {'legal_document_eula': null},
    ]) {
      test('legacy missing hashes retain version fallback: $hashes', () async {
        storeLegacyAcceptance(documentShas: hashes);
        remoteResponse = _remoteDocument(
          '# Updated EULA\n',
          sha: 'aa654e2f168f87016796b80e8e79260ebee4995b',
        );
        await repo.refreshFromRemote(LegalDocumentType.eula);

        expect(await repo.hasAcceptedCurrentTerms(), isTrue);
        final stored = storage.values['legal_acceptance_v1'] as Map;
        stored['terms_version'] = kCurrentTermsVersion - 1;
        expect(await repo.hasAcceptedCurrentTerms(), isFalse);
      });
    }

    test(
      'legacy fetched hashes match the bundled Git content hashes',
      () async {
        storeLegacyAcceptance(
          documentShas: {
            'legal_document_eula': _eulaSha,
            'legal_document_terms_of_service': _termsSha,
          },
        );

        expect(await repo.hasAcceptedCurrentTerms(), isTrue);
      },
    );

    test(
      'an identical cache without a remote SHA remains the same document',
      () async {
        remoteResponse = _remoteDocument(_eula);
        await repo.refreshFromRemote(LegalDocumentType.eula);
        await repo.recordAcceptance(surface: 'onboarding');

        remoteResponse = _remoteDocument(_eula, sha: _eulaSha);
        await repo.refreshFromRemote(LegalDocumentType.eula);

        expect(await repo.hasAcceptedCurrentTerms(), isTrue);
      },
    );

    test(
      'changed cached text without a remote SHA invalidates acceptance',
      () async {
        remoteResponse = _remoteDocument(_eula);
        await repo.refreshFromRemote(LegalDocumentType.eula);
        await repo.recordAcceptance(surface: 'onboarding');

        remoteResponse = _remoteDocument('# Updated EULA\n');
        await repo.refreshFromRemote(LegalDocumentType.eula);

        expect(await repo.hasAcceptedCurrentTerms(), isFalse);
      },
    );

    test(
      'missing cached text cannot satisfy consent even with prior acceptance',
      () async {
        await repo.refreshFromRemote(LegalDocumentType.eula);
        await repo.recordAcceptance(surface: 'onboarding');

        await storage.delete(LegalDocumentType.eula.cacheKey);

        expect(await repo.hasAcceptedCurrentTerms(), isFalse);
      },
    );

    test('no bundled fallback after cache removal', () async {
      remoteResponse = _remoteDocument(
        '# Updated EULA\n',
        sha: 'aa654e2f168f87016796b80e8e79260ebee4995b',
      );
      await repo.refreshFromRemote(LegalDocumentType.eula);
      await repo.recordAcceptance(surface: 'onboarding');

      await storage.delete(LegalDocumentType.eula.cacheKey);

      expect(await repo.hasAcceptedCurrentTerms(), isFalse);
    });

    test('Unicode content hashes use UTF-8 byte length', () async {
      storage.values[LegalDocumentType.eula.cacheKey] = {
        'markdown': '# EULA – café ☕\n',
      };
      repo.dispose();
      repo = LegalDocumentsRepository(storage: storage);

      await repo.recordAcceptance(surface: 'onboarding');

      expect(
        (await repo.readAcceptance())?.documentShas['legal_document_eula'],
        '177d4ea5d1aec0d0f0b0537d99df98d0e8ccbcb6',
      );
    });

    test(
      'changed cached text invalidates a newly recorded acceptance',
      () async {
        await repo.recordAcceptance(surface: 'onboarding');
        repo.dispose();
        storage.values[LegalDocumentType.eula.cacheKey] = {
          'markdown': '# Updated EULA\n',
        };
        repo = LegalDocumentsRepository(storage: storage);

        expect(await repo.hasAcceptedCurrentTerms(), isFalse);
      },
    );

    test(
      'documents outside the consent notice do not invalidate acceptance',
      () async {
        await repo.recordAcceptance(surface: 'onboarding');
        remoteResponse = _remoteDocument(
          '# Privacy\n',
          sha: 'f78bbfafb197b2327b3be207a8e3c2391b2589cc',
        );

        await repo.refreshFromRemote(LegalDocumentType.privacyNotice);

        expect(await repo.hasAcceptedCurrentTerms(), isTrue);
      },
    );

    test('a record from an older terms version no longer counts', () async {
      storage.values['legal_acceptance_v1'] = LegalAcceptance(
        termsVersion: kCurrentTermsVersion - 1,
        acceptedAt: DateTime.utc(2020),
        surface: 'onboarding',
        documentShas: const {},
      ).toJson();

      expect(await repo.hasAcceptedCurrentTerms(), isFalse);
    });

    test('a changed document SHA invalidates the acceptance', () async {
      // What the user accepted...
      storage.values['legal_acceptance_v1'] = LegalAcceptance(
        termsVersion: kCurrentTermsVersion,
        acceptedAt: DateTime.utc(2026),
        surface: 'onboarding',
        documentShas: const {
          'legal_document_eula': 'sha-at-acceptance',
          'legal_document_terms_of_service': 'bundled',
        },
      ).toJson();
      // ...and what the EULA says now.
      storage.values['legal_document_eula'] = {
        'markdown': '# Updated EULA',
        'sha': 'sha-after-update',
      };

      expect(await repo.hasAcceptedCurrentTerms(), isFalse);
    });

    test('an unchanged cached document keeps the acceptance valid', () async {
      storage.values['legal_document_eula'] = {
        'markdown': '# EULA',
        'sha': legalContentSha('# EULA'),
      };
      await repo.recordAcceptance(surface: 'onboarding');

      expect(await repo.hasAcceptedCurrentTerms(), isTrue);
    });

    test('a corrupt stored record reads as not accepted', () async {
      storage.values['legal_acceptance_v1'] = 'not a map';

      expect(await repo.readAcceptance(), isNull);
      expect(await repo.hasAcceptedCurrentTerms(), isFalse);
    });
  });

  test('an empty device cannot record missing documents', () async {
    final repository = LegalDocumentsRepository(storage: _MemoryStorage());
    addTearDown(repository.dispose);
    await repository.recordAcceptance(surface: 'onboarding');
    expect(await repository.readAcceptance(), isNull);
    expect(await repository.hasAcceptedCurrentTerms(), isFalse);
  });
}
