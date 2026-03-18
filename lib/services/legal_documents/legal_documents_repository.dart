import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';
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
