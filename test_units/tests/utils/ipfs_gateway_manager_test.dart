import 'package:flutter/foundation.dart';
import 'package:test/test.dart';
import 'package:web_dex/shared/constants/ipfs_constants.dart';
import 'package:web_dex/shared/utils/ipfs_gateway_manager.dart';

void main() {
  testIpfsGatewayManager();
}

void testIpfsGatewayManager() {
  group('IpfsGatewayManager', () {
    late IpfsGatewayManager manager;

    setUp(() {
      manager = IpfsGatewayManager();
    });

    group('Constructor and Configuration', () {
      test('should use default gateways when none provided', () {
        final manager = IpfsGatewayManager();

        expect(manager.gateways, isNotEmpty);
        // Should use web-optimized or standard based on platform
        if (kIsWeb) {
          expect(
            manager.gateways,
            equals(IpfsConstants.defaultWebOptimizedGateways),
          );
        } else {
          expect(
            manager.gateways,
            equals(IpfsConstants.defaultStandardGateways),
          );
        }
      });

      test('should use custom gateways when provided', () {
        final customWebGateways = ['https://custom-web.gateway.com/ipfs/'];
        final customStandardGateways = [
          'https://custom-standard.gateway.com/ipfs/',
        ];

        final manager = IpfsGatewayManager(
          webOptimizedGateways: customWebGateways,
          standardGateways: customStandardGateways,
        );

        if (kIsWeb) {
          expect(manager.gateways, equals(customWebGateways));
        } else {
          expect(manager.gateways, equals(customStandardGateways));
        }
      });

      test('should use custom failure cooldown when provided', () async {
        const customCooldown = Duration(minutes: 10);
        final manager = IpfsGatewayManager(failureCooldown: customCooldown);

        // Test cooldown by marking a URL as failed and checking timing
        const testUrl = 'https://test.gateway.com/ipfs/QmTest';
        await manager.logGatewayAttempt(testUrl, false);

        expect(await manager.shouldSkipUrl(testUrl), isTrue);
      });
    });

    group('IPFS URL Detection', () {
      test('should detect ipfs:// protocol URLs', () {
        expect(
          IpfsGatewayManager.isIpfsUrl(
            'ipfs://QmYjtig7VJQ6XsnUjqqJvj7QaMcCAwtrgNdahSiFofrE7o',
          ),
          isTrue,
        );
        expect(IpfsGatewayManager.isIpfsUrl('ipfs://QmTest/image.png'), isTrue);
      });

      test('should detect gateway format URLs', () {
        expect(
          IpfsGatewayManager.isIpfsUrl(
            'https://ipfs.io/ipfs/QmYjtig7VJQ6XsnUjqqJvj7QaMcCAwtrgNdahSiFofrE7o',
          ),
          isTrue,
        );
        expect(
          IpfsGatewayManager.isIpfsUrl(
            'https://gateway.pinata.cloud/ipfs/QmTest/metadata.json',
          ),
          isTrue,
        );
        expect(
          IpfsGatewayManager.isIpfsUrl('https://dweb.link/ipfs/QmTest'),
          isTrue,
        );
      });

      test('should detect subdomain format URLs', () {
        expect(
          IpfsGatewayManager.isIpfsUrl(
            'https://QmYjtig7VJQ6XsnUjqqJvj7QaMcCAwtrgNdahSiFofrE7o.ipfs.dweb.link',
          ),
          isTrue,
        );
        expect(
          IpfsGatewayManager.isIpfsUrl(
            'https://QmTest.ipfs.gateway.com/image.png',
          ),
          isTrue,
        );
      });

      test('should detect URLs with /ipfs/ path anywhere', () {
        expect(
          IpfsGatewayManager.isIpfsUrl('https://some.domain.com/ipfs/QmTest'),
          isTrue,
        );
        expect(
          IpfsGatewayManager.isIpfsUrl(
            'https://custom-gateway.com/ipfs/QmTest/file.json',
          ),
          isTrue,
        );
      });

      test('should not detect regular HTTP URLs as IPFS', () {
        expect(
          IpfsGatewayManager.isIpfsUrl('https://example.com/image.png'),
          isFalse,
        );
        expect(
          IpfsGatewayManager.isIpfsUrl('https://api.example.com/data'),
          isFalse,
        );
        expect(
          IpfsGatewayManager.isIpfsUrl('http://localhost:3000/test'),
          isFalse,
        );
      });

      test('should handle null and empty URLs', () {
        expect(IpfsGatewayManager.isIpfsUrl(null), isFalse);
        expect(IpfsGatewayManager.isIpfsUrl(''), isFalse);
        expect(IpfsGatewayManager.isIpfsUrl('   '), isFalse);
      });
    });

    group('Content ID Extraction', () {
      test('should extract CID from ipfs:// protocol', () {
        final urls = manager.getGatewayUrls(
          'ipfs://QmYjtig7VJQ6XsnUjqqJvj7QaMcCAwtrgNdahSiFofrE7o',
        );
        expect(urls.isNotEmpty, isTrue);
        expect(
          urls.first.contains('QmYjtig7VJQ6XsnUjqqJvj7QaMcCAwtrgNdahSiFofrE7o'),
          isTrue,
        );
      });

      test('should extract CID and path from ipfs:// protocol', () {
        final urls = manager.getGatewayUrls('ipfs://QmTest/metadata.json');
        expect(urls.isNotEmpty, isTrue);
        expect(urls.first.contains('QmTest/metadata.json'), isTrue);
      });

      test('should extract CID from gateway format', () {
        final urls = manager.getGatewayUrls(
          'https://ipfs.io/ipfs/QmYjtig7VJQ6XsnUjqqJvj7QaMcCAwtrgNdahSiFofrE7o',
        );
        expect(urls.isNotEmpty, isTrue);
        expect(
          urls.first.contains('QmYjtig7VJQ6XsnUjqqJvj7QaMcCAwtrgNdahSiFofrE7o'),
          isTrue,
        );
      });

      test('should extract CID and path from gateway format', () {
        final urls = manager.getGatewayUrls(
          'https://gateway.pinata.cloud/ipfs/QmTest/image.png',
        );
        expect(urls.isNotEmpty, isTrue);
        expect(urls.first.contains('QmTest/image.png'), isTrue);
      });

      test('should extract CID from subdomain format', () {
        final urls = manager.getGatewayUrls(
          'https://QmYjtig7VJQ6XsnUjqqJvj7QaMcCAwtrgNdahSiFofrE7o.ipfs.dweb.link',
        );
        expect(urls.isNotEmpty, isTrue);
        expect(
          urls.first.contains('QmYjtig7VJQ6XsnUjqqJvj7QaMcCAwtrgNdahSiFofrE7o'),
          isTrue,
        );
      });

      test('should extract CID and path from subdomain format', () {
        final urls = manager.getGatewayUrls(
          'https://QmTest.ipfs.gateway.com/path/to/file.json',
        );
        expect(urls.isNotEmpty, isTrue);
        expect(urls.first.contains('QmTest/path/to/file.json'), isTrue);
      });

      test('should handle URLs with /ipfs/ path', () {
        final urls = manager.getGatewayUrls(
          'https://custom.gateway.com/ipfs/QmTest/data',
        );
        expect(urls.isNotEmpty, isTrue);
        expect(urls.first.contains('QmTest/data'), isTrue);
      });

      test('should extract CID from case-insensitive URLs', () {
        // Test case-insensitive protocol
        final urls1 = manager.getGatewayUrls('IPFS://QmTest');
        expect(urls1.isNotEmpty, isTrue);
        expect(urls1.first.contains('QmTest'), isTrue);

        // Test case-insensitive /ipfs/ path
        final urls2 = manager.getGatewayUrls('https://gateway.com/IPFS/QmTest');
        expect(urls2.isNotEmpty, isTrue);
        expect(urls2.first.contains('QmTest'), isTrue);
      });
    });

    group('Gateway URL Generation', () {
      test('should generate multiple gateway URLs for IPFS content', () {
        final urls = manager.getGatewayUrls('ipfs://QmTest');

        expect(urls.length, equals(manager.gateways.length));
        for (int i = 0; i < urls.length; i++) {
          expect(urls[i], equals('${manager.gateways[i]}QmTest'));
        }
      });

      test('should return original URL for non-IPFS URLs', () {
        const originalUrl = 'https://example.com/image.png';
        final urls = manager.getGatewayUrls(originalUrl);

        expect(urls.length, equals(1));
        expect(urls.first, equals(originalUrl));
      });

      test('should return empty list for null/empty URLs', () {
        expect(manager.getGatewayUrls(null), isEmpty);
        expect(manager.getGatewayUrls(''), isEmpty);
      });

      test('should get primary gateway URL', () {
        final primaryUrl = manager.getPrimaryGatewayUrl('ipfs://QmTest');
        expect(primaryUrl, equals('${manager.gateways.first}QmTest'));
      });

      test('should return null for primary URL when input is invalid', () {
        expect(manager.getPrimaryGatewayUrl(null), isNull);
        expect(manager.getPrimaryGatewayUrl(''), isNull);
      });
    });

    group('URL Normalization', () {
      test(
        'should normalize different IPFS URL formats to preferred gateway',
        () {
          const cid = 'QmYjtig7VJQ6XsnUjqqJvj7QaMcCAwtrgNdahSiFofrE7o';
          final expectedUrl = '${manager.gateways.first}$cid';

          expect(manager.normalizeIpfsUrl('ipfs://$cid'), equals(expectedUrl));
          expect(
            manager.normalizeIpfsUrl('https://ipfs.io/ipfs/$cid'),
            equals(expectedUrl),
          );
          expect(
            manager.normalizeIpfsUrl('https://$cid.ipfs.dweb.link'),
            equals(expectedUrl),
          );
        },
      );

      test('should preserve paths in normalized URLs', () {
        const cidWithPath = 'QmTest/metadata.json';
        final expectedUrl = '${manager.gateways.first}$cidWithPath';

        expect(
          manager.normalizeIpfsUrl('ipfs://$cidWithPath'),
          equals(expectedUrl),
        );
        expect(
          manager.normalizeIpfsUrl(
            'https://gateway.pinata.cloud/ipfs/$cidWithPath',
          ),
          equals(expectedUrl),
        );
      });
    });

    group('Failure Tracking and Circuit Breaker', () {
      test('should track failed URLs', () async {
        const testUrl = 'https://test.gateway.com/ipfs/QmTest';

        expect(await manager.shouldSkipUrl(testUrl), isFalse);

        await manager.logGatewayAttempt(testUrl, false);
        expect(await manager.shouldSkipUrl(testUrl), isTrue);
      });

      test('should remove URLs from failed set on success', () async {
        const testUrl = 'https://test.gateway.com/ipfs/QmTest';

        await manager.logGatewayAttempt(testUrl, false);
        expect(await manager.shouldSkipUrl(testUrl), isTrue);

        await manager.logGatewayAttempt(testUrl, true);
        expect(await manager.shouldSkipUrl(testUrl), isFalse);
      });

      test('should respect failure cooldown period', () async {
        const testUrl = 'https://test.gateway.com/ipfs/QmTest';
        final shortCooldownManager = IpfsGatewayManager(
          failureCooldown: const Duration(milliseconds: 100),
        );

        await shortCooldownManager.logGatewayAttempt(testUrl, false);
        expect(await shortCooldownManager.shouldSkipUrl(testUrl), isTrue);

        // Wait for cooldown to expire
        await Future.delayed(const Duration(milliseconds: 150));
        expect(await shortCooldownManager.shouldSkipUrl(testUrl), isFalse);
      });

      test(
        'should filter out failed URLs from reliable gateway URLs',
        () async {
          const originalUrl = 'ipfs://QmTest';
          final allUrls = manager.getGatewayUrls(originalUrl);

          if (allUrls.isNotEmpty) {
            // Mark first gateway as failed
            await manager.logGatewayAttempt(allUrls.first, false);

            final reliableUrls = await manager.getReliableGatewayUrls(
              originalUrl,
            );
            expect(reliableUrls.length, equals(allUrls.length - 1));
            expect(reliableUrls.contains(allUrls.first), isFalse);
          }
        },
      );
    });

    group('Edge Cases and Error Handling', () {
      test('should handle malformed URLs gracefully', () {
        const malformedUrls = [
          'ipfs://',
          'ipfs:///',
          'https://ipfs.io/ipfs/',
          'https://.ipfs.dweb.link',
          'not-a-url',
          'ftp://example.com/file',
        ];

        for (final url in malformedUrls) {
          expect(() => manager.getGatewayUrls(url), returnsNormally);
          expect(() => manager.normalizeIpfsUrl(url), returnsNormally);
        }
      });

      test('should handle very long URLs', () {
        final longCid =
            'QmYjtig7VJQ6XsnUjqqJvj7QaMcCAwtrgNdahSiFofrE7o${'A' * 100}';
        final urls = manager.getGatewayUrls('ipfs://$longCid');

        expect(urls.isNotEmpty, isTrue);
        expect(urls.first.contains(longCid), isTrue);
      });

      test('should handle URLs with special characters', () {
        const specialPath =
            'QmTest/file%20with%20spaces.json?param=value#anchor';
        final urls = manager.getGatewayUrls('ipfs://$specialPath');

        expect(urls.isNotEmpty, isTrue);
        expect(urls.first.contains(specialPath), isTrue);
      });

      test('should handle case variations in URL schemes', () {
        // URL schemes and paths should be case-insensitive
        expect(IpfsGatewayManager.isIpfsUrl('IPFS://QmTest'), isTrue);
        expect(IpfsGatewayManager.isIpfsUrl('Ipfs://QmTest'), isTrue);
        expect(IpfsGatewayManager.isIpfsUrl('ipfs://QmTest'), isTrue);
        // Gateway URLs with different case should work
        expect(
          IpfsGatewayManager.isIpfsUrl('HTTPS://gateway.com/IPFS/QmTest'),
          isTrue,
        );
        expect(
          IpfsGatewayManager.isIpfsUrl('https://gateway.com/ipfs/QmTest'),
          isTrue,
        );
        expect(
          IpfsGatewayManager.isIpfsUrl('https://gateway.com/Ipfs/QmTest'),
          isTrue,
        );
      });
    });

    group('Real-world Examples', () {
      group('NFT Metadata URLs', () {
        test('should handle typical NFT metadata IPFS URLs', () {
          const examples = [
            'ipfs://QmYjtig7VJQ6XsnUjqqJvj7QaMcCAwtrgNdahSiFofrE7o',
            'ipfs://QmPMc4tcBsMqLRuCQtPmPe84bpSjrC3Ky7t3JWuHXYB4aS/1',
            'https://ipfs.io/ipfs/QmYjtig7VJQ6XsnUjqqJvj7QaMcCAwtrgNdahSiFofrE7o',
            'https://gateway.pinata.cloud/ipfs/QmPMc4tcBsMqLRuCQtPmPe84bpSjrC3Ky7t3JWuHXYB4aS/metadata.json',
          ];

          for (final example in examples) {
            final urls = manager.getGatewayUrls(example);
            expect(urls.isNotEmpty, isTrue, reason: 'Failed for: $example');
            expect(
              IpfsGatewayManager.isIpfsUrl(example),
              isTrue,
              reason: 'Not detected as IPFS: $example',
            );
          }
        });

        test('should handle subdomain IPFS URLs from popular services', () {
          const examples = [
            'https://bafybeigdyrzt5sfp7udm7hu76uh7y26nf3efuylqabf3oclgtqy55fbzdi.ipfs.dweb.link',
            'https://QmYjtig7VJQ6XsnUjqqJvj7QaMcCAwtrgNdahSiFofrE7o.ipfs.nftstorage.link',
            'https://QmPMc4tcBsMqLRuCQtPmPe84bpSjrC3Ky7t3JWuHXYB4aS.ipfs.w3s.link/metadata.json',
          ];

          for (final example in examples) {
            final urls = manager.getGatewayUrls(example);
            expect(urls.isNotEmpty, isTrue, reason: 'Failed for: $example');
            expect(
              IpfsGatewayManager.isIpfsUrl(example),
              isTrue,
              reason: 'Not detected as IPFS: $example',
            );
          }
        });
      });

      group('Non-IPFS URLs', () {
        test('should handle regular image URLs', () {
          const examples = [
            'https://example.com/image.png',
            'https://cdn.example.com/assets/logo.svg',
            'https://api.example.com/v1/image/123.jpg',
            'http://localhost:3000/test-image.gif',
            'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8/5+hHgAHggJ/PchI7wAAAABJRU5ErkJggg==',
          ];

          for (final example in examples) {
            expect(
              IpfsGatewayManager.isIpfsUrl(example),
              isFalse,
              reason: 'Incorrectly detected as IPFS: $example',
            );
            final urls = manager.getGatewayUrls(example);
            expect(
              urls.length,
              equals(1),
              reason: 'Should return original URL: $example',
            );
            expect(
              urls.first,
              equals(example),
              reason: 'Should return unchanged: $example',
            );
          }
        });
      });

      group('Invalid/Broken URLs', () {
        test('should handle invalid URLs gracefully', () {
          const invalidExamples = [
            '',
            '   ',
            'not-a-url',
            '://missing-scheme',
            'https://',
            'ipfs://',
            'javascript:alert("xss")',
            'file:///etc/passwd',
          ];

          for (final example in invalidExamples) {
            expect(
              () => manager.getGatewayUrls(example),
              returnsNormally,
              reason: 'Should not throw for: $example',
            );
            expect(
              () => IpfsGatewayManager.isIpfsUrl(example),
              returnsNormally,
              reason: 'Should not throw for: $example',
            );
          }
        });
      });
    });

    group('Performance and Logging', () {
      test('should log gateway attempts with success', () async {
        const testUrl = 'https://test.gateway.com/ipfs/QmTest';
        const loadTime = Duration(milliseconds: 250);

        // Should not throw
        await expectLater(
          manager.logGatewayAttempt(testUrl, true, loadTime: loadTime),
          completes,
        );
      });

      test('should log gateway attempts with failure', () async {
        const testUrl = 'https://test.gateway.com/ipfs/QmTest';
        const errorMessage = 'Connection timeout';

        // Should not throw
        await expectLater(
          manager.logGatewayAttempt(testUrl, false, errorMessage: errorMessage),
          completes,
        );
      });
    });
  });
}
