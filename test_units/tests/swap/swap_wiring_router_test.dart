// The analyzer does not treat test_units as tests, so test-only members
// read as violations here.
// ignore_for_file: invalid_use_of_visible_for_testing_member

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_dex/common/screen.dart';
import 'package:web_dex/model/main_menu_value.dart';
import 'package:web_dex/router/navigators/page_content/page_content_router_delegate.dart';
import 'package:web_dex/router/navigators/page_menu/page_menu_router_delegate.dart';
import 'package:web_dex/router/state/routing_state.dart';
import 'package:web_dex/views/swap/swap_shell.dart';

/// The Swap menu entry leads to the swap surface at every width.
void main() {
  group('Swap menu routing', () {
    late MainMenuValue previousMenu;

    setUp(() => previousMenu = routingState.selectedMenu);
    tearDown(() => routingState.selectedMenu = previousMenu);

    /// What [build] shows for the Swap menu entry on a screen of [size]. The
    /// page is only built, not mounted: mounting it is the shell's own test.
    Future<Widget> swapMenuPage(
      WidgetTester tester,
      Widget Function(BuildContext context) build,
      Size size,
    ) async {
      late Widget page;
      routingState.selectedMenu = MainMenuValue.dex;
      addTearDown(resetScreenType);
      await tester.pumpWidget(
        MediaQuery(
          data: MediaQueryData(size: size),
          child: Builder(
            builder: (context) {
              updateScreenType(context);
              page = build(context);
              return const SizedBox();
            },
          ),
        ),
      );
      return page;
    }

    void expectSwapForm(Widget page) {
      expect(page, isA<SwapShell>());
      final shell = page as SwapShell;
      expect(shell.initialDestination, SwapDestination.swap);
      // Without an override the shell stands up the real swap state.
      expect(shell.destinationBuilder, isNull);
    }

    testWidgets('the content area shows the swap surface, opening on Swap', (
      tester,
    ) async {
      final page = await swapMenuPage(
        tester,
        PageContentRouterDelegate().build,
        const Size(1440, 900),
      );

      expectSwapForm(page);
    });

    testWidgets('a phone reaches the same swap surface from the menu', (
      tester,
    ) async {
      final page = await swapMenuPage(
        tester,
        PageMenuRouterDelegate().build,
        const Size(390, 844),
      );

      expect(isMobile, isTrue);
      expectSwapForm(page);
    });

    testWidgets('wider screens leave the swap surface to the content area', (
      tester,
    ) async {
      for (final size in const [Size(768, 1024), Size(1440, 900)]) {
        final menuPage = await swapMenuPage(
          tester,
          PageMenuRouterDelegate().build,
          size,
        );
        final contentPage = await swapMenuPage(
          tester,
          PageContentRouterDelegate().build,
          size,
        );

        expect(isMobile, isFalse, reason: '$size');
        expect(menuPage, isA<SizedBox>(), reason: '$size');
        expectSwapForm(contentPage);
      }
    });
  });
}
