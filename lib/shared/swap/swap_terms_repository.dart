import 'dart:convert';

import 'package:web_dex/services/storage/base_storage.dart';
import 'package:web_dex/services/storage/get_storage.dart';

/// A recorded acceptance of the routing provider's terms.
class SwapTermsAcceptance {
  const SwapTermsAcceptance({
    required this.version,
    required this.acceptedAt,
    required this.provider,
    required this.url,
  });

  /// Parses a stored record, or returns null for anything unreadable.
  static SwapTermsAcceptance? tryParse(Object? raw) {
    try {
      final json = raw is String ? jsonDecode(raw) : raw;
      if (json is! Map) return null;
      final version = json['version'];
      final acceptedAt = DateTime.tryParse('${json['accepted_at']}');
      if (version is! int || acceptedAt == null) return null;
      return SwapTermsAcceptance(
        version: version,
        acceptedAt: acceptedAt,
        provider: '${json['provider'] ?? ''}',
        url: '${json['url'] ?? ''}',
      );
    } on Object {
      return null;
    }
  }

  /// Which version of the terms was accepted.
  final int version;

  /// When.
  final DateTime acceptedAt;

  /// Whose terms.
  final String provider;

  /// Where the accepted terms were published.
  final String url;

  /// The stored form.
  String toStorage() => jsonEncode({
    'version': version,
    'accepted_at': acceptedAt.toUtc().toIso8601String(),
    'provider': provider,
    'url': url,
  });
}

/// Records that the user accepted the routing provider's third-party terms.
///
/// The routed-swap contract makes this the GUI's obligation: funds transit the
/// provider's contracts, so a user's first routed swap presents the provider's
/// terms, and the acceptance is stored app-side with no engine involvement.
/// Kept per wallet, since several people can share one device, and versioned,
/// so a change of terms asks again.
class SwapTermsRepository {
  SwapTermsRepository({
    required Future<String?> Function() walletKey,
    BaseStorage? storage,
  }) : _walletKey = walletKey,
       _storage = storage ?? getStorage();

  /// Bump to ask every wallet to accept again.
  static const currentVersion = 1;

  /// The provider whose terms apply.
  static const provider = 'LI.FI';

  /// Where the provider publishes its terms.
  static const termsUrl = 'https://li.fi/legal/terms-and-conditions/';

  static const _keyPrefix = 'routed_swap_terms_acceptance_v1';

  final Future<String?> Function() _walletKey;
  final BaseStorage _storage;

  Future<String?> _key() async {
    final wallet = await _walletKey();
    return wallet == null ? null : '$_keyPrefix:$wallet';
  }

  /// Whether the current wallet has accepted the current terms.
  Future<bool> hasAccepted() async {
    final key = await _key();
    if (key == null) return false;
    try {
      final acceptance = SwapTermsAcceptance.tryParse(await _storage.read(key));
      return acceptance != null && acceptance.version >= currentVersion;
    } on Object {
      return false;
    }
  }

  /// Records acceptance for the current wallet.
  Future<void> recordAcceptance({DateTime? at}) async {
    final key = await _key();
    if (key == null) return;
    await _storage.write(
      key,
      SwapTermsAcceptance(
        version: currentVersion,
        acceptedAt: at ?? DateTime.now(),
        provider: provider,
        url: termsUrl,
      ).toStorage(),
    );
  }
}
