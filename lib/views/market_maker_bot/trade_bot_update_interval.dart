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
    final parsed = int.tryParse(interval);
    if (parsed == null) return TradeBotUpdateInterval.fiveMinutes;

    // Backward compatibility: legacy values can be saved either as minutes
    // (1/3/5) or as seconds (60/180/300).
    final int seconds = parsed < 60 ? parsed * 60 : parsed;
    final options = TradeBotUpdateInterval.values;

    TradeBotUpdateInterval closest = options.first;
    int closestDiff = (closest.seconds - seconds).abs();

    for (final option in options.skip(1)) {
      final int diff = (option.seconds - seconds).abs();
      if (diff < closestDiff) {
        closest = option;
        closestDiff = diff;
      }
    }

    return closest;
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
