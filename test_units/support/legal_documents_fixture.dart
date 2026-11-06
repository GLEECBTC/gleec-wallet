import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:web_dex/services/legal_documents/legal_documents_repository.dart';
import 'package:web_dex/services/storage/base_storage.dart';
import 'package:web_dex/services/legal_documents/legal_document.dart';

String legalFixtureText(LegalDocumentType type) => '# ${type.name}\n';

class LegalFixtureStorage implements BaseStorage {
  LegalFixtureStorage({bool populated = true}) {
    if (populated) {
      for (final type in LegalDocumentType.values) {
        final text = legalFixtureText(type);
        values[type.cacheKey] = {
          'markdown': text,
          'sha': legalContentSha(text),
        };
      }
    }
  }
  final values = <String, dynamic>{};
  @override
  Future<dynamic> read(String key) async => values[key];
  @override
  Future<bool> write(String key, dynamic value) async {
    values[key] = value;
    return true;
  }

  @override
  Future<bool> delete(String key) async {
    values.remove(key);
    return true;
  }
}

LegalConsentSnapshot legalFixtureSnapshot({
  List<LegalDocumentType> documents = swapConsentDocuments,
}) => LegalConsentSnapshot.fromDocuments({
  for (final type in documents)
    type: LegalDocumentContent(
      markdown: legalFixtureText(type),
      source: LegalDocumentSource.cachedRemote,
    ),
}, requiredDocuments: documents);

LegalDocumentsRepository legalFixtureRepository() => LegalDocumentsRepository(
  storage: LegalFixtureStorage(),
  httpClient: MockClient(
    (request) async => http.Response(
      legalFixtureText(
        LegalDocumentType.values.firstWhere((d) => d.url == '${request.url}'),
      ),
      200,
      headers: {'content-type': 'text/markdown; charset=utf-8'},
    ),
  ),
);
