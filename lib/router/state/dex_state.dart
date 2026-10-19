import 'package:flutter/material.dart';
import 'package:web_dex/router/state/menu_state_interface.dart';

class DexState extends ChangeNotifier implements IResettableOnLogout {
  DexState()
      : _action = DexAction.none,
        _uuid = '',
        _fromCurrency = '',
        _fromAmount = '',
        _toCurrency = '',
        _toAmount = '',
        _orderType = '';

  DexAction _action;
  String _uuid;
  bool _detailsRequested = false;

  String _fromCurrency;
  String _fromAmount;
  String _toCurrency;
  String _toAmount;
  String _orderType;

  set action(DexAction action) {
    if (_action == action) {
      return;
    }

    _action = action;
    notifyListeners();
  }

  void setDetailsAction(String uuid) {
    _uuid = uuid;
    _action = DexAction.tradingDetails;
    _detailsRequested = true;
    notifyListeners();
  }

  /// Whether [setDetailsAction] was called since this was last asked, so a
  /// trading page built just after it opens on those details. Details left
  /// open on an earlier visit, or named by a link that cannot say whether it
  /// means a swap or an order, are not reopened.
  bool takeDetailsRequest() {
    final requested = _detailsRequested;
    _detailsRequested = false;
    return requested;
  }

  DexAction get action => _action;

  bool get isTradingDetails => _action == DexAction.tradingDetails;

  set uuid(String uuid) {
    _uuid = uuid;
    notifyListeners();
  }

  String get uuid => _uuid;

  String get fromCurrency => _fromCurrency;
  set fromCurrency(String fromCurrency) {
    _fromCurrency = fromCurrency;
    notifyListeners();
  }

  String get fromAmount => _fromAmount;
  set fromAmount(String fromAmount) {
    _fromAmount = fromAmount;
    notifyListeners();
  }

  String get toCurrency => _toCurrency;
  set toCurrency(String toCurrency) {
    _toCurrency = toCurrency;
    notifyListeners();
  }

  String get toAmount => _toAmount;
  set toAmount(String toAmount) {
    _toAmount = toAmount;
    notifyListeners();
  }

  String get orderType => _orderType;
  set orderType(String orderType) {
    _orderType = orderType;
    notifyListeners();
  }

  @override
  void reset() {
    _detailsRequested = false;
    action = DexAction.none;
  }

  @override
  void resetOnLogOut() {
    reset();
  }

  void clearDexParams() {
    _fromCurrency = '';
    _fromAmount = '';
    _toCurrency = '';
    _toAmount = '';
    _orderType = '';
  }
}

enum DexAction {
  tradingDetails,
  none,
}
