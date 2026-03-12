import 'package:web_dex/services/storage/get_storage.dart';
import 'package:web_dex/shared/constants.dart';

String _walletHdWalletModePreferenceKey(String walletId) {
  return '$hdWalletModePreferenceKey:$walletId';
}

bool? _parseStoredPreference(dynamic value) {
  if (value is bool) {
    return value;
  }
  if (value is String) {
    final normalized = value.toLowerCase();
    if (normalized == 'true') return true;
    if (normalized == 'false') return false;
  }
  return null;
}

Future<bool?> readHdWalletModePreference(String walletId) async {
  final storage = getStorage();
  final walletScopedValue = await storage.read(
    _walletHdWalletModePreferenceKey(walletId),
  );
  final parsedWalletScopedValue = _parseStoredPreference(walletScopedValue);
  if (parsedWalletScopedValue != null) {
    return parsedWalletScopedValue;
  }

  // Fall back to the legacy global key so existing users keep their last
  // selection until this wallet writes its own scoped preference.
  final legacyValue = await storage.read(hdWalletModePreferenceKey);
  return _parseStoredPreference(legacyValue);
}

Future<void> storeHdWalletModePreference(String walletId, bool value) async {
  await getStorage().write(_walletHdWalletModePreferenceKey(walletId), value);
}
