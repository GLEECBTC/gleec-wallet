import 'package:flutter/material.dart';
import 'package:web_dex/model/trading_entity_id.dart';
import 'package:web_dex/router/state/menu_state_interface.dart';

class DexState extends ChangeNotifier implements IResettableOnLogout {
  DexState()
    : _action = DexAction.none,
      _entityKind = DexTradingEntityKind.swap,
      _uuid = '',
      _fromCurrency = '',
      _fromAmount = '',
      _toCurrency = '',
      _toAmount = '',
      _orderType = '';

  DexAction _action;
  DexTradingEntityKind _entityKind;
  String _uuid;

  String _fromCurrency;
  String _fromAmount;
  String _toCurrency;
  String _toAmount;
  String _orderType;

  set action(DexAction action) {
    final nextAction =
        action == DexAction.tradingDetails &&
            normalizeTradingEntityUuid(_uuid) == null
        ? DexAction.none
        : action;
    if (_action == nextAction) {
      return;
    }

    _action = nextAction;
    notifyListeners();
  }

  bool setDetailsAction(
    String uuid, {
    DexTradingEntityKind kind = DexTradingEntityKind.swap,
  }) {
    final normalizedUuid = normalizeTradingEntityUuid(uuid);
    if (normalizedUuid == null) {
      _action = DexAction.none;
      _uuid = '';
      _entityKind = DexTradingEntityKind.swap;
      notifyListeners();
      return false;
    }
    _uuid = normalizedUuid;
    _entityKind = kind;
    _action = DexAction.tradingDetails;
    notifyListeners();
    return true;
  }

  /// Replaces every Advanced route field atomically. This prevents listeners
  /// from briefly fetching an old UUID with a newly parsed entity kind.
  void replaceRoute({
    required DexAction action,
    required DexTradingEntityKind entityKind,
    required String uuid,
    required String fromCurrency,
    required String fromAmount,
    required String toCurrency,
    required String toAmount,
    required String orderType,
  }) {
    final normalizedUuid = action == DexAction.tradingDetails
        ? normalizeTradingEntityUuid(uuid)
        : null;
    _action = action == DexAction.tradingDetails && normalizedUuid == null
        ? DexAction.none
        : action;
    _entityKind = normalizedUuid == null
        ? DexTradingEntityKind.swap
        : entityKind;
    _uuid = normalizedUuid ?? '';
    _fromCurrency = fromCurrency;
    _fromAmount = fromAmount;
    _toCurrency = toCurrency;
    _toAmount = toAmount;
    _orderType = orderType;
    notifyListeners();
  }

  DexAction get action => _action;

  bool get isTradingDetails => _action == DexAction.tradingDetails;

  DexTradingEntityKind get entityKind => _entityKind;

  set entityKind(DexTradingEntityKind value) {
    if (_entityKind == value) return;
    _entityKind = value;
    notifyListeners();
  }

  set uuid(String uuid) {
    if (uuid.isEmpty) {
      _uuid = '';
    } else {
      final normalizedUuid = normalizeTradingEntityUuid(uuid);
      if (normalizedUuid == null) {
        _uuid = '';
        _action = DexAction.none;
        _entityKind = DexTradingEntityKind.swap;
      } else {
        _uuid = normalizedUuid;
      }
    }
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
    _action = DexAction.none;
    _uuid = '';
    _entityKind = DexTradingEntityKind.swap;
    clearDexParams();
    notifyListeners();
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

  /// Seeds validated, legacy form hints before the Advanced form is built.
  /// The form consumes and clears these values once, so they never become
  /// durable route or wallet state.
  void setLegacyFormHints({
    String? fromCurrency,
    String? fromAmount,
    String? toCurrency,
  }) {
    _fromCurrency = fromCurrency ?? '';
    _fromAmount = fromAmount ?? '';
    _toCurrency = toCurrency ?? '';
    _toAmount = '';
    _orderType = 'maker';
  }
}

enum DexAction { tradingDetails, none }

/// The durable URL identity for an Advanced trading detail entity.
///
/// A UUID is not self-describing: an order and a swap require different
/// repositories and screens. Keeping this in router state prevents a cold
/// deep link from depending on whichever tab happened to be selected.
enum DexTradingEntityKind { swap, order }
