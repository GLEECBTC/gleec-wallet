import 'dart:math' as math;

import 'package:decimal/decimal.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';

/// Which way a displayed figure may be rounded.
///
/// A swap screen shows numbers people commit money against, so rounding is
/// never neutral: what someone receives is rounded down and what they pay in
/// costs is rounded up, so the display never promises more than the swap
/// delivers.
enum SwapRounding {
  /// Towards zero. For amounts received.
  down,

  /// Away from zero. For costs.
  up,

  /// To the nearest. For amounts the user typed or already holds.
  nearest,
}

/// Number, time and identity formatting for the swap surface.
abstract final class SwapFormat {
  static final _thousand = Decimal.fromInt(1000);
  static final _cent = Decimal.parse('0.01');
  static final _hundred = Decimal.fromInt(100);

  /// A token amount, grouped, with precision that follows its magnitude.
  static String amount(
    Decimal value, {
    SwapRounding rounding = SwapRounding.nearest,
  }) => value == Decimal.zero
      ? '0'
      : _amountAt(value, _decimalsFor(value.abs()), rounding);

  static String _amountAt(Decimal value, int decimals, SwapRounding rounding) {
    if (value == Decimal.zero) return '0';
    final rounded = _round(value, decimals, rounding);
    if (rounded == Decimal.zero) {
      return '< ${_trim(Decimal.one.shift(-decimals).toStringAsFixed(decimals))}';
    }
    return _group(_trim(rounded.toStringAsFixed(decimals)));
  }

  /// [before] and [after] as [tokens] writes them, with as many more decimals
  /// as it takes for two different amounts not to read the same.
  static (String, String) tokensApart(
    Decimal before,
    Decimal after,
    String ticker, {
    SwapRounding rounding = SwapRounding.nearest,
  }) {
    var first = amount(before, rounding: rounding);
    var second = amount(after, rounding: rounding);
    var decimals = math.max(
      _decimalsFor(before.abs()),
      _decimalsFor(after.abs()),
    );
    final exact = math.max(before.scale, after.scale);
    while (first == second && before != after && decimals < exact) {
      decimals++;
      first = _amountAt(before, decimals, rounding);
      second = _amountAt(after, decimals, rounding);
    }
    return ('$first $ticker', '$second $ticker');
  }

  /// [value] at the precision [amount] shows it with, so an amount offered as
  /// a label is exactly the one used.
  static Decimal shown(
    Decimal value, {
    SwapRounding rounding = SwapRounding.nearest,
  }) => value == Decimal.zero
      ? value
      : _round(value, _decimalsFor(value.abs()), rounding);

  static int _decimalsFor(Decimal abs) {
    if (abs >= _thousand) return 2;
    if (abs >= Decimal.one) return 4;
    return (_leadingFractionZeros(abs) + 4).clamp(0, 8);
  }

  /// A token amount followed by its ticker.
  static String tokens(
    Decimal value,
    String ticker, {
    SwapRounding rounding = SwapRounding.nearest,
  }) => '${amount(value, rounding: rounding)} $ticker';

  /// A US-dollar value: "$1,204.33", or "< $0.01" for dust.
  static String usd(
    Decimal value, {
    SwapRounding rounding = SwapRounding.nearest,
  }) {
    final abs = value.abs();
    if (abs > Decimal.zero && abs < _cent) return r'< $0.01';
    final rounded = _round(value, 2, rounding);
    final sign = rounded < Decimal.zero ? '-' : '';
    return '$sign\$${_group(rounded.abs().toStringAsFixed(2))}';
  }

  /// A fraction as a percentage: 0.052 → "5.2%".
  static String percent(Decimal fraction) {
    final value = _round(fraction * _hundred, 1, SwapRounding.nearest);
    return '${_trim(value.toStringAsFixed(1))}%';
  }

  /// How long a swap has run or took: "under a minute", "12 min", "2 h",
  /// "1 h 5 min". Minutes round down, or up with [roundUp], as an estimate's
  /// should.
  static String elapsed(Duration duration, {bool roundUp = false}) {
    final seconds = duration.isNegative ? 0 : duration.inSeconds;
    final minutes = roundUp ? (seconds / 60).ceil() : seconds ~/ 60;
    if (minutes < 1) return LocaleKeys.swapTimeUnderMinute.tr();
    if (minutes < 60) return LocaleKeys.swapTimeMinutes.tr(args: ['$minutes']);
    final hours = '${minutes ~/ 60}';
    final rest = minutes % 60;
    return rest == 0
        ? LocaleKeys.swapTimeHours.tr(args: [hours])
        : LocaleKeys.swapTimeHoursMinutes.tr(args: [hours, '$rest']);
  }

  /// How long something takes, in words.
  static String duration(Duration? duration) {
    if (duration == null || duration <= Duration.zero) {
      return LocaleKeys.swapDurationVaries.tr();
    }
    final seconds = duration.inSeconds;
    if (seconds < 60) {
      final rounded = ((seconds / 5).ceil() * 5).clamp(5, 55);
      return LocaleKeys.swapDurationSeconds.tr(args: ['$rounded']);
    }
    if (seconds < 90) return LocaleKeys.swapDurationOneMinute.tr();
    if (seconds < 3600) {
      return LocaleKeys.swapDurationMinutes.tr(
        args: ['${(seconds / 60).round()}'],
      );
    }
    final hours = seconds / 3600;
    final label = hours < 10
        ? _trim(hours.toStringAsFixed(1))
        : '${hours.round()}';
    if (label == '1') return LocaleKeys.swapDurationOneHour.tr();
    return LocaleKeys.swapDurationHours.tr(args: [label]);
  }

  /// An address or hash shortened to its recognisable ends.
  static String short(String value) {
    if (value.length <= 14) return value;
    return '${value.substring(0, 6)}…${value.substring(value.length - 4)}';
  }

  /// A time: the clock for today, the date otherwise.
  static String time(DateTime time, {DateTime? now}) {
    final local = time.toLocal();
    final today = (now ?? DateTime.now()).toLocal();
    if (local.year == today.year &&
        local.month == today.month &&
        local.day == today.day) {
      return DateFormat.Hm().format(local);
    }
    if (local.year == today.year) {
      return DateFormat.MMMd().add_Hm().format(local);
    }
    return DateFormat.yMMMd().add_Hm().format(local);
  }

  /// The ticker a user knows an asset by: "USDT", not "USDT-ERC20".
  static String ticker(AssetId asset) => asset.symbol.configSymbol;

  static Decimal _round(Decimal value, int scale, SwapRounding rounding) =>
      switch (rounding) {
        SwapRounding.down =>
          value >= Decimal.zero
              ? value.floor(scale: scale)
              : value.ceil(scale: scale),
        SwapRounding.up =>
          value >= Decimal.zero
              ? value.ceil(scale: scale)
              : value.floor(scale: scale),
        SwapRounding.nearest => value.round(scale: scale),
      };

  static int _leadingFractionZeros(Decimal abs) {
    var zeros = 0;
    var probe = abs;
    while (probe < Decimal.one && zeros < 18) {
      probe = probe * Decimal.ten;
      if (probe < Decimal.one) zeros++;
    }
    return zeros;
  }

  static String _trim(String fixed) {
    if (!fixed.contains('.')) return fixed;
    var result = fixed.replaceFirst(RegExp(r'0+$'), '');
    if (result.endsWith('.')) result = result.substring(0, result.length - 1);
    return result;
  }

  static String _group(String plain) {
    final negative = plain.startsWith('-');
    final unsigned = negative ? plain.substring(1) : plain;
    final parts = unsigned.split('.');
    final digits = parts.first;
    final buffer = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
      buffer.write(digits[i]);
    }
    final grouped = parts.length > 1
        ? '$buffer.${parts[1]}'
        : buffer.toString();
    return negative ? '-$grouped' : grouped;
  }
}
