// ignore_for_file: avoid_print

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_ui_kit/komodo_ui_kit.dart';

import 'pause.dart';
import 'widget_tester_pump_extension.dart';

extension WidgetTesterActionExtensions on WidgetTester {
  Future<void> tapAndPump(Finder finder, {int nFrames = 30}) async {
    await ensureVisible(finder);
    await tap(finder);
    await pause();
    await pumpNFrames(nFrames);
  }

  Future<void> waitForButtonEnabled(
    Finder buttonFinder, {
    Duration timeout = const Duration(seconds: 10),
    Duration interval = const Duration(milliseconds: 100),
  }) async {
    final stopwatch = Stopwatch()..start();

    while (stopwatch.elapsed < timeout) {
      // TODO: change to more generic type
      final button = widget<UiPrimaryButton>(buttonFinder);
      if (button.onPressed != null) {
        print(
          '🔍 Button became enabled after '
          '${stopwatch.elapsed.inSeconds} seconds',
        );
        return;
      }
      await pump(interval);
    }

    throw TimeoutException(
      'Button did not become enabled '
      'within ${timeout.inSeconds} seconds',
    );
  }

  /// [dragUntilVisible] that says what it was hunting for when it gives up.
  ///
  /// Its own failure is a bare `Bad state: No element` thrown by [element],
  /// which in a minified web build names neither the target nor the caller.
  Future<void> dragUntilVisibleNamed(
    Finder finder,
    Finder view,
    Offset moveStep, {
    required String description,
  }) async {
    try {
      await dragUntilVisible(finder, view, moveStep);
    } catch (error) {
      throw TestFailure(
        'Could not bring $description into view after scrolling '
        '($finder matched ${finder.evaluate().length}, '
        'scroll view matched ${view.evaluate().length}): $error',
      );
    }
  }

  Future<bool> isWidgetVisible(Finder finder) async {
    try {
      await pumpAndSettle();
      expect(finder, findsOneWidget);
      return true;
    } catch (e) {
      return false;
    }
  }
}
