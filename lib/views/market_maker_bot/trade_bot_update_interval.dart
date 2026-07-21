enum TradeBotUpdateInterval {
  oneMinute,
  threeMinutes,
  fiveMinutes,
  tenMinutes,
  fifteenMinutes,
  thirtyMinutes,
  sixtyMinutes;

  @override
  String toString() {
    switch (this) {
      case TradeBotUpdateInterval.oneMinute:
        return '1';
      case TradeBotUpdateInterval.threeMinutes:
        return '3';
      case TradeBotUpdateInterval.fiveMinutes:
        return '5';
      case TradeBotUpdateInterval.tenMinutes:
        return '10';
      case TradeBotUpdateInterval.fifteenMinutes:
        return '15';
      case TradeBotUpdateInterval.thirtyMinutes:
        return '30';
      case TradeBotUpdateInterval.sixtyMinutes:
        return '60';
    }
  }

  static TradeBotUpdateInterval fromString(String interval) {
    final exact = tryFromString(interval);
    if (exact != null) return exact;

    // Keep displaying valid legacy/custom KDF intervals using the closest UI
    // option. Form submissions remain strict through [tryFromString].
    if (interval.isEmpty ||
        interval.length > 16 ||
        interval != interval.trim()) {
      return TradeBotUpdateInterval.fiveMinutes;
    }
    final parsed = int.tryParse(interval);
    if (parsed == null) return TradeBotUpdateInterval.fiveMinutes;
    final seconds = parsed < 60 ? parsed * 60 : parsed;
    if (seconds < 60 || seconds > 86400) {
      return TradeBotUpdateInterval.fiveMinutes;
    }

    return TradeBotUpdateInterval.values.reduce(
      (current, candidate) =>
          (candidate.seconds - seconds).abs() <
              (current.seconds - seconds).abs()
          ? candidate
          : current,
    );
  }

  static TradeBotUpdateInterval? tryFromString(String interval) {
    if (interval.isEmpty ||
        interval.length > 16 ||
        interval != interval.trim()) {
      return null;
    }
    final parsed = int.tryParse(interval);
    if (parsed == null) return null;

    // Backward compatibility: legacy values can be saved either as minutes
    // (1/3/5) or as seconds (60/180/300).
    final seconds = parsed < 60 ? parsed * 60 : parsed;
    return tryFromSeconds(seconds);
  }

  static TradeBotUpdateInterval? tryFromSeconds(int seconds) {
    for (final option in TradeBotUpdateInterval.values) {
      if (option.seconds == seconds) return option;
    }
    return null;
  }

  int get minutes {
    switch (this) {
      case TradeBotUpdateInterval.oneMinute:
        return 1;
      case TradeBotUpdateInterval.threeMinutes:
        return 3;
      case TradeBotUpdateInterval.fiveMinutes:
        return 5;
      case TradeBotUpdateInterval.tenMinutes:
        return 10;
      case TradeBotUpdateInterval.fifteenMinutes:
        return 15;
      case TradeBotUpdateInterval.thirtyMinutes:
        return 30;
      case TradeBotUpdateInterval.sixtyMinutes:
        return 60;
    }
  }

  int get seconds {
    switch (this) {
      case TradeBotUpdateInterval.oneMinute:
        return 60;
      case TradeBotUpdateInterval.threeMinutes:
        return 180;
      case TradeBotUpdateInterval.fiveMinutes:
        return 300;
      case TradeBotUpdateInterval.tenMinutes:
        return 600;
      case TradeBotUpdateInterval.fifteenMinutes:
        return 900;
      case TradeBotUpdateInterval.thirtyMinutes:
        return 1800;
      case TradeBotUpdateInterval.sixtyMinutes:
        return 3600;
    }
  }
}
