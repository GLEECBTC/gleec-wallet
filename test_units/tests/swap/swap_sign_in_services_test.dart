import 'package:flutter_test/flutter_test.dart';
import 'package:web_dex/shared/swap/swap_services.dart';

import 'swap_src_sdk_fakes.dart';

/// Covers how [SwapServices] carries the swap form across a sign-in the form
/// starts: to the form rebuilt for the wallet, and nowhere else.
void main() {
  const form = (pay: 'ETH', receive: 'USDC-ERC20', amount: '250', fiat: true);

  late SwapServices services;
  late List<SwapIntent> announced;

  setUp(() {
    services = servicesOf(SrcSdk());
    announced = [];
    services.intents.listen(announced.add);
  });

  tearDown(() => services.dispose());

  test('knows a sign-in the form started, until it ends', () {
    expect(services.signInFromSwap, isFalse);

    services.beginSignIn(form);
    expect(services.signInFromSwap, isTrue);

    services.endSignIn(signedIn: true);
    expect(services.signInFromSwap, isFalse);
  });

  test('keeps the form for the next one, without announcing it', () async {
    services.beginSignIn(form);
    await pumpEventQueue();
    // The signed-out form still on screen listens, and must not take it.
    expect(announced, isEmpty);

    services.endSignIn(signedIn: true);
    expect(services.takePendingIntent(), form);
    expect(services.takePendingIntent(), isNull);
  });

  test('leaves nothing behind once the new form has taken it', () {
    services.beginSignIn(form);
    expect(services.takePendingIntent(), form);

    services.endSignIn(signedIn: true);
    expect(services.takePendingIntent(), isNull);
  });

  test('drops the form when no wallet signed in', () {
    services.beginSignIn(form);
    services.endSignIn(signedIn: false);

    expect(services.signInFromSwap, isFalse);
    expect(services.takePendingIntent(), isNull);
  });

  test("dropping it keeps another screen's later request", () {
    const coinPage = (pay: 'BTC', receive: null, amount: null, fiat: false);
    services
      ..beginSignIn(form)
      ..requestIntent(coinPage)
      ..endSignIn(signedIn: false);

    expect(services.takePendingIntent(), coinPage);
  });
}
