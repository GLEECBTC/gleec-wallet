import 'dart:async';
import 'dart:convert';

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
    http.Client? httpClient,
    DateTime Function()? clock,
    this.bypassGate = kBypassLegalDocumentGate,
  }) : _storage = storage ?? getStorage(),
       _httpClient = httpClient ?? http.Client(),
       _clock = clock ?? DateTime.now;

  static const _acceptanceKey = 'legal_acceptance_v1';
  final bool bypassGate;
  final BaseStorage _storage;
  final http.Client _httpClient;
  final DateTime Function() _clock;
  final _log = Logger('LegalDocumentsRepository');
  final _changes = StreamController<void>.broadcast();
  final _refreshes = <LegalDocumentType, Future<LegalDocumentContent?>>{};
  final _nextRefresh = <LegalDocumentType, DateTime>{};
  final _missing = <LegalDocumentType, LegalDocumentStatus>{};
  bool _disposed = false;

  Stream<void> get changes => _changes.stream;
  bool canSubmit(LegalConsentSnapshot? snapshot) =>
      bypassGate || (snapshot?.covers(walletConsentDocuments) ?? false);

  Future<LegalConsentSnapshot> loadConsentSnapshot() =>
      loadSnapshot(walletConsentDocuments);

  Future<LegalConsentSnapshot> loadSnapshot(
    List<LegalDocumentType> documents,
  ) async {
    final contents = await Future.wait(documents.map(loadPreferredContent));
    return LegalConsentSnapshot.fromDocuments({
      for (var i = 0; i < documents.length; i++) documents[i]: contents[i],
    }, requiredDocuments: documents);
  }

  /// Does not wait for the network: forms can immediately use a valid cache.
  Future<LegalDocumentContent> loadPreferredContent(
    LegalDocumentType document,
  ) async =>
      await _readCachedContent(document) ??
      LegalDocumentContent.unavailable(
        status: _missing[document] ?? LegalDocumentStatus.unavailable,
      );

  Future<void> refreshConsentDocuments({bool force = false}) =>
      refreshDocuments(walletConsentDocuments, force: force);

  Future<void> refreshDocuments(
    List<LegalDocumentType> documents, {
    bool force = false,
  }) async {
    await Future.wait(documents.map((d) => refreshFromRemote(d, force: force)));
  }

  Future<LegalDocumentContent?> refreshFromRemote(
    LegalDocumentType document, {
    bool force = true,
  }) {
    if (_disposed) return Future.value();
    final pending = _refreshes[document];
    if (pending != null) return pending;
    final next = _nextRefresh[document];
    if (!force && next != null && _clock().isBefore(next)) {
      return Future.value();
    }
    final refresh = _refreshFromRemote(document).whenComplete(() {
      _refreshes.remove(document);
    });
    _refreshes[document] = refresh;
    return refresh;
  }

  Future<LegalDocumentContent?> _refreshFromRemote(
    LegalDocumentType document,
  ) async {
    _nextRefresh[document] = _clock().add(const Duration(minutes: 1));
    try {
      final cached = await _readCachedContent(document);
      final response = await _httpClient
          .get(
            Uri.parse(document.url),
            headers: {
              'Accept': 'text/markdown, text/plain',
              if (cached?.etag case final etag?) 'If-None-Match': etag,
            },
          )
          .timeout(const Duration(seconds: 10));
      if (_disposed) return null;
      if (response.statusCode == 304 && cached != null) {
        _nextRefresh[document] = _clock().add(const Duration(minutes: 15));
        return null;
      }
      if (response.statusCode != 200) {
        throw FormatException('HTTP ${response.statusCode}');
      }
      final mediaType = response.headers['content-type']
          ?.split(';')
          .first
          .trim()
          .toLowerCase();
      if (mediaType != 'text/markdown' && mediaType != 'text/plain') {
        throw const FormatException('Expected Markdown or plain text');
      }
      final markdown = utf8.decode(response.bodyBytes);
      if (!isLegalMarkdown(markdown)) {
        throw const FormatException('Empty or invalid legal document');
      }
      if (markdown.contains(legalPlaceholderMarker)) {
        _setMissing(document, LegalDocumentStatus.placeholder);
        return null;
      }
      final sha = legalContentSha(markdown);
      final fetchedAt = _clock();
      final etag = response.headers['etag'];
      final persisted = await _storage.write(document.cacheKey, {
        'markdown': markdown,
        'sha': sha,
        'fetchedAt': fetchedAt.toIso8601String(),
        'etag': etag,
        'url': document.url,
      });
      if (!persisted) throw StateError('Legal document cache write failed');
      if (_disposed) return null;
      _missing.remove(document);
      _nextRefresh[document] = _clock().add(const Duration(minutes: 15));
      if (cached?.markdown == markdown) return null;
      _changes.add(null);
      return LegalDocumentContent(
        markdown: markdown,
        source: LegalDocumentSource.remote,
        sha: sha,
        fetchedAt: fetchedAt,
        etag: etag,
      );
    } catch (error) {
      _log.warning('Could not refresh ${document.cacheKey}: $error');
      _setMissing(document, LegalDocumentStatus.unavailable);
      return null;
    }
  }

  void _setMissing(LegalDocumentType document, LegalDocumentStatus status) {
    if (_disposed || _missing[document] == status) return;
    _missing[document] = status;
    _changes.add(null);
  }

  Future<LegalDocumentContent?> _readCachedContent(
    LegalDocumentType document,
  ) async {
    try {
      final raw = await _storage.read(document.cacheKey);
      if (raw is! Map) return null;
      final markdown = raw['markdown'];
      if (markdown is! String ||
          !isLegalMarkdown(markdown) ||
          markdown.contains(legalPlaceholderMarker)) {
        return null;
      }
      final sha = legalContentSha(markdown);
      // Old GitHub cache entries can omit the SHA, but a mismatch is corrupt.
      if (raw['sha'] != null && raw['sha'] != sha) return null;
      return LegalDocumentContent(
        markdown: markdown,
        source: LegalDocumentSource.cachedRemote,
        sha: sha,
        fetchedAt: DateTime.tryParse('${raw['fetchedAt']}'),
        // Validators belong to the new URL, never to the old GitHub endpoint.
        etag: raw['url'] == document.url && raw['etag'] is String
            ? raw['etag'] as String
            : null,
      );
    } catch (error) {
      _log.warning('Could not read ${document.cacheKey}: $error');
      return null;
    }
  }

  Future<LegalAcceptance?> readAcceptance() async {
    try {
      final raw = await _storage.read(_acceptanceKey);
      return raw is Map
          ? LegalAcceptance.fromJson(Map<String, dynamic>.from(raw))
          : null;
    } catch (error) {
      _log.warning('Could not read legal acceptance: $error');
      return null;
    }
  }

  /// A testing bypass must never turn missing text into an acceptance record.
  Future<void> recordAcceptance({
    required String surface,
    LegalConsentSnapshot? snapshot,
  }) async {
    try {
      final presented = snapshot ?? await loadConsentSnapshot();
      if (!presented.covers(walletConsentDocuments)) return;
      await _storage.write(
        _acceptanceKey,
        LegalAcceptance(
          termsVersion: kCurrentTermsVersion,
          acceptedAt: _clock(),
          surface: surface,
          documentShas: {
            for (final d in walletConsentDocuments)
              d.cacheKey: presented.documentShas[d.cacheKey]!,
          },
        ).toJson(),
      );
    } catch (error) {
      _log.warning('Could not record legal acceptance: $error');
    }
  }

  Future<bool> hasAcceptedCurrentTerms({LegalConsentSnapshot? snapshot}) async {
    final presented = snapshot ?? await loadConsentSnapshot();
    if (!presented.covers(walletConsentDocuments)) return false;
    final acceptance = await readAcceptance();
    if (acceptance == null || acceptance.termsVersion < kCurrentTermsVersion) {
      return false;
    }
    for (final document in walletConsentDocuments) {
      var accepted = acceptance.documentShas[document.cacheKey];
      if (accepted == null) continue; // Legacy version-only acceptance.
      if (accepted == 'bundled') accepted = document.legacyBundledSha;
      if (accepted != presented.documentShas[document.cacheKey]) return false;
    }
    return true;
  }

  void dispose() {
    _disposed = true;
    unawaited(_changes.close());
    _httpClient.close();
  }
}
