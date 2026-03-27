import 'dart:async';
import 'package:test/test.dart';
import 'package:web_dex/bloc/system_health/providers/ntp_time_provider.dart';

void testNtpTimeProvider() {
  group('NtpTimeProvider', () {
    test('throws TimeoutException if all servers fail', () async {
      final provider = NtpTimeProvider(
        ntpServers: ['bad.ntp.server'],
        lookupTimeout: const Duration(milliseconds: 10),
        maxRetries: 1,
      );
      // This will likely fail due to bad server
      expect(
        () => provider.getCurrentUtcTime(),
        throwsA(isA<TimeoutException>()),
      );
    });
    // Note: A true success test would require a real NTP server and is best as
    // an integration test.
  });
}
