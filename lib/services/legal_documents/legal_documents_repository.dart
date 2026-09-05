import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';
import 'package:web_dex/shared/constants.dart';
import 'package:web_dex/services/legal_documents/legal_acceptance.dart';
import 'package:web_dex/services/legal_documents/legal_document.dart';
import 'package:web_dex/services/storage/base_storage.dart';
import 'package:web_dex/services/storage/get_storage.dart';

class LegalDocumentsRepository {
  LegalDocumentsRepository({
    BaseStorage? storage,
    AssetBundle? assetBundle,
    http.Client? httpClient,
  }) : _storage = storage ?? getStorage(),
       _assetBundle = assetBundle ?? rootBundle,
       _httpClient = httpClient ?? http.Client();

  static const String _acceptanceKey = 'legal_acceptance_v1';

  /// The two documents the consent line actually names.
  static const List<LegalDocumentType> _consentDocuments = [
    LegalDocumentType.eula,
    LegalDocumentType.termsOfService,
  ];

  static const String _githubOwner = 'GLEECBTC';
  static const String _githubRepo = 'gleec-wallet';
  static const String _githubBranch = 'main';

  final BaseStorage _storage;
  final AssetBundle _assetBundle;
  final http.Client _httpClient;
  final Logger _log = Logger('LegalDocumentsRepository');

  Future<LegalDocumentContent> loadPreferredContent(
    LegalDocumentType document,
  ) async {
    final cached = await _readCachedContent(document);
    if (cached != null) {
      return cached;
    }

    final bundled = await _assetBundle.loadString(document.assetPath);
    return LegalDocumentContent(
      markdown: bundled,
      source: LegalDocumentSource.bundledAsset,
    );
  }

  Future<LegalDocumentContent?> refreshFromRemote(
    LegalDocumentType document,
  ) async {
    final cached = await _readCachedContent(document);
    final uri = Uri.https(
      'api.github.com',
      '/repos/$_githubOwner/$_githubRepo/contents/${document.githubPath}',
      <String, String>{'ref': _githubBranch},
    );

    try {
      final response = await _httpClient
          .get(
            uri,
            headers: const <String, String>{
              'Accept': 'application/vnd.github+json',
              'User-Agent': 'GleecWallet',
              'X-GitHub-Api-Version': '2022-11-28',
            },
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        _log.warning(
          'Failed to refresh ${document.cacheKey}: '
          'GitHub returned ${response.statusCode}',
        );
        return null;
      }

      final payload = jsonDecode(response.body) as Map<String, dynamic>;
      final encodedContent = payload['content'] as String?;
      final sha = payload['sha'] as String?;
      if (encodedContent == null || encodedContent.trim().isEmpty) {
        _log.warning(
          'GitHub response missing content for ${document.cacheKey}',
        );
        return null;
      }

      final markdown = utf8.decode(
        base64Decode(encodedContent.replaceAll('\n', '')),
      );
      if (markdown.trim().isEmpty) {
        _log.warning('Decoded content empty for ${document.cacheKey}');
        return null;
      }

      final fetchedAt = DateTime.now();
      final hasChanged =
          cached?.markdown != markdown || (sha != null && cached?.sha != sha);

      if (hasChanged) {
        await _storage.write(document.cacheKey, <String, dynamic>{
          'markdown': markdown,
          'sha': sha,
          'fetchedAt': fetchedAt.toIso8601String(),
        });
      }

      if (!hasChanged) {
        return null;
      }

      return LegalDocumentContent(
        markdown: markdown,
        source: LegalDocumentSource.remote,
        sha: sha,
        fetchedAt: fetchedAt,
      );
    } on TimeoutException catch (error) {
      _log.warning('Timed out refreshing ${document.cacheKey}: $error');
      return null;
    } on FormatException catch (error) {
      _log.warning('Invalid GitHub payload for ${document.cacheKey}: $error');
      return null;
    } catch (error, stackTrace) {
      _log.warning(
        'Unexpected error refreshing ${document.cacheKey}',
        error,
        stackTrace,
      );
      return null;
    }
  }

  /// The stored acceptance record, or null if the user has never accepted.
  Future<LegalAcceptance?> readAcceptance() async {
    try {
      final raw = await _storage.read(_acceptanceKey);
      if (raw is! Map) return null;
      return LegalAcceptance.fromJson(Map<String, dynamic>.from(raw));
    } catch (error) {
      _log.warning('Could not read the legal acceptance record: $error');
      return null;
    }
  }

  /// Records that the user accepted the current documents on [surface].
  ///
  /// Fire-and-forget by design: consent is given by the act of continuing, so
  /// a storage failure must never block the user from reaching their wallet.
  Future<void> recordAcceptance({required String surface}) async {
    try {
      await _storage.write(
        _acceptanceKey,
        LegalAcceptance(
          termsVersion: kCurrentTermsVersion,
          acceptedAt: DateTime.now(),
          surface: surface,
          documentShas: await _currentDocumentShas(),
        ).toJson(),
      );
    } catch (error) {
      _log.warning('Could not record the legal acceptance: $error');
    }
  }

  /// Whether the stored acceptance still covers what the user would agree to
  /// today. False when there is no record, when [kCurrentTermsVersion] has been
  /// bumped, or when either document's content has since changed.
  Future<bool> hasAcceptedCurrentTerms() async {
    final acceptance = await readAcceptance();
    if (acceptance == null) return false;
    if (acceptance.termsVersion < kCurrentTermsVersion) return false;

    final current = await _currentDocumentShas();
    for (final entry in current.entries) {
      final accepted = acceptance.documentShas[entry.key];
      // A document with no SHA on either side is the bundled asset, which
      // cannot have drifted - only a real remote change invalidates consent.
      if (accepted != null && accepted != entry.value) return false;
    }
    return true;
  }

  Future<Map<String, String>> _currentDocumentShas() async {
    final shas = <String, String>{};
    for (final document in _consentDocuments) {
      final cached = await _readCachedContent(document);
      shas[document.cacheKey] = cached?.sha ?? 'bundled';
    }
    return shas;
  }

  Future<LegalDocumentContent?> _readCachedContent(
    LegalDocumentType document,
  ) async {
    final rawValue = await _storage.read(document.cacheKey);
    if (rawValue is! Map) {
      return null;
    }

    final markdown = rawValue['markdown'];
    if (markdown is! String || markdown.trim().isEmpty) {
      return null;
    }

    final sha = rawValue['sha'];
    final fetchedAtRaw = rawValue['fetchedAt'];
    return LegalDocumentContent(
      markdown: markdown,
      source: LegalDocumentSource.cachedRemote,
      sha: sha is String ? sha : null,
      fetchedAt: fetchedAtRaw is String
          ? DateTime.tryParse(fetchedAtRaw)
          : null,
    );
  }

  void dispose() {
    _httpClient.close();
  }
}
