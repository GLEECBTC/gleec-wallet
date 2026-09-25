import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_ui_kit/komodo_ui_kit.dart';

/// `AutoScrollText` waits before its first scroll, and again between passes.
/// Those waits used to be plain `Future.delayed`s, which cannot be cancelled,
/// so a widget disposed of mid-wait left the delay running. The test binding
/// fails on a timer that outlives the tree, so every widget test rendering one
/// - a DEX coin row, a transaction row, a withdrawal amount - failed on
/// `!timersPending` instead of on whatever it was written to assert, and the
/// suites worked around it by unmounting and pumping the delay away.
///
/// Both tests below assert by finishing: that same pending-timer check at
/// teardown is what catches a wait outliving its widget again.
void main() {
  testWidgets('disposing during the wait before the first scroll leaves no '
      'timer behind', (tester) async {
    await tester.pumpWidget(_host());

    // Part-way into the initial pause, so the wait is still outstanding.
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('disposing between scroll passes leaves no timer behind', (
    tester,
  ) async {
    await tester.pumpWidget(_host());

    // Past the initial pause. The text is far wider than its column, so the
    // animation really did start and the pause under test is a real one.
    await tester.pump(const Duration(seconds: 3));
    expect(
      find.byKey(const ValueKey('AutoScrollText-Container')),
      findsOneWidget,
    );

    // Past the outbound pass, into the pause before it scrolls back.
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

Widget _host() => const MaterialApp(
  home: Scaffold(
    body: Center(
      child: SizedBox(
        width: 40,
        child: AutoScrollText(text: 'A coin name far too long for its column'),
      ),
    ),
  ),
);
