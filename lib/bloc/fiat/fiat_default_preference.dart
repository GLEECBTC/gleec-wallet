import 'package:decimal/decimal.dart';
import 'package:komodo_cex_market_data/komodo_cex_market_data.dart'
    as market_data;
import 'package:web_dex/bloc/fiat/models/i_currency.dart' as fiat_models;
import 'package:web_dex/services/storage/base_storage.dart';
import 'package:web_dex/shared/constants.dart';

String? normalizeDefaultFiatPreferenceValue(String? rawValue) {
  if (rawValue == null) {
    return null;
  }

  final trimmed = rawValue.trim();
  if (trimmed.isEmpty) {
    return null;
  }

  final resolved = market_data.FiatCurrency.fromString(trimmed);
  return resolved?.symbol;
}

Future<fiat_models.FiatCurrency?> loadDefaultFiatPreference(
  BaseStorage storage,
) async {
  final rawValue = await storage.read(defaultFiatPreferenceKey);
  final normalized = rawValue is String
      ? normalizeDefaultFiatPreferenceValue(rawValue)
      : null;
  if (normalized == null) {
    return null;
  }

  final resolved = market_data.FiatCurrency.fromString(normalized);
  if (resolved == null) {
    return null;
  }

  return fiat_models.FiatCurrency(
    symbol: resolved.symbol,
    name: resolved.displayName,
    minPurchaseAmount: Decimal.zero,
  );
}

Future<void> persistDefaultFiatPreference(
  BaseStorage storage,
  fiat_models.FiatCurrency fiat,
) async {
  await storage.write(defaultFiatPreferenceKey, fiat.getAbbr());
}
