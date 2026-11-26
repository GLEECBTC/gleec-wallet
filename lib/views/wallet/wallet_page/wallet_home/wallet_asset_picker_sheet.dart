import 'package:decimal/decimal.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:web_dex/bloc/coins_bloc/coins_bloc.dart';
import 'package:web_dex/bloc/settings/settings_bloc.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/model/coin.dart';
import 'package:web_dex/model/coin_utils.dart';
import 'package:web_dex/router/state/wallet_state.dart';
import 'package:web_dex/shared/utils/extensions/sdk_extensions.dart';
import 'package:web_dex/views/swap/common/swap_palette.dart';
import 'package:web_dex/views/wallet/wallet_page/wallet_home/wallet_asset_row.dart';
import 'package:web_dex/views/wallet/wallet_page/wallet_home/wallet_home_style.dart';
import 'package:web_dex/views/wallet/wallet_page/wallet_home/wallet_quick_action.dart';

/// The choice made in [showWalletAssetPicker]: an asset, or, when there was
/// nothing to send, another action to take instead.
typedef WalletAssetPick = ({Coin? coin, WalletQuickAction? instead});

/// Asks which asset to send or receive. Sending offers only what holds a
/// balance; with nothing to send, the sheet says so and offers Receive or Buy.
Future<WalletAssetPick?> showWalletAssetPicker(
  BuildContext context, {
  required CoinQuickAction purpose,
}) {
  final palette = SwapPalette.of(context);
  return showModalBottomSheet<WalletAssetPick>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    constraints: walletSheetConstraints,
    backgroundColor: palette.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => WalletAssetPickerSheet(purpose: purpose),
  );
}

/// The wallet's assets that can be used for [purpose], best first.
List<Coin> walletAssetsFor(
  CoinQuickAction purpose, {
  required Iterable<Coin> walletCoins,
  required KomodoDefiSdk sdk,
  required bool includeTestCoins,
}) {
  final usable = walletCoins.where((coin) {
    if (!includeTestCoins && coin.isTestCoin) return false;
    return switch (purpose) {
      CoinQuickAction.receive => coin.isActive || coin.isActivating,
      CoinQuickAction.send =>
        coin.isActive &&
            (sdk.balances.lastKnown(coin.id)?.spendable ?? Decimal.zero) >
                Decimal.zero,
    };
  }).toList();
  return sortByPriorityAndBalance(usable, sdk);
}

class WalletAssetPickerSheet extends StatefulWidget {
  const WalletAssetPickerSheet({required this.purpose, super.key});

  final CoinQuickAction purpose;

  /// From this many assets the sheet offers a search field.
  static const searchFrom = 7;

  @override
  State<WalletAssetPickerSheet> createState() => _WalletAssetPickerSheetState();
}

class _WalletAssetPickerSheetState extends State<WalletAssetPickerSheet> {
  String _phrase = '';

  @override
  Widget build(BuildContext context) {
    final sdk = context.sdk;
    final includeTestCoins = context.select(
      (SettingsBloc bloc) => bloc.state.testCoinsEnabled,
    );
    final coins = context.select(
      (CoinsBloc bloc) => bloc.state.walletCoins.values.toList(),
    );
    final candidates = walletAssetsFor(
      widget.purpose,
      walletCoins: coins,
      sdk: sdk,
      includeTestCoins: includeTestCoins,
    );
    final shown = filterCoinsByPhrase(candidates, _phrase).toList();
    final isSend = widget.purpose == CoinQuickAction.send;
    final height = MediaQuery.sizeOf(context).height * 0.86;

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: height),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _Handle(),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Semantics(
                  header: true,
                  child: Text(
                    isSend ? LocaleKeys.send.tr() : LocaleKeys.receive.tr(),
                    style: SwapText.heading(context),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  LocaleKeys.walletHomeChooseAsset.tr(),
                  style: WalletHomeText.caption(context),
                ),
              ],
            ),
          ),
          if (candidates.length >= WalletAssetPickerSheet.searchFrom)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: _SearchField(
                onChanged: (value) =>
                    setState(() => _phrase = value.trim().toLowerCase()),
              ),
            ),
          if (candidates.isEmpty)
            isSend ? const _NothingToSend() : const _NoAssets()
          else
            Flexible(
              child: shown.isEmpty
                  ? _NoMatch()
                  : ListView.builder(
                      shrinkWrap: true,
                      padding: const EdgeInsets.fromLTRB(4, 8, 4, 16),
                      itemCount: shown.length,
                      itemBuilder: (context, index) {
                        final coin = shown[index];
                        return WalletAssetRow(
                          key: Key(
                            'wallet-asset-picker-${coin.abbr.toLowerCase()}',
                          ),
                          coin: coin,
                          showDivider: index > 0,
                          borderRadius: BorderRadius.circular(16),
                          onTap: () => Navigator.of(
                            context,
                          ).pop<WalletAssetPick>((coin: coin, instead: null)),
                        );
                      },
                    ),
            ),
        ],
      ),
    );
  }
}

class _Handle extends StatelessWidget {
  const _Handle();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        margin: const EdgeInsets.only(top: 10, bottom: 6),
        width: 40,
        height: 4,
        decoration: BoxDecoration(
          color: SwapPalette.of(context).borderStrong,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({required this.onChanged});

  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return WalletHomeSearchField(
      key: const Key('wallet-asset-picker-search'),
      onChanged: onChanged,
      autofocus: false,
    );
  }
}

/// A rounded search field on the palette's raised surface.
class WalletHomeSearchField extends StatelessWidget {
  const WalletHomeSearchField({
    required this.onChanged,
    this.controller,
    this.focusNode,
    this.autofocus = false,
    this.fieldKey,
    super.key,
  });

  final ValueChanged<String> onChanged;
  final TextEditingController? controller;
  final FocusNode? focusNode;
  final bool autofocus;
  final Key? fieldKey;

  @override
  Widget build(BuildContext context) {
    final palette = SwapPalette.of(context);
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(color: palette.border),
    );
    return TextField(
      key: fieldKey,
      controller: controller,
      focusNode: focusNode,
      autofocus: autofocus,
      autocorrect: false,
      textInputAction: TextInputAction.search,
      onChanged: onChanged,
      style: WalletHomeText.title(context)
          .copyWith(fontWeight: FontWeight.w600),
      decoration: InputDecoration(
        isDense: true,
        filled: true,
        fillColor: palette.surfaceRaised,
        hintText: LocaleKeys.searchAssets.tr(),
        hintStyle: WalletHomeText.detail(context).copyWith(fontSize: 15),
        prefixIcon: Icon(
          Icons.search_rounded,
          size: 20,
          color: palette.textTertiary,
        ),
        contentPadding: const EdgeInsets.symmetric(vertical: 12),
        border: border,
        enabledBorder: border,
        focusedBorder: border.copyWith(
          borderSide: BorderSide(color: palette.brand, width: 1.5),
        ),
      ),
    );
  }
}

class _NothingToSend extends StatelessWidget {
  const _NothingToSend();

  @override
  Widget build(BuildContext context) {
    final palette = SwapPalette.of(context);
    void instead(WalletQuickAction action) =>
        Navigator.of(context)
            .pop<WalletAssetPick>((coin: null, instead: action));
    return Padding(
      key: const Key('wallet-asset-picker-nothing-to-send'),
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: palette.selected,
              shape: BoxShape.circle,
            ),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Icon(
                Icons.account_balance_wallet_outlined,
                color: palette.brandHover,
                size: 28,
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            LocaleKeys.walletHomeNothingToSend.tr(),
            style: SwapText.strong(context),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          Text(
            LocaleKeys.walletHomeNothingToSendHint.tr(),
            style: SwapText.body(context),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          Row(
            spacing: 12,
            children: [
              for (final action in const [
                WalletQuickAction.receive,
                WalletQuickAction.buy,
              ])
                Expanded(
                  child: _SheetButton(
                    key: Key('wallet-asset-picker-instead-${action.name}'),
                    action: action,
                    primary: action == WalletQuickAction.receive,
                    onPressed: () => instead(action),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SheetButton extends StatelessWidget {
  const _SheetButton({
    required this.action,
    required this.primary,
    required this.onPressed,
    super.key,
  });

  final WalletQuickAction action;
  final bool primary;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final palette = SwapPalette.of(context);
    final style = ButtonStyle(
      minimumSize: const WidgetStatePropertyAll(Size.fromHeight(48)),
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      backgroundColor: WidgetStatePropertyAll(
        primary ? palette.brand : palette.surfaceHigh,
      ),
      foregroundColor: WidgetStatePropertyAll(
        primary ? palette.onBrand : palette.text,
      ),
      textStyle: WidgetStatePropertyAll(SwapText.strong(context)),
    );
    return TextButton.icon(
      style: style,
      onPressed: onPressed,
      icon: Icon(action.icon, size: 18),
      label: Text(action.label),
    );
  }
}

class _NoAssets extends StatelessWidget {
  const _NoAssets();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
      child: Text(
        LocaleKeys.walletHomeNoAssets.tr(),
        style: SwapText.body(context),
        textAlign: TextAlign.center,
      ),
    );
  }
}

class _NoMatch extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
      child: Text(
        LocaleKeys.walletPageNoSuchAsset.tr(),
        style: SwapText.body(context),
        textAlign: TextAlign.center,
      ),
    );
  }
}
