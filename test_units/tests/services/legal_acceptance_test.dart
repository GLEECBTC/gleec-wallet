import 'package:flutter_test/flutter_test.dart';
import 'package:web_dex/services/legal_documents/legal_acceptance.dart';
import 'package:web_dex/services/legal_documents/legal_documents_repository.dart';
import 'package:web_dex/services/storage/base_storage.dart';
import 'package:web_dex/shared/constants.dart';

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
  });

  group('LegalDocumentsRepository acceptance', () {
    late _MemoryStorage storage;
    late LegalDocumentsRepository repo;

    setUp(() {
      storage = _MemoryStorage();
      repo = LegalDocumentsRepository(storage: storage);
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
        'sha': 'stable-sha',
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
}
