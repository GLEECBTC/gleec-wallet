import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:web_dex/services/feedback/feedback_formatter.dart';
import 'package:web_dex/services/feedback/feedback_provider.dart';
import 'package:web_dex/services/logger/safe_log_exporter.dart';

class TrelloFeedbackProvider implements FeedbackProvider {
  const TrelloFeedbackProvider({
    required this.apiKey,
    required this.token,
    required this.boardId,
    required this.listId,
    http.Client? client,
  }) : _client = client;

  final String apiKey;
  final String token;
  final String boardId;
  final String listId;
  final http.Client? _client;

  static bool hasEnvironmentVariables() =>
      const String.fromEnvironment('TRELLO_API_KEY').isNotEmpty &&
      const String.fromEnvironment('TRELLO_TOKEN').isNotEmpty &&
      const String.fromEnvironment('TRELLO_BOARD_ID').isNotEmpty &&
      const String.fromEnvironment('TRELLO_LIST_ID').isNotEmpty;

  static TrelloFeedbackProvider? fromEnvironment() => !hasEnvironmentVariables()
      ? null
      : const TrelloFeedbackProvider(
          apiKey: String.fromEnvironment('TRELLO_API_KEY'),
          token: String.fromEnvironment('TRELLO_TOKEN'),
          boardId: String.fromEnvironment('TRELLO_BOARD_ID'),
          listId: String.fromEnvironment('TRELLO_LIST_ID'),
        );

  @override
  bool get isAvailable =>
      apiKey.isNotEmpty &&
      token.isNotEmpty &&
      boardId.isNotEmpty &&
      listId.isNotEmpty;

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
      final cardResponse = await client.post(
        Uri.parse('https://api.trello.com/1/cards'),
        headers: {'Content-Type': 'application/json; charset=utf-8'},
        body: jsonEncode({
          'idList': listId,
          'key': apiKey,
          'token': token,
          'name': 'Feedback: $type',
          'desc': FeedbackFormatter.createAgentFriendlyDescription(
            description,
            type,
            metadata,
          ),
        }),
      );
      if (cardResponse.statusCode != 200) {
        throw FeedbackSubmissionException(
          'create card',
          cardResponse.statusCode,
        );
      }
      final Object? card;
      try {
        card = jsonDecode(cardResponse.body);
      } on FormatException {
        throw const FeedbackSubmissionException('decode card', 200);
      }
      final cardId = card is Map<String, dynamic> ? card['id'] : null;
      if (cardId is! String || !RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(cardId)) {
        throw const FeedbackSubmissionException('decode card', 200);
      }
      final endpoint = Uri.https(
        'api.trello.com',
        '/1/cards/$cardId/attachments',
      );
      await _attach(
        client,
        endpoint,
        screenshot,
        'screenshot.png',
        MediaType('image', 'png'),
      );
      if (diagnostics != null && !diagnostics.isEmpty) {
        try {
          await _attach(
            client,
            endpoint,
            diagnostics.bytes,
            diagnostics.fileName,
            MediaType('text', 'plain'),
          );
        } on Object {
          // The card and screenshot have already succeeded; diagnostics are optional.
        }
      }
    } on FeedbackSubmissionException {
      rethrow;
    } on Object {
      throw const FeedbackSubmissionException('transport', 0);
    } finally {
      if (_client == null) client.close();
    }
  }

  Future<void> _attach(
    http.Client client,
    Uri endpoint,
    Uint8List bytes,
    String filename,
    MediaType contentType,
  ) async {
    final request = http.MultipartRequest('POST', endpoint);
    request.fields.addAll({'key': apiKey, 'token': token});
    request.files.add(
      http.MultipartFile.fromBytes(
        'file',
        bytes,
        filename: filename,
        contentType: contentType,
      ),
    );
    final response = await client.send(request);
    await response.stream.drain<void>();
    if (response.statusCode != 200) {
      throw FeedbackSubmissionException('attach file', response.statusCode);
    }
  }
}
