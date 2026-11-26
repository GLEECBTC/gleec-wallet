import 'package:flutter/material.dart';
import 'package:web_dex/router/state/menu_state_interface.dart';

class WalletState extends ChangeNotifier implements IResettableOnLogout {
  WalletState()
      : _selectedCoin = '',
        _action = '';

  String _selectedCoin;
  String _action;

  String get selectedCoin => _selectedCoin;
  set selectedCoin(String abbrCoin) {
    if (_selectedCoin == abbrCoin) {
      return;
    }

    _selectedCoin = abbrCoin;
    action = '';
    notifyListeners();
  }

  set action(String action) {
    if (_action == action) {
      return;
    }
    _action = action;
    _selectedCoin = '';
    notifyListeners();
  }

  String get action => _action;

  CoinsManagerAction get coinsManagerAction {
    return coinsManagerRouteAction.toEnum(_action);
  }

  CoinQuickActionRequest? _quickAction;

  /// Opens [abbrCoin]'s page, with [quickAction] started once it can be.
  /// The action is not part of the route: a reload opens the page alone.
  void openCoin(String abbrCoin, {CoinQuickAction? quickAction}) {
    _quickAction = quickAction == null
        ? null
        : CoinQuickActionRequest(coin: abbrCoin, action: quickAction);
    selectedCoin = abbrCoin;
  }

  /// The action asked for with [openCoin] as [abbrCoin]'s page opens, once.
  CoinQuickActionRequest? takeQuickAction(String abbrCoin) {
    final request = _quickAction;
    _quickAction = null;
    return request?.coin == abbrCoin ? request : null;
  }

  @override
  void reset() {
    _quickAction = null;
    selectedCoin = '';
    action = '';
  }

  @override
  void resetOnLogOut() {
    _quickAction = null;
    selectedCoin = '';
    action = '';
  }
}

/// What the wallet home's Send and Receive ask a coin's page to start.
enum CoinQuickAction { send, receive }

/// A coin page's pending quick action. The page's buttons start it the first
/// time they can, so coming back to the page does not start it again.
class CoinQuickActionRequest {
  CoinQuickActionRequest({required this.coin, required this.action});

  final String coin;
  final CoinQuickAction action;
  bool _started = false;

  /// Whether [action] is this request's and still waiting; true only once.
  bool start(CoinQuickAction action) {
    if (_started || action != this.action) return false;
    _started = true;
    return true;
  }
}

class CoinsManagerRouteAction {
  final String addAssets = 'add-assets';
  final String removeAssets = 'remove-assets';
  final String none = '';

  CoinsManagerAction toEnum(String action) {
    if (action == addAssets) return CoinsManagerAction.add;
    if (action == removeAssets) return CoinsManagerAction.remove;
    return CoinsManagerAction.none;
  }
}

final CoinsManagerRouteAction coinsManagerRouteAction =
    CoinsManagerRouteAction();

enum CoinsManagerAction { add, remove, none }
