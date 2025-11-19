import 'dart:async';

import 'package:app_theme/app_theme.dart';
import 'package:decimal/decimal.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart'
    show ReadContext, RepositoryProvider;
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:rational/rational.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:web_dex/app_config/app_config.dart';
import 'package:web_dex/bloc/coins_bloc/coins_bloc.dart';
import 'package:web_dex/blocs/trading_entities_bloc.dart'
    show TradingEntitiesBloc;
import 'package:web_dex/common/screen.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/model/coin.dart';
import 'package:web_dex/model/coin_type.dart';
import 'package:web_dex/performance_analytics/performance_analytics.dart';
import 'package:web_dex/services/logger/get_logger.dart';
import 'package:web_dex/shared/constants.dart';
import 'package:web_dex/shared/widgets/information_popup.dart';

export 'package:web_dex/shared/utils/extensions/async_extensions.dart';
export 'package:web_dex/shared/utils/extensions/collection_extensions.dart';
export 'package:web_dex/shared/utils/extensions/legacy_coin_migration_extensions.dart';
export 'package:web_dex/shared/utils/extensions/sdk_extensions.dart';
export 'package:web_dex/shared/utils/prominent_colors.dart';

// TODO: Refactor this (and all its references) to remove the context dependency
// and/or make it optional, and then use the global `scaffoldKey` instead.
Future<void> copyToClipBoard(
  BuildContext context,
  String payload, [
  String? message,
]) async {
  if (!context.mounted) return;
  final themeData = Theme.of(context);

  try {
    await Clipboard.setData(ClipboardData(text: payload));

    if (!context.mounted) return;
    final scaffoldMessenger =
        ScaffoldMessenger.maybeOf(context) ??
        ScaffoldMessenger.of(scaffoldKey.currentContext!);
    scaffoldMessenger.showSnackBar(
      SnackBar(
        width: isMobile ? null : 400.0,
        content: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.check_circle,
              color: themeData.colorScheme.onPrimaryContainer,
            ),
            const SizedBox(width: 12.0),
            Text(message ?? LocaleKeys.clipBoard.tr()),
          ],
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  } catch (e) {
    log('Error copyToClipBoard: $e', isError: true);
    if (!context.mounted) return; // Show error feedback using SnackBar
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Failed to copy to clipboard'),
        backgroundColor: themeData.colorScheme.error,
        duration: const Duration(seconds: 2),
      ),
    );
  }
}

/// Converts a double value [dv] to a string representation with specified decimal places [fractions].
/// Parameters:
/// - [dv] (double): The input double value to be converted to a string.
/// - [fractions] (int): The number of decimal places to format the double value. Default is 8.
///
/// Return Value:
/// - (String): The formatted string representation of the double value.
///
/// Example Usage:
/// ```dart
/// double inputValue1 = 123.456789;
/// String result1 = doubleToString(inputValue1, 3);
/// print(result1); // Output: "123.457"
/// ```
/// ```dart
/// double inputValue2 = 1000.0;
/// String result2 = doubleToString(inputValue2);
/// print(result2); // Output: "1000"
/// ```
/// unit tests: [testCustomDoubleToString]
String doubleToString(double dv, [int fractions = 8]) {
  final Rational r = Rational.parse(dv.toString());
  if (r.isInteger) {
    return r
        .toDecimal(scaleOnInfinitePrecision: scaleOnInfinitePrecision)
        .toStringAsFixed(0);
  }
  String sv = r
      .toDecimal(scaleOnInfinitePrecision: scaleOnInfinitePrecision)
      .toStringAsFixed(fractions > 20 ? 20 : fractions);
  final dot = sv.indexOf('.');
  // Looks like we already have [cutTrailingZeros]
  sv = sv.replaceFirst(RegExp(r'0+$'), '', dot);
  if (sv.length - 1 == dot) sv = sv.substring(0, dot);
  if (sv == '-0') sv = sv.replaceAll('-', '');
  return sv;
}

/// Converts a map [fract] containing numerator and denominator to a [Rational] value.
/// Parameters:
/// - [fract] (Map<String, dynamic>?): The map containing numerator and denominator values.
///
/// Return Value:
/// - (Rational?): The [Rational] value representing the numerator and denominator,
///                 or null if conversion fails or [fract] is null.
///
/// Example Usage:
/// ```dart
/// Map<String, dynamic> fractionMap = {'numer': 3, 'denom': 4};
/// Rational? result = fract2rat(fractionMap);
/// print(result); // Output: Rational with value 3/4
/// ```
/// ```dart
/// Rational? result = fract2rat(null);
/// print(result); // Output: null
/// ```
/// unit tests: [testRatToFracAndViseVersa]
Rational? fract2rat(Map<String, dynamic>? fract, [bool willLog = true]) {
  if (fract == null) return null;

  try {
    final String numerStr = fract['numer'].toString();
    final String denomStr = fract['denom'].toString();
    final rat = Rational(BigInt.parse(numerStr), BigInt.parse(denomStr));
    return rat;
  } catch (e) {
    if (willLog) {
      log('Error fract2rat: $e', isError: true);
    }
    return null;
  }
}

/// Converts a [Rational] value [rat] to a map containing numerator and denominator.
///
/// Parameters:
/// - [rat] (Rational?): The [Rational] value to be converted to a map.
/// - [toLog] (bool): Whether to log errors. Default is true.
///
/// Return Value:
/// - (Map<String, dynamic>?): The map containing 'numer' and 'denom' keys and values,
///                            or null if conversion fails or [rat] is null.
///
/// Example Usage:
/// ```dart
/// Rational inputRational = Rational.fromBigInt(BigInt.from(3), BigInt.from(4));
/// Map<String, dynamic>? result = rat2fract(inputRational);
/// print(result); // Output: {'numer': '3', 'denom': '4'}
/// ```
/// ```dart
/// Map<String, dynamic>? result = rat2fract(null);
/// print(result); // Output: null
/// ```
/// unit tests: [testRatToFracAndViseVersa]
Map<String, dynamic>? rat2fract(Rational? rat, [bool toLog = true]) {
  if (rat == null) return null;

  try {
    return <String, dynamic>{
      'numer': rat.numerator.toString(),
      'denom': rat.denominator.toString(),
    };
  } catch (e) {
    if (toLog) {
      log('Error rat2fract: $e', isError: true);
    }
    return null;
  }
}

String getTxExplorerUrl(Coin coin, String txHash) {
  final String explorerUrl = coin.explorerUrl;
  final String explorerTxUrl = coin.explorerTxUrl;
  if (explorerUrl.isEmpty) return '';

  final hash =
      coin.type == CoinType.tendermint || coin.type == CoinType.tendermintToken
      ? txHash.toUpperCase()
      : txHash;

  return coin.need0xPrefixForTxHash && !hash.startsWith('0x')
      ? '$explorerUrl${explorerTxUrl}0x$hash'
      : '$explorerUrl$explorerTxUrl$hash';
}

String getAddressExplorerUrl(Coin coin, String address) {
  final String explorerUrl = coin.explorerUrl;
  final String explorerAddressUrl = coin.explorerAddressUrl;
  if (explorerUrl.isEmpty) return '';

  return '$explorerUrl$explorerAddressUrl$address';
}

@Deprecated('Use the Protocol class\'s explorer URL methods')
void viewHashOnExplorer(Coin coin, String address, HashExplorerType type) {
  late String url;
  switch (type) {
    case HashExplorerType.address:
      url = getAddressExplorerUrl(coin, address);
      break;
    case HashExplorerType.tx:
      url = getTxExplorerUrl(coin, address);
      break;
  }
  launchURLString(url);
}

extension AssetExplorerUrls on Asset {
  Uri? txExplorerUrl(String? txHash) {
    return txHash == null ? null : protocol.explorerTxUrl(txHash);
  }

  Uri? addressExplorerUrl(String? address) {
    return address == null ? null : protocol.explorerAddressUrl(address);
  }
}

Future<void> openUrl(Uri uri, {bool? inSeparateTab}) async {
  if (!await canLaunchUrl(uri)) {
    throw Exception('Could not launch $uri');
  }
  await launchUrl(
    uri,
    mode: inSeparateTab == null
        ? LaunchMode.platformDefault
        : inSeparateTab == true
        ? LaunchMode.externalApplication
        : LaunchMode.inAppWebView,
  );
}

Future<void> launchURLString(String url, {bool? inSeparateTab}) async {
  final uri = Uri.parse(url);

  if (await canLaunchUrl(uri)) {
    await launchUrl(
      uri,
      mode: inSeparateTab == null
          ? LaunchMode.platformDefault
          : inSeparateTab == true
          ? LaunchMode.externalApplication
          : LaunchMode.inAppWebView,
    );
  } else {
    throw 'Could not launch $url';
  }
}

// TODO: deprecate
Future<void> log(
  String message, {
  String? path,
  StackTrace? trace,
  bool isError = false,
}) async {
  final timer = Stopwatch()..start();
  // todo(yurii & ivan): to finish stacktrace parsing
  // if (trace != null) {
  //   final String errorTrace = getInfoFromStackTrace(trace);
  //   logger.write('$errorTrace: $errorOrUsefulData');
  // }
  const isTestEnv = isTestMode || kDebugMode;
  if (isTestEnv && isError) {
    // ignore: avoid_print
    print('path: $path');
    // ignore: avoid_print
    print('error: $message');
    if (trace != null) {
      // ignore: avoid_print
      print('trace: $trace');
    }
  }

  try {
    await logger.write(message, path);

    // TODO: Add a `.dispose()` method to the logger library and call it before
    // the app is disposed.

    performance.logTimeWritingLogs(timer.elapsedMilliseconds);
  } catch (e) {
    // TODO: replace below with crashlytics reporting or show UI the printed
    // message in a snackbar/banner.
    // ignore: avoid_print
    print(
      'ERROR: Writing logs failed. Exported log files may be incomplete.'
      '\nError message: $e',
    );
  } finally {
    timer.stop();
  }
}

/// Returns the ticker from the coin abbreviation.
///
/// Parameters:
/// - [abbr] (String): The abbreviation of the coin, including suffixes like the
/// coin token type (e.g. 'ETH-ERC20', 'BNB-BEP20') and whether the coin is
/// a test or OLD coin (e.g. 'ETH_OLD', 'BNB-TEST').
///
/// Return Value:
/// - (String): The ticker of the coin, with the suffixes removed.
///
/// Example Usage:
/// ```dart
/// String abbr = 'ETH-ERC20';
///
/// String ticker = abbr2Ticker(abbr);
/// print(ticker); // Output: "ETH"
/// ```
String abbr2Ticker(String abbr) {
  if (_abbr2TickerCache.containsKey(abbr)) return _abbr2TickerCache[abbr]!;
  if (!abbr.contains('-') && !abbr.contains('_')) return abbr;

  const List<String> filteredSuffixes = [
    'ERC20',
    'BEP20',
    'QRC20',
    'FTM20',
    'ARB20',
    'BASE',
    'HRC20',
    'MVR20',
    'AVX20',
    'HCO20',
    'PLG20',
    'KRC20',
    'SLP',
    'IBC_IRIS',
    'IBC-IRIS',
    'IRIS',
    'segwit',
    'OLD',
    'IBC_NUCLEUSTEST',
  ];

  // Join the suffixes with '|' to form the regex pattern
  final String regexPattern = '(${filteredSuffixes.join('|')})';

  final String ticker = abbr
      .replaceAll(RegExp('-$regexPattern'), '')
      .replaceAll(RegExp('_$regexPattern'), '');

  _abbr2TickerCache[abbr] = ticker;
  return ticker;
}

/// Returns the ticker from the coin abbreviation with the following suffixes:
/// - 'OLD' for OLD coins.
/// - 'TESTNET' for test coins.
///
/// Parameters:
/// - [abbr] (String): The abbreviation of the coin, including suffixes like the
/// coin token type (e.g. 'ETH-ERC20', 'BNB-BEP20') and whether the coin is
/// a test or OLD coin (e.g. 'ETH_OLD', 'BNB-TEST').
///
/// Return Value:
/// - (String): The ticker of the coin, with the suffixes removed and the
/// suffixes 'OLD' or 'TESTNET' added if present in the abbreviation.
String abbr2TickerWithSuffix(String abbr) {
  final isOldCoin = RegExp(r'[-_]OLD$', caseSensitive: false).hasMatch(abbr);
  final ticker = abbr2Ticker(abbr);
  if (isOldCoin) {
    return '$ticker (OLD)';
  }
  return ticker;
}

final Map<String, String> _abbr2TickerCache = {};

Color getProtocolColor(CoinType type) {
  switch (type) {
    case CoinType.zhtlc:
    case CoinType.utxo:
      return const Color.fromRGBO(233, 152, 60, 1);
    case CoinType.erc20:
      return const Color.fromRGBO(108, 147, 237, 1);
    case CoinType.smartChain:
      return const Color.fromRGBO(32, 22, 49, 1);
    case CoinType.sia:
      return const Color(0xFF29F06F);
    case CoinType.bep20:
      return const Color.fromRGBO(255, 199, 0, 1);
    case CoinType.qrc20:
      return const Color.fromRGBO(0, 168, 226, 1);
    case CoinType.ftm20:
      return const Color.fromRGBO(25, 105, 255, 1);
    case CoinType.arb20:
      return const Color.fromRGBO(0, 168, 226, 1);
    case CoinType.base20:
      return const Color.fromRGBO(0, 168, 226, 1);
    case CoinType.hrc20:
      return const Color.fromRGBO(29, 195, 219, 1);
    case CoinType.etc:
      return const Color.fromRGBO(16, 185, 129, 1);
    case CoinType.avx20:
      return const Color.fromRGBO(232, 65, 66, 1);
    case CoinType.mvr20:
      return const Color.fromRGBO(242, 183, 5, 1);
    case CoinType.hco20:
      return const Color.fromRGBO(1, 148, 67, 1);
    case CoinType.plg20:
      return const Color.fromRGBO(130, 71, 229, 1);
    case CoinType.sbch:
      return const Color.fromRGBO(117, 222, 84, 1);
    case CoinType.ubiq:
      return const Color.fromRGBO(0, 234, 144, 1);
    case CoinType.krc20:
      return const Color.fromRGBO(66, 229, 174, 1);
    case CoinType.tendermintToken:
      return const Color.fromRGBO(60, 60, 85, 1);
    case CoinType.tendermint:
      return const Color.fromRGBO(136, 87, 138, 1);
    case CoinType.slp:
      return const Color.fromRGBO(134, 184, 124, 1);
  }
}

bool hasTxHistorySupport(Coin coin) {
  switch (coin.type) {
    case CoinType.sbch:
    case CoinType.ubiq:
    case CoinType.hrc20:
      return false;
    case CoinType.krc20:
    case CoinType.tendermint:
    case CoinType.tendermintToken:
    case CoinType.utxo:
    case CoinType.sia:
    case CoinType.erc20:
    case CoinType.smartChain:
    case CoinType.bep20:
    case CoinType.qrc20:
    case CoinType.ftm20:
    case CoinType.arb20:
    case CoinType.base20:
    case CoinType.etc:
    case CoinType.avx20:
    case CoinType.mvr20:
    case CoinType.hco20:
    case CoinType.plg20:
    case CoinType.slp:
    case CoinType.zhtlc:
      return true;
  }
}

String getNativeExplorerUrlByCoin(Coin coin, String? address) {
  final bool hasSupport = hasTxHistorySupport(coin);
  final coinAddress = address ?? coin.address;
  assert(!hasSupport);

  switch (coin.type) {
    case CoinType.sbch:
    case CoinType.tendermint:
      return '${coin.explorerUrl}address/$coinAddress';
    case CoinType.tendermintToken:
      return '${coin.explorerUrl}account/$coinAddress';

    case CoinType.zhtlc:
    case CoinType.utxo:
    case CoinType.smartChain:
    case CoinType.erc20:
    case CoinType.sia:
    case CoinType.bep20:
    case CoinType.qrc20:
    case CoinType.ftm20:
    case CoinType.arb20:
    case CoinType.base20:
    case CoinType.avx20:
    case CoinType.mvr20:
    case CoinType.hco20:
    case CoinType.plg20:
    case CoinType.etc:
    case CoinType.hrc20:
    case CoinType.ubiq:
    case CoinType.krc20:
    case CoinType.slp:
      return '${coin.explorerUrl}address/$coinAddress';
  }
}

String get themeAssetPostfix => theme.mode == ThemeMode.dark ? '_dark' : '';

void rebuildAll(BuildContext? context) {
  void rebuild(Element element) {
    element.markNeedsBuild();
    element.visitChildren(rebuild);
  }

  ((materialPageContext ?? context) as Element).visitChildren(rebuild);
}

int get nowMs => DateTime.now().millisecondsSinceEpoch;

String? assertString(dynamic value) {
  if (value == null) return null;

  switch (value.runtimeType) {
    case int:
    case double:
      return value.toString();
    default:
      return value as String?;
  }
}

int? assertInt(dynamic value) {
  if (value == null) return null;

  switch (value.runtimeType) {
    case String:
      return int.parse(value as String);
    default:
      return value as int?;
  }
}

double assertDouble(dynamic value) {
  if (value == null) return double.nan;

  switch (value.runtimeType) {
    case double:
      return value as double;
    case int:
      return (value as int).toDouble();
    case String:
      return double.tryParse(value as String) ?? double.nan;
    case bool:
      return (value as bool) ? 1.0 : 0.0;
    case num:
      return (value as num).toDouble();
    default:
      try {
        return double.parse(value.toString());
      } catch (e, s) {
        log('Error converting to double: $e', trace: s, isError: true);
        return double.nan;
      }
  }
}

Future<void> pauseWhile(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 30),
}) async {
  final int startMs = nowMs;
  bool timedOut = false;
  while (condition() && !timedOut) {
    await Future<dynamic>.delayed(const Duration(milliseconds: 10));
    timedOut = nowMs - startMs > timeout.inMilliseconds;
  }
}

enum HashExplorerType { address, tx }

Future<bool> confirmParentCoinDisable(
  BuildContext context, {
  required String parent,
  required List<String> tokens,
}) async {
  if (tokens.isEmpty) return true;
  final tokenList = tokens.join(', ');
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(LocaleKeys.disable.tr()),
      content: Text(
        LocaleKeys.parentCoinDisableWarning.tr(args: [parent, tokenList]),
      ),
      actions: [
        TextButton(
          child: Text(LocaleKeys.cancel.tr()),
          onPressed: () => Navigator.of(context).pop(false),
        ),
        TextButton(
          child: Text(LocaleKeys.disable.tr()),
          onPressed: () => Navigator.of(context).pop(true),
        ),
      ],
    ),
  );
  return result ?? false;
}

Future<bool> confirmCoinDisableWithOrders(
  BuildContext context, {
  required String coin,
  required int ordersCount,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(LocaleKeys.disable.tr()),
      content: Text(
        LocaleKeys.coinDisableOpenOrdersWarning.tr(
          args: [ordersCount.toString(), coin],
        ),
      ),
      actions: [
        TextButton(
          child: Text(LocaleKeys.cancel.tr()),
          onPressed: () => Navigator.of(context).pop(false),
        ),
        TextButton(
          child: Text(LocaleKeys.disable.tr()),
          onPressed: () => Navigator.of(context).pop(true),
        ),
      ],
    ),
  );
  return result ?? false;
}

void confirmBeforeDisablingCoin(
  Coin coin,
  BuildContext context, {
  void Function()? onConfirm,
}) {
  final tradingEntitiesBloc = RepositoryProvider.of<TradingEntitiesBloc>(
    context,
  );
  final bloc = context.read<CoinsBloc>();

  final childCoins = bloc.state.walletCoins.values
      .where((c) => c.parentCoin?.abbr == coin.abbr)
      .toList();

  final hasSwap =
      tradingEntitiesBloc.hasActiveSwap(coin.abbr) ||
      childCoins.any((c) => tradingEntitiesBloc.hasActiveSwap(c.abbr));

  if (hasSwap) {
    InformationPopup(context: context)
      ..text = LocaleKeys.coinDisableSpan1.tr(args: [coin.abbr])
      ..show();
    return;
  }

  final int openOrders =
      tradingEntitiesBloc.openOrdersCount(coin.abbr) +
      childCoins.fold<int>(
        0,
        (sum, c) => sum + tradingEntitiesBloc.openOrdersCount(c.abbr),
      );

  if (openOrders > 0) {
    confirmCoinDisableWithOrders(
      context,
      coin: coin.abbr,
      ordersCount: openOrders,
    ).then((confirmed) {
      if (!confirmed) return;
      tradingEntitiesBloc.cancelOrdersForCoin(coin.abbr);
      for (final child in childCoins) {
        tradingEntitiesBloc.cancelOrdersForCoin(child.abbr);
      }
      _confirmDisable(bloc, coin, childCoins, context, onConfirm);
    });
    return;
  }

  _confirmDisable(bloc, coin, childCoins, context, onConfirm);
  return;
}

void _confirmDisable(
  CoinsBloc bloc,
  Coin coin,
  List<Coin> childCoins,
  BuildContext context,
  void Function()? onConfirm,
) {
  if (coin.parentCoin == null) {
    final childTokens = childCoins.map((c) => c.abbr).toList();
    confirmParentCoinDisable(
      context,
      parent: coin.abbr,
      tokens: childTokens,
    ).then((confirmed) {
      if (confirmed) {
        bloc.add(CoinsDeactivated([coin.abbr]));
        onConfirm?.call();
      }
    });
  } else {
    bloc.add(CoinsDeactivated([coin.abbr]));
    onConfirm?.call();
  }
}
