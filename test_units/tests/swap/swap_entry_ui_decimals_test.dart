// The analyzer does not treat test_units as tests, so Bloc.emit's
// @visibleForTesting reads as a violation here.
// ignore_for_file: invalid_use_of_visible_for_testing_member

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_event.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_state.dart';
import 'package:web_dex/views/swap/entry/swap_entry_view.dart';

import 'swap_entry_ui_fakes.dart';
import 'swap_test_fixtures.dart';

/// Covers the decimal places the amount field takes, and what typing past
/// them does: the digits at the end make room rather than the key being
/// refused.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpSwapUi();

  late RecordingSwapBloc swap;

  setUp(() => swap = RecordingSwapBloc());

  tearDown(() => swap.close());

  final field = find.byKey(const Key('swap-amount'));

  Future<void> pump(WidgetTester tester, UnifiedSwapState state) async {
    swap.emit(state);
    await pumpSwapUi(
      tester,
      const SwapEntryView(),
      bloc: swap,
      services: FakeSwapServices(),
    );
  }

  TextEditingValue value(WidgetTester tester) =>
      tester.widget<TextField>(field).controller!.value;

  /// What a keyboard sends: the whole text after a key, and the cursor.
  Future<void> send(WidgetTester tester, String text, int cursor) async {
    tester.testTextInput.updateEditingValue(
      TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: cursor),
      ),
    );
    await tester.pump();
  }

  // Unpriced, so each needs the issue the bloc would hold the form on, or
  // the action keeps moving and the pump never settles.
  UnifiedSwapState form({
    AssetId? pay,
    String input = '',
    SwapFormIssue issue = SwapFormIssue.amountMissing,
  }) => swapBaseForm(pay: pay, input: input).copyWith(issue: issue);

  final dollars = form().copyWith(amountMode: SwapAmountMode.fiat);

  group('in dollars', () {
    testWidgets('places past two are dropped', (tester) async {
      await pump(tester, dollars);
      await tester.enterText(field, '12.345');

      expect(swap.events, [const UnifiedSwapAmountChanged('12.34')]);
      expect(value(tester).text, '12.34');
    });

    testWidgets('a digit typed into full places pushes the last one out', (
      tester,
    ) async {
      await pump(tester, dollars);
      await tester.enterText(field, '12.34');
      await send(tester, '12.534', 4);

      expect(value(tester).text, '12.53');
      expect(value(tester).selection, const TextSelection.collapsed(offset: 4));
      expect(swap.events.last, const UnifiedSwapAmountChanged('12.53'));
    });

    testWidgets('a digit typed after full places changes nothing', (
      tester,
    ) async {
      await pump(tester, dollars);
      await tester.enterText(field, '12.34');
      await send(tester, '12.345', 6);

      expect(value(tester).text, '12.34');
      expect(value(tester).selection, const TextSelection.collapsed(offset: 5));
      expect(swap.events, [const UnifiedSwapAmountChanged('12.34')]);
    });

    testWidgets('pasted digits push out as many, and so does a point', (
      tester,
    ) async {
      await pump(tester, dollars);
      await tester.enterText(field, '12.34');
      await send(tester, '12.67834', 6);

      expect(value(tester).text, '12.67');
      expect(value(tester).selection, const TextSelection.collapsed(offset: 5));

      await tester.enterText(field, '12345');
      await send(tester, '1.2345', 2);

      expect(value(tester).text, '1.23');
    });

    testWidgets('digits typed into the whole number are all kept', (
      tester,
    ) async {
      await pump(tester, dollars);
      await tester.enterText(field, '12.34');
      await send(tester, '912.34', 1);

      expect(value(tester).text, '912.34');
    });
  });

  group('in tokens', () {
    testWidgets('the field takes as many places as the asset has', (
      tester,
    ) async {
      await pump(tester, form(pay: btc));
      await tester.enterText(field, '0.123456789');
      expect(value(tester).text, '0.12345678');

      await send(tester, '0.912345678', 3);
      expect(value(tester).text, '0.91234567');
      expect(swap.events.last, const UnifiedSwapAmountChanged('0.91234567'));
    });

    testWidgets('the field takes 18 for an asset with none on record', (
      tester,
    ) async {
      final unknown = assetOf(
        'KMD',
        subClass: CoinSubClass.smartChain,
        chainId: 0,
        decimals: null,
      );
      await pump(tester, form(pay: unknown));
      await tester.enterText(field, '0.1234567890123456789');

      expect(value(tester).text, '0.123456789012345678');
    });

    testWidgets('the field takes no point for an asset with no places', (
      tester,
    ) async {
      await pump(tester, form(pay: assetOf('WHOLE', decimals: 0)));
      await tester.enterText(field, '12');
      await tester.enterText(field, '12.');
      await tester.enterText(field, '12.5');

      expect(value(tester).text, '12');
      expect(swap.events, [const UnifiedSwapAmountChanged('12')]);
    });

    testWidgets('an amount set with more places loses only what an edit adds', (
      tester,
    ) async {
      // As a link can set it: ten places, where BTC has eight.
      await pump(
        tester,
        form(
          pay: btc,
          input: '1.1234567890',
          issue: SwapFormIssue.tooManyDecimals,
        ),
      );
      await tester.showKeyboard(field);
      await send(tester, '1.51234567890', 3);
      expect(value(tester).text, '1.5123456789');

      // Shortening is taken even while the amount is still too long.
      await send(tester, '1.512345678', 11);
      expect(value(tester).text, '1.512345678');
      expect(swap.events.last, const UnifiedSwapAmountChanged('1.512345678'));
    });
  });
}
