import 'dart:math' as math;

import 'package:decimal/decimal.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_state.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/views/swap/common/swap_format.dart';
import 'package:web_dex/views/swap/common/swap_palette.dart';
import 'package:web_dex/views/swap/common/swap_widgets.dart';
import 'package:web_dex/views/swap/motion/swap_motion.dart';

part 'swap_amount_controls.dart';
part 'swap_receive_card.dart';

/// A stable card with a full-width asset identity above the amount.
/// Addresses belong to review; giving them a footer here crowded the keyboard.
class _AmountCardFrame extends StatelessWidget {
  const _AmountCardFrame({
    required this.label,
    required this.amount,
    required this.assetPill,
    this.topTrailing,
    this.hasError = false,
    this.focused = false,
  });

  final String label;
  final Widget amount;
  final Widget assetPill;
  final Widget? topTrailing;
  final bool hasError;
  final bool focused;

  @override
  Widget build(BuildContext context) {
    final palette = SwapPalette.of(context);
    final compact = SwapGeometry.isCompact(context);
    final keyboard = MediaQuery.viewInsetsOf(context).bottom > 0;
    final inset = compact ? 12.0 : 18.0;
    final gap = keyboard ? 4.0 : 8.0;
    return Semantics(
      container: true,
      label: label,
      child: AnimatedContainer(
        duration: SwapMotion.of(context, SwapMotion.selection),
        decoration: BoxDecoration(
          color: palette.surfaceRaised,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: hasError
                ? palette.danger
                : focused
                ? palette.brand
                : palette.controlBorder,
          ),
        ),
        padding: EdgeInsets.all(inset),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    style: SwapText.small(context).copyWith(
                      color: palette.textSecondary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (topTrailing != null)
                  Flexible(
                    child: Align(
                      alignment: AlignmentDirectional.centerEnd,
                      heightFactor: 1,
                      child: topTrailing!,
                    ),
                  ),
              ],
            ),
            SizedBox(height: gap),
            assetPill,
            SizedBox(height: gap),
            amount,
          ],
        ),
      ),
    );
  }
}

/// The pay side: the editable amount, its dollar value, the balance and Max.
class SwapPayCard extends StatefulWidget {
  const SwapPayCard({
    required this.state,
    required this.network,
    required this.tokenAmount,
    required this.usdPrice,
    required this.onAmountChanged,
    required this.onModeToggled,
    required this.onMax,
    required this.onPickAsset,
    super.key,
  });

  final UnifiedSwapState state;

  /// The pay asset's network, for the pill.
  final String? network;

  /// What the field amounts to in pay-asset units.
  final Decimal? tokenAmount;

  /// The pay asset's USD price, when known.
  final Decimal? usdPrice;

  final ValueChanged<String> onAmountChanged;
  final VoidCallback onModeToggled;
  final VoidCallback onMax;
  final VoidCallback onPickAsset;

  @override
  State<SwapPayCard> createState() => _SwapPayCardState();
}

class _SwapPayCardState extends State<SwapPayCard> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.state.inputText,
  );
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() => setState(() {}));
  }

  @override
  void didUpdateWidget(covariant SwapPayCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The bloc owns the text: Max, the fiat toggle and a reset rewrite it.
    // Only overwrite the field when it disagrees, so typing never jumps.
    final text = widget.state.inputText;
    if (text != _controller.text) {
      _controller.value = TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  static const _amountIssues = {
    SwapFormIssue.amountMalformed,
    SwapFormIssue.amountZero,
    SwapFormIssue.tooManyDecimals,
    SwapFormIssue.insufficient,
    SwapFormIssue.insufficientForFees,
    SwapFormIssue.fiatUnavailable,
  };

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final palette = SwapPalette.of(context);
    final pay = state.pay;
    final fiat = state.amountMode == SwapAmountMode.fiat;
    final ticker = pay == null ? '' : SwapFormat.ticker(pay);
    final balance = state.balance;
    final locked = state.startInDoubt;

    // While Max asks, the whole balance shown may still change.
    final amountStyle = state.checkingMax
        ? SwapText.amount(context).copyWith(color: palette.textSecondary)
        : SwapText.amount(context);
    final field = TextField(
      key: const Key('swap-amount'),
      controller: _controller,
      focusNode: _focus,
      onChanged: widget.onAmountChanged,
      // A phone's decimal pad has no key to put it away: a tap anywhere else
      // does, as dragging the form does.
      onTapOutside: (_) => _focus.unfocus(),
      enabled: pay != null && !locked,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [
        _DecimalInputFormatter(
          // The form checks the asset's own decimals when it knows them.
          maxDecimals: fiat ? 2 : pay?.chainId.decimals ?? 18,
        ),
      ],
      style: amountStyle,
      cursorColor: palette.brand,
      decoration: InputDecoration(
        // Uncollapsed at standard density, so on every platform the field
        // itself is at least 48 dp tall with its text centred.
        contentPadding: EdgeInsets.zero,
        visualDensity: VisualDensity.standard,
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        disabledBorder: InputBorder.none,
        errorBorder: InputBorder.none,
        filled: false,
        hintText: '0',
        hintStyle: amountStyle.copyWith(color: palette.textTertiary),
        prefixText: fiat ? r'$' : null,
        prefixStyle: amountStyle,
        semanticCounterText: '',
      ),
    );

    final amount = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        MergeSemantics(
          child: Semantics(
            label: LocaleKeys.swapAmountToPay.tr(),
            child: field,
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(child: _secondaryLine(context, ticker)),
            if (pay != null && balance != null)
              SwapLinkButton(
                label: LocaleKeys.max.tr(),
                onPressed: locked ? null : widget.onMax,
                busy: state.checkingMax,
              ),
          ],
        ),
      ],
    );

    return _AmountCardFrame(
      label: LocaleKeys.swapYouPay.tr(),
      hasError: _amountIssues.contains(state.issue),
      focused: _focus.hasFocus,
      topTrailing: balance == null || pay == null
          ? null
          : Text(
              LocaleKeys.swapBalanceValue.tr(
                args: [
                  SwapFormat.tokens(
                    balance,
                    ticker,
                    rounding: SwapRounding.down,
                  ),
                ],
              ),
              style: SwapText.small(context)
                  .copyWith(color: palette.textSecondary),
              textAlign: TextAlign.right,
            ),
      amount: amount,
      assetPill: SwapAssetPill(
        asset: pay,
        network: widget.network,
        onTap: widget.onPickAsset,
        semanticLabel: LocaleKeys.swapYouPay.tr(),
      ),
    );
  }

  Widget _secondaryLine(BuildContext context, String ticker) {
    final state = widget.state;
    final price = widget.usdPrice;
    final palette = SwapPalette.of(context);
    final toggle = state.startInDoubt ? null : widget.onModeToggled;
    if (state.pay == null) {
      return Text('—', style: SwapText.small(context));
    }
    final fiat = state.amountMode == SwapAmountMode.fiat;
    if (price == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            LocaleKeys.swapPriceUnavailable.tr(),
            style: SwapText.small(context),
          ),
          if (fiat)
            SwapLinkButton(
              label: LocaleKeys.swapEnterInToken.tr(args: [ticker]),
              onPressed: widget.onModeToggled,
            ),
        ],
      );
    }
    final tokenAmount = widget.tokenAmount ?? Decimal.zero;
    final text = fiat
        ? LocaleKeys.swapApproxToken.tr(
            args: [SwapFormat.amount(tokenAmount), ticker],
          )
        : SwapFormat.usd(tokenAmount * price);
    final label = fiat
        ? LocaleKeys.swapEnterInToken.tr(args: [ticker])
        : LocaleKeys.swapEnterInUsd.tr();
    return SwapButtonSemantics(
      label: '$text. $label',
      onTap: toggle,
      child: Tooltip(
        message: label,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: toggle,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(child: Text(text, style: SwapText.small(context))),
                const SizedBox(width: 6),
                Icon(
                  Icons.swap_vert_rounded,
                  size: 16,
                  color: palette.brandHover,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The price impact from which the form warns: 5%.
final swapHighImpact = Decimal.parse('0.05');

/// The share of a swap's value going to fees from which the form warns: 10%,
/// the threshold LI.FI's own widget uses.
final swapHighFeeShare = Decimal.parse('0.10');
