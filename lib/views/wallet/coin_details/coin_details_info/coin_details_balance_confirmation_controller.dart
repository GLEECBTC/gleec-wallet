import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:flutter/foundation.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';

typedef FetchBalance = Future<BalanceInfo> Function();

/// Confirms coin-details balance before the UI renders numeric values.
///
/// The controller treats initial cached values as unconfirmed and transitions
/// to confirmed state when:
/// 1) a bootstrap `getBalance` call succeeds, or
/// 2) a stream update arrives after at least one bootstrap attempt.
class CoinDetailsBalanceConfirmationController extends ChangeNotifier {
  CoinDetailsBalanceConfirmationController({
    required FetchBalance fetchConfirmedBalance,
    BalanceInfo? initialBalance,
    this.maxStartupRetries = 2,
    this.retryBackoffBase = const Duration(milliseconds: 300),
  }) : _fetchConfirmedBalance = fetchConfirmedBalance,
       _latestBalance = initialBalance;

  final FetchBalance _fetchConfirmedBalance;
  final int maxStartupRetries;
  final Duration retryBackoffBase;

  BalanceInfo? _latestBalance;
  bool _isConfirmed = false;
  bool _isBootstrapInFlight = false;
  bool _hasCompletedBootstrapAttempt = false;
  int _startupRetryAttempts = 0;
  bool _isDisposed = false;

  BalanceInfo? get latestBalance => _latestBalance;
  bool get isConfirmed => _isConfirmed;
  bool get isBootstrapping => _isBootstrapInFlight;
  int get startupRetryAttempts => _startupRetryAttempts;

  Future<void> bootstrap() async {
    if (_isDisposed || _isConfirmed || _isBootstrapInFlight) return;

    _isBootstrapInFlight = true;
    _notifyListenersIfAlive();

    try {
      final balance = await _fetchConfirmedBalance();
      if (_isDisposed) return;
      _latestBalance = balance;
      _isConfirmed = true;
    } catch (_) {
      // Best effort. Startup errors are handled with bounded retries.
    } finally {
      _hasCompletedBootstrapAttempt = true;
      _isBootstrapInFlight = false;
      if (!_isDisposed) {
        _notifyListenersIfAlive();
      }
    }
  }

  void onStreamBalance(BalanceInfo balance) {
    if (_isDisposed) return;

    _latestBalance = balance;

    if (!_isConfirmed) {
      final hasNonZeroValue = balance.spendable > Decimal.zero;
      if (hasNonZeroValue || _hasCompletedBootstrapAttempt) {
        _isConfirmed = true;
      }
    }

    _notifyListenersIfAlive();
  }

  Future<void> onStartupStreamError() async {
    if (_isDisposed || _isConfirmed) return;
    if (_startupRetryAttempts >= maxStartupRetries) return;

    _startupRetryAttempts += 1;
    _notifyListenersIfAlive();

    final delayMs = retryBackoffBase.inMilliseconds * _startupRetryAttempts;
    await Future<void>.delayed(Duration(milliseconds: delayMs));

    if (_isDisposed || _isConfirmed) return;
    await bootstrap();
  }

  void _notifyListenersIfAlive() {
    if (_isDisposed) return;
    notifyListeners();
  }

  @override
  void dispose() {
    _isDisposed = true;
    super.dispose();
  }
}
