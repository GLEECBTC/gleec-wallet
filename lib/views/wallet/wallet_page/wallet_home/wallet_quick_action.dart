import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';

/// The wallet's four everyday verbs, one tap from home.
enum WalletQuickAction {
  receive(Icons.south_west_rounded),
  send(Icons.north_east_rounded),
  swap(Icons.swap_horiz_rounded),
  buy(Icons.add_rounded);

  const WalletQuickAction(this.icon);

  final IconData icon;

  String get label => switch (this) {
    WalletQuickAction.receive => LocaleKeys.receive.tr(),
    WalletQuickAction.send => LocaleKeys.send.tr(),
    WalletQuickAction.swap => LocaleKeys.swap.tr(),
    WalletQuickAction.buy => LocaleKeys.buy.tr(),
  };

  Key get key => Key('wallet-quick-action-$name');
}
