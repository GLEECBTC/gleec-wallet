import 'dart:io';
import 'dart:ui' show BoxHeightStyle, SemanticsAction, Tristate;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// The app's font under a name of its own, so loading it changes no other
/// test. The test font's square glyphs wrap and cut text that fits on a
/// device.
const swapFont = 'SwapTestManrope';

Future<void>? _fontLoaded;

/// Registers [swapFont], once per test run.
Future<void> loadSwapFont() => _fontLoaded ??= _loadFont();

Future<void> _loadFont() async {
  final loader = FontLoader(swapFont);
  for (final weight in const [
    'Regular',
    'Medium',
    'SemiBold',
    'Bold',
    'ExtraBold',
  ]) {
    final bytes = File('assets/fonts/Manrope-$weight.ttf').readAsBytesSync();
    loader.addFont(Future.value(ByteData.sublistView(bytes)));
  }
  await loader.load();
}

/// Every control on screen is at least 48 dp, labelled, and pressable by a
/// screen reader, and no word is split across lines. With [largeText], no
/// text may be cut short either.
Future<void> expectSwapAccessible(
  WidgetTester tester, {
  bool largeText = false,
}) async {
  await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
  await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
  // The guidelines skip a button without a tap action, which is exactly the
  // one a screen reader can focus but not press.
  expect(
    find.semantics.byPredicate((node) {
      final data = node.getSemanticsData();
      return data.flagsCollection.isButton &&
          data.flagsCollection.isEnabled != Tristate.isFalse &&
          !data.hasAction(SemanticsAction.tap);
    }, describeMatch: (_) => 'buttons a screen reader cannot press'),
    findsNothing,
  );
  expect(_brokenText(largeText: largeText), isEmpty);
}

/// Text cut short by an ellipsis, and plain words wrapped mid-word.
List<String> _brokenText({required bool largeText}) {
  final word = RegExp(r"^[A-Za-z’']+[.,:;!?)]*$");
  final broken = <String>[];
  for (final element in find.byType(RichText).evaluate()) {
    final paragraph = element.renderObject;
    if (paragraph is! RenderParagraph || !paragraph.hasSize) continue;
    final text = paragraph.text.toPlainText();
    if (largeText && paragraph.didExceedMaxLines) broken.add('cut: $text');
    for (final token in RegExp(r'\S+').allMatches(text)) {
      if (!word.hasMatch(token[0]!)) continue;
      final lines = paragraph
          .getBoxesForSelection(
            TextSelection(baseOffset: token.start, extentOffset: token.end),
            boxHeightStyle: BoxHeightStyle.max,
          )
          .map((box) => box.top.round())
          .toSet();
      if (lines.length > 1) broken.add('split: ${token[0]} in "$text"');
    }
  }
  return broken;
}
