import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:feedback/feedback.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:web_dex/services/feedback/feedback_metadata.dart';
import 'package:web_dex/services/feedback/feedback_provider.dart';
import 'package:web_dex/services/feedback/feedback_service.dart';
import 'package:web_dex/services/feedback/providers/cloudflare_feedback_provider.dart';
import 'package:web_dex/services/feedback/providers/trello_feedback_provider.dart';
import 'package:web_dex/services/logger/safe_log_exporter.dart';

import '../logger/safe_log_exporter_test.dart'
    show FixtureLogSource, diagnosticFixture;

class _CaptureClient extends http.BaseClient {
  final bodies = <String>[];
  final requests = <http.BaseRequest>[];
  int statusCode = 200;
  String responseBody = '{"id":"synthetic-card"}';
  Object? failure;
  bool closed = false;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (failure case final Object error) throw error;
    requests.add(request);
    bodies.add(utf8.decode(await request.finalize().toBytes()));
    return http.StreamedResponse(
      Stream.value(utf8.encode(responseBody)),
      statusCode,
    );
  }

  @override
  void close() {
    closed = true;
  }
}

class _CaptureProvider implements FeedbackProvider {
  int submissions = 0;
  String? description;
  Uint8List? screenshot;
  Map<String, dynamic>? metadata;
  SafeLogAttachment? diagnostics;
  @override
  bool get isAvailable => true;
  @override
  Future<void> submitFeedback({
    required String description,
    required Uint8List screenshot,
    required String type,
    required Map<String, dynamic> metadata,
    SafeLogAttachment? diagnostics,
  }) async {
    submissions++;
    this.description = description;
    this.screenshot = screenshot;
    this.metadata = metadata;
    this.diagnostics = diagnostics;
  }
}

void main() {
  group('feedback diagnostic privacy', () {
    test(
      'both providers transmit only the same supplied sanitized attachment',
      () async {
        final diagnostics = await SafeLogExporter(
          source: FixtureLogSource([
            diagnosticFixture('Connected'),
            diagnosticFixture('private_key=SENTINEL'),
          ]),
        ).export();
        final cloudClient = _CaptureClient();
        final trelloClient = _CaptureClient();
        final providers = <FeedbackProvider>[
          CloudflareFeedbackProvider(
            apiKey: 'synthetic-key',
            prodEndpoint: 'https://audit.invalid',
            listId: 'list',
            boardId: 'board',
            client: cloudClient,
          ),
          TrelloFeedbackProvider(
            apiKey: 'synthetic-key',
            token: 'synthetic-token',
            listId: 'list',
            boardId: 'board',
            client: trelloClient,
          ),
        ];
        for (final provider in providers) {
          await provider.submitFeedback(
            description: 'User context',
            screenshot: Uint8List.fromList([1, 2, 3]),
            type: 'Bug',
            metadata: {
              'version': '0.9.7',
              'wallet': {'seed': 'SENTINEL'},
              'baseUrl': 'https://example.invalid/?secret=SENTINEL',
            },
            diagnostics: diagnostics,
          );
        }
        expect(cloudClient.requests, hasLength(1));
        expect(trelloClient.requests, hasLength(3));
        final safeText = utf8.decode(diagnostics.bytes);
        expect(cloudClient.bodies.single, contains(safeText));
        expect(trelloClient.bodies.last, contains(safeText));
        expect(cloudClient.bodies.single, contains('filename="logs.txt"'));
        expect(trelloClient.bodies.last, contains('filename="logs.txt"'));
        expect(
          [...cloudClient.bodies, ...trelloClient.bodies].join(),
          isNot(contains('SENTINEL')),
        );
        expect(cloudClient.closed, isFalse); // Caller owns injected transports.
        expect(trelloClient.closed, isFalse);
      },
    );

    test(
      'provider without diagnostics sends text/screenshot without opening logs',
      () async {
        final client = _CaptureClient();
        final provider = CloudflareFeedbackProvider(
          apiKey: 'synthetic-key',
          prodEndpoint: 'https://audit.invalid',
          listId: 'list',
          boardId: 'board',
          client: client,
        );
        await provider.submitFeedback(
          description: 'User context',
          screenshot: Uint8List(0),
          type: 'Bug',
          metadata: {},
        );
        expect(client.bodies.single, contains('User context'));
        expect(client.bodies.single, contains('filename="screenshot.png"'));
        expect(client.bodies.single, isNot(contains('filename="logs.txt"')));
      },
    );

    test(
      'automatic wallet/URL metadata is removed and explicit contact retained',
      () async {
        final provider = _CaptureProvider();
        var exports = 0;
        final service = FeedbackService(
          provider: provider,
          loadMetadata: () async => {
            'version': '0.9.7',
            'commitHash': 'eae57cd734f89270a36bcdf7c604b8cbe49869de',
            'coinsCurrentCommit': 'deadbee',
            'coinsLatestCommit': 'private_key=SENTINEL',
            'walletIsHd': true,
            'wallet': {
              'metadata': {'seed': 'SENTINEL'},
            },
            'baseUrl': 'https://example.invalid/?token=SENTINEL',
            'contactDetails': 'SENTINEL',
            'arbitrary': 'SENTINEL',
          },
          loadDiagnostics: () async {
            exports++;
            return SafeLogAttachment.empty();
          },
        );
        final image = Uint8List.fromList([1, 2, 3]);
        expect(
          await service.handleFeedback(
            UserFeedback(
              text: 'User context',
              screenshot: image,
              extra: {
                'feedback_type': 'bugReport',
                'contact_method': 'email',
                'contact_details': 'test@example.invalid',
              },
            ),
          ),
          isTrue,
        );
        expect(provider.description, 'User context');
        expect(provider.screenshot, same(image));
        expect(provider.metadata, {
          'version': '0.9.7',
          'commitHash': 'eae57cd734f89270a36bcdf7c604b8cbe49869de',
          'coinsCurrentCommit': 'deadbee',
          'walletIsHd': true,
          'contactMethod': 'email',
          'contactDetails': 'test@example.invalid',
        });
        expect(exports, 1);
      },
    );

    test(
      'failed metadata or log readiness does not prevent feedback',
      () async {
        final provider = _CaptureProvider();
        final service = FeedbackService(
          provider: provider,
          loadMetadata: () async => throw StateError('SENTINEL'),
          loadDiagnostics: () async => throw StateError('SENTINEL'),
        );
        expect(
          await service.handleFeedback(
            UserFeedback(
              text: 'User context',
              screenshot: Uint8List(0),
              extra: {'feedback_type': 'bugReport'},
            ),
          ),
          isTrue,
        );
        expect(provider.submissions, 1);
        expect(provider.metadata, isEmpty);
        expect(provider.diagnostics, isNull);
      },
    );

    test(
      'stalled optional diagnostics time out without blocking submission',
      () async {
        final provider = _CaptureProvider();
        final pending = Completer<SafeLogAttachment>();
        final service = FeedbackService(
          provider: provider,
          loadMetadata: () async => {},
          loadDiagnostics: () => pending.future,
          diagnosticsTimeout: const Duration(milliseconds: 1),
        );
        expect(
          await service.handleFeedback(
            UserFeedback(
              text: 'User context',
              screenshot: Uint8List(0),
              extra: {'feedback_type': 'bugReport'},
            ),
          ),
          isTrue,
        );
        expect(provider.diagnostics, isNull);
        pending.complete(SafeLogAttachment.empty());
      },
    );

    test('provider exceptions never include server bodies', () async {
      final client = _CaptureClient()
        ..statusCode = 500
        ..responseBody = 'private_key=SENTINEL';
      final provider = CloudflareFeedbackProvider(
        apiKey: 'synthetic-key',
        prodEndpoint: 'https://audit.invalid',
        listId: 'list',
        boardId: 'board',
        client: client,
      );
      await expectLater(
        provider.submitFeedback(
          description: 'User context',
          screenshot: Uint8List(0),
          type: 'Bug',
          metadata: {},
        ),
        throwsA(
          isA<FeedbackSubmissionException>().having(
            (error) => error.toString(),
            'safe error',
            isNot(contains('SENTINEL')),
          ),
        ),
      );
    });

    test('transport failures never expose raw exception details', () async {
      final client = _CaptureClient()
        ..failure = StateError('private_key=SENTINEL');
      final providers = <FeedbackProvider>[
        CloudflareFeedbackProvider(
          apiKey: 'synthetic-key',
          prodEndpoint: 'https://audit.invalid',
          listId: 'list',
          boardId: 'board',
          client: client,
        ),
        TrelloFeedbackProvider(
          apiKey: 'synthetic-key',
          token: 'synthetic-token',
          listId: 'list',
          boardId: 'board',
          client: client,
        ),
      ];
      for (final provider in providers) {
        await expectLater(
          provider.submitFeedback(
            description: 'User context',
            screenshot: Uint8List(0),
            type: 'Bug',
            metadata: {},
          ),
          throwsA(
            isA<FeedbackSubmissionException>().having(
              (error) => error.toString(),
              'safe error',
              isNot(contains('SENTINEL')),
            ),
          ),
        );
      }
    });

    test('contact metadata is bounded, explicit, and control-free', () {
      expect(
        submittedFeedbackContact({
          'contact_method': 'unknown',
          'contact_details': 'value',
        }),
        isEmpty,
      );
      expect(
        submittedFeedbackContact({
          'contact_method': 'email',
          'contact_details': 'x' * 101,
        }),
        isEmpty,
      );
      expect(
        submittedFeedbackContact({
          'contact_method': 'email',
          'contact_details': 'hello\nSENTINEL',
        }),
        isEmpty,
      );
      expect(
        sanitizeFeedbackMetadata({
          'contactMethod': 'email',
          'contactDetails': 'SENTINEL',
        }),
        isEmpty,
      );
    });
  });
}
