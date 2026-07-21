import 'package:flutter_test/flutter_test.dart';
import 'package:web_dex/features/unified_swap/infrastructure/unified_swap_config.dart';

void main() {
  group('UnifiedSwapConfig', () {
    test('defaults every new-trading switch off', () {
      const config = UnifiedSwapConfig();

      expect(config.canQuote, isFalse);
      expect(config.canExecute, isFalse);
    });

    test('requires quote when init is requested', () {
      final config = _resolve(initEnabled: true);

      expect(config.canQuote, isFalse);
      expect(config.canExecute, isFalse);
      expect(
        config.configurationFailures,
        contains(UnifiedSwapConfigurationFailure.initRequiresQuote),
      );
    });

    test('accepts the exact production proxy base', () {
      final config = _resolve(
        quoteEnabled: true,
        initEnabled: true,
        kdfLifiEnabled: true,
        kdfLifiCaseAEnabled: true,
        transport: 'gleec_proxy',
        proxyUrl: 'https://proxy.gleec.example/lifi/v1',
        production: true,
      );

      expect(config.configurationFailures, isEmpty);
      expect(config.canQuote, isTrue);
      expect(config.canExecute, isTrue);
      expect(config.canStartKdfExternalExecution, isTrue);
    });

    test('rejects non-HTTPS and inexact production proxy URLs', () {
      for (final url in [
        'http://proxy.gleec.example/lifi/v1',
        'https://proxy.gleec.example/lifi/v1/',
        'https://proxy.gleec.example/lifi/v1?credential=forbidden',
        'https://proxy.gleec.example/lifi/v1?',
        'https://proxy.gleec.example/lifi/v1#',
        ' https://proxy.gleec.example/lifi/v1',
      ]) {
        final config = _resolve(
          quoteEnabled: true,
          kdfLifiEnabled: true,
          kdfLifiCaseAEnabled: true,
          transport: 'gleec_proxy',
          proxyUrl: url,
          production: true,
        );

        expect(config.canQuote, isFalse, reason: url);
        expect(
          config.configurationFailures,
          contains(UnifiedSwapConfigurationFailure.proxyUrlInvalid),
          reason: url,
        );
      }
    });

    test(
      'allows direct transport only behind the explicit non-prod override',
      () {
        final blocked = _resolve(
          quoteEnabled: true,
          kdfLifiEnabled: true,
          kdfLifiCaseAEnabled: true,
          transport: 'direct',
        );
        final allowed = _resolve(
          quoteEnabled: true,
          kdfLifiEnabled: true,
          kdfLifiCaseAEnabled: true,
          transport: 'direct',
          allowDirectLifiNonProduction: true,
        );
        final production = _resolve(
          quoteEnabled: true,
          kdfLifiEnabled: true,
          kdfLifiCaseAEnabled: true,
          transport: 'direct',
          allowDirectLifiNonProduction: true,
          production: true,
        );

        expect(blocked.canQuote, isFalse);
        expect(allowed.canQuote, isTrue);
        expect(allowed.canStartKdfExternalExecution, isTrue);
        expect(production.canQuote, isFalse);
        expect(production.canStartKdfExternalExecution, isFalse);
      },
    );

    test('does not start KDF Li.Fi when its independent gate is off', () {
      final config = _resolve(
        transport: 'gleec_proxy',
        proxyUrl: 'https://proxy.gleec.example/lifi/v1',
      );

      expect(config.canStartKdfExternalExecution, isFalse);
    });
  });
}

UnifiedSwapConfig _resolve({
  bool quoteEnabled = false,
  bool initEnabled = false,
  bool kdfLifiEnabled = false,
  bool kdfLifiCaseAEnabled = false,
  String transport = '',
  String proxyUrl = '',
  bool allowDirectLifiNonProduction = false,
  bool production = false,
}) => UnifiedSwapConfig.resolve(
  quoteEnabled: quoteEnabled,
  initEnabled: initEnabled,
  kdfLifiEnabled: kdfLifiEnabled,
  kdfLifiCaseAEnabled: kdfLifiCaseAEnabled,
  transport: transport,
  proxyUrl: proxyUrl,
  allowDirectLifiNonProduction: allowDirectLifiNonProduction,
  production: production,
);
