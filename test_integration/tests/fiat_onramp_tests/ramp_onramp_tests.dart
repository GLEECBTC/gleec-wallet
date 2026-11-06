import 'package:integration_test/integration_test.dart';

import 'fiat_onramp_tests.dart';

// Explicit recovery check; excluded from the default run while Ramp is deferred.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  fiatOnRampWidgetTests(provider: 'Ramp');
}
