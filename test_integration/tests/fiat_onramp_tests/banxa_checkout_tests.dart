import 'package:integration_test/integration_test.dart';

import 'fiat_onramp_tests.dart';

// Explicit supervised check: creates a provider order and opens hosted checkout.
// It does not enter payment details or complete a purchase.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  fiatOnRampWidgetTests(submitOrder: true);
}
