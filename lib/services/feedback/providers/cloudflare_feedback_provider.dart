import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:web_dex/services/feedback/feedback_formatter.dart';
import 'package:web_dex/services/feedback/feedback_provider.dart';
import 'package:web_dex/services/logger/safe_log_exporter.dart';

class CloudflareFeedbackProvider implements FeedbackProvider {
  const CloudflareFeedbackProvider({
    required this.apiKey,
    required this.prodEndpoint,
    required this.listId,
    required this.boardId,
    http.Client? client,
  }) : _client = client;

  final String apiKey;
  final String prodEndpoint;
  final String listId;
  final String boardId;
  // Injected clients are owned by the caller; per-submission clients are closed.
  final http.Client? _client;

  static CloudflareFeedbackProvider fromEnvironment() =>
      const CloudflareFeedbackProvider(
        apiKey: String.fromEnvironment('FEEDBACK_API_KEY'),
        prodEndpoint: String.fromEnvironment('FEEDBACK_PRODUCTION_URL'),
        listId: String.fromEnvironment('TRELLO_LIST_ID'),
        boardId: String.fromEnvironment('TRELLO_BOARD_ID'),
      );

  @override
  bool get isAvailable =>
      apiKey.isNotEmpty &&
      prodEndpoint.isNotEmpty &&
      listId.isNotEmpty &&
      boardId.isNotEmpty;

  @override
  Future<void> submitFeedback({
    required String description,
    required Uint8List screenshot,
    required String type,
    required Map<String, dynamic> metadata,
    SafeLogAttachment? diagnostics,
  }) async {
    final client = _client ?? http.Client();
    try {
      final request = http.MultipartRequest('POST', Uri.parse(prodEndpoint));
      request.headers.addAll({'X-KW-KEY': apiKey, 'Accept-Charset': 'utf-8'});
      request.fields.addAll({
        'idBoard': boardId,
        'idList': listId,
        'name': 'Feedback: $type',
        'desc': FeedbackFormatter.createAgentFriendlyDescription(
          description,
          type,
          metadata,
        ),
      });
      request.files.add(
        http.MultipartFile.fromBytes(
          'img',
          screenshot,
          filename: 'screenshot.png',
          contentType: MediaType('image', 'png'),
        ),
      );
      if (diagnostics != null && !diagnostics.isEmpty) {
        request.files.add(
          http.MultipartFile.fromBytes(
            'logs',
            diagnostics.bytes,
            filename: diagnostics.fileName,
            contentType: MediaType('text', 'plain'),
          ),
        );
      }
      final response = await client.send(request);
      await response.stream.drain<void>();
      if (response.statusCode != 200) {
        throw FeedbackSubmissionException('submit', response.statusCode);
      }
    } on FeedbackSubmissionException {
      rethrow;
    } on Object {
      throw const FeedbackSubmissionException('transport', 0);
    } finally {
      if (_client == null) client.close();
    }
  }
}
