import 'package:flutter_test/flutter_test.dart';
import 'package:web_dex/mm2/mm2.dart';

void main() {
  test('Gleec activation serializes the pinned GasFree provider contract', () {
    final config = buildGleecTronGaslessProviderConfig(
      baseUrl: ' https://quicknode.gleec.com/gasfree/nile ',
      serviceProvider: ' TLntW9Z59LYY5KEi9cmwk3PKjQga828ird ',
    );

    expect(config.toJson(), {
      'base_url': 'https://quicknode.gleec.com/gasfree/nile',
      'service': 'komodo_proxy',
      'service_provider': 'TLntW9Z59LYY5KEi9cmwk3PKjQga828ird',
      'request_timeout_ms': 10000,
      'status_poll_interval_ms': 3000,
    });
  });
}
