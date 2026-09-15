import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Verifies the copy action's real engine acknowledgement, independently of UI
/// feedback. Clipboard messages go directly to the platform delegate so a test
/// binding's default clipboard handler cannot fabricate success.
Future<void> verifyPlatformClipboardWrite(
  WidgetTester tester, {
  required String expectedText,
  required Future<void> Function() copyAction,
  Duration timeout = const Duration(seconds: 10),
}) async {
  final messenger = tester.binding.defaultBinaryMessenger;
  final previousObserver = messenger.allMessagesHandler;
  final completed = Completer<({Object? error, StackTrace? stackTrace})>();
  var requestObserved = false;

  messenger.allMessagesHandler = (channel, handler, message) {
    if (channel == SystemChannels.platform.name && message != null) {
      final call = SystemChannels.platform.codec.decodeMethodCall(message);
      if (call.method == 'Clipboard.setData') {
        requestObserved = true;
        final response = messenger.delegate.send(channel, message);
        unawaited(() async {
          try {
            final reply = await response;
            if (reply == null) {
              throw MissingPluginException(
                'The platform did not handle Clipboard.setData',
              );
            }
            // Preserve real platform failures; never synthesize a successful
            // envelope or convert an error into a clipboard acknowledgement.
            SystemChannels.platform.codec.decodeEnvelope(reply);
            final arguments = call.arguments;
            if (arguments is! Map || arguments['text'] != expectedText) {
              throw TestFailure(
                'The copy action sent a different receive address',
              );
            }
            if (!completed.isCompleted) {
              completed.complete((error: null, stackTrace: null));
            }
          } catch (error, stackTrace) {
            if (!completed.isCompleted) {
              completed.complete((error: error, stackTrace: stackTrace));
            }
          }
        }());
        return response;
      }
    }
    if (previousObserver != null) {
      return previousObserver(channel, handler, message);
    }
    return handler != null
        ? handler(message)
        : messenger.delegate.send(channel, message);
  };

  try {
    await copyAction();
    final deadline = DateTime.now().add(timeout);
    while (!completed.isCompleted && DateTime.now().isBefore(deadline)) {
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    if (!completed.isCompleted) {
      throw TimeoutException(
        requestObserved
            ? 'The browser did not acknowledge Clipboard.setData'
            : 'The copy action did not request Clipboard.setData',
        timeout,
      );
    }
    final result = await completed.future;
    if (result.error != null) {
      Error.throwWithStackTrace(result.error!, result.stackTrace!);
    }
  } finally {
    messenger.allMessagesHandler = previousObserver;
  }
}
