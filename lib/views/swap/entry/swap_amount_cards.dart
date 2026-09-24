import 'package:decimal/decimal.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_state.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/shared/utils/utils.dart';
import 'package:web_dex/views/swap/common/swap_format.dart';
import 'package:web_dex/views/swap/common/swap_palette.dart';
import 'package:web_dex/views/swap/common/swap_widgets.dart';

part 'swap_amount_controls.dart';

/// The frame both amount cards share: a label row, the amount beside the
/// asset pill, and an address footer.
class _AmountCardFrame extends StatelessWidget {
  const _AmountCardFrame({
    required this.label,
    required this.amount,
    required this.assetPill,
    required this.footer,
    this.topTrailing,
    this.hasError = false,
    this.focused = false,
  });

  final String label;
  final Widget amount;
  final Widget assetPill;
  final Widget footer;
  final Widget? topTrailing;
  final bool hasError;
  final bool focused;

  @override
  Widget build(BuildContext context) {
    final palette = SwapPalette.of(context);
    final borderColor = hasError
        ? palette.danger
        : focused
        ? palette.brand
        : palette.controlBorder;
    return Semantics(
      container: true,
      label: label,
      child: AnimatedContainer(
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          color: palette.surfaceRaised,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: borderColor),
          boxShadow: focused && !hasError
              ? [
                  BoxShadow(
                    color: palette.brand.withValues(alpha: 0.28),
                    spreadRadius: 3,
                  ),
                ]
              : null,
        ),
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 4),
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
                if (topTrailing != null) Flexible(child: topTrailing!),
              ],
            ),
            const SizedBox(height: 16),
            LayoutBuilder(
              builder: (context, constraints) {
                final scale = MediaQuery.textScalerOf(context).scale(1);
                final half = constraints.maxWidth * 0.5;
                final pill = 190 * scale;
                // Larger text must not cut the pill short: it moves under
                // the amount once half the row can no longer hold it.
                if (constraints.maxWidth / scale < 240 ||
                    (scale > 1 && half < pill)) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [amount, const SizedBox(height: 14), assetPill],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(child: amount),
                    const SizedBox(width: 14),
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: half < pill ? half : pill,
                      ),
                      child: assetPill,
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 16),
            Divider(height: 1, thickness: 1, color: palette.border),
            footer,
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
    final address = state.selectedQuote?.fromAddress ?? state.payAddress;

    final amountStyle = SwapText.amount(context);
    final field = TextField(
      key: const Key('swap-amount'),
      controller: _controller,
      focusNode: _focus,
      onChanged: widget.onAmountChanged,
      enabled: pay != null,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [_DecimalInputFormatter(maxDecimals: fiat ? 2 : 18)],
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
        _secondaryLine(context, ticker),
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
              style: SwapText.small(
                context,
              ).copyWith(color: palette.textSecondary),
              textAlign: TextAlign.right,
            ),
      amount: amount,
      assetPill: SwapAssetPill(
        asset: pay,
        network: widget.network,
        onTap: widget.onPickAsset,
        semanticLabel: LocaleKeys.swapYouPay.tr(),
      ),
      footer: Row(
        children: [
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: _AddressFooterButton(
                prefix: (a) => LocaleKeys.swapFromAddress.tr(args: [a]),
                address: address,
              ),
            ),
          ),
          if (pay != null && balance != null)
            SwapLinkButton(label: LocaleKeys.max.tr(), onPressed: widget.onMax),
        ],
      ),
    );
  }

  Widget _secondaryLine(BuildContext context, String ticker) {
    final state = widget.state;
    final price = widget.usdPrice;
    final palette = SwapPalette.of(context);
    if (state.pay == null) {
      return Text(r'$0.00', style: SwapText.small(context));
    }
    if (price == null) {
      return Text(
        LocaleKeys.swapPriceUnavailable.tr(),
        style: SwapText.small(context),
      );
    }
    final fiat = state.amountMode == SwapAmountMode.fiat;
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
      onTap: widget.onModeToggled,
      child: Tooltip(
        message: label,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: widget.onModeToggled,
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

/// The receive side: what the selected option is expected to deliver.
class SwapReceiveCard extends StatelessWidget {
  const SwapReceiveCard({
    required this.state,
    required this.network,
    required this.onPickAsset,
    super.key,
  });

  final UnifiedSwapState state;
  final String? network;
  final VoidCallback onPickAsset;

  @override
  Widget build(BuildContext context) {
    final palette = SwapPalette.of(context);
    final quote = state.selectedQuote;
    final receive = state.receive;
    final checking =
        state.evaluation == SwapEvaluationStatus.checking && quote == null;
    final address = quote?.toAddress ?? state.receiveAddress;

    final Widget amountText;
    if (checking) {
      amountText = const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: SwapSkeleton(height: 24, widthFactor: 0.6),
      );
    } else {
      final value = quote?.expectedReceive;
      amountText = ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Align(
          alignment: Alignment.centerLeft,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value == null
                  ? '0'
                  : SwapFormat.amount(value, rounding: SwapRounding.down),
              style: SwapText.amount(context).copyWith(
                color: value == null ? palette.textTertiary : palette.text,
              ),
              maxLines: 1,
            ),
          ),
        ),
      );
    }

    return _AmountCardFrame(
      label: LocaleKeys.swapYouReceive.tr(),
      amount: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [amountText, const SizedBox(height: 6), _fiatLine(context)],
      ),
      assetPill: SwapAssetPill(
        asset: receive,
        network: network,
        onTap: onPickAsset,
        semanticLabel: LocaleKeys.swapYouReceive.tr(),
      ),
      footer: Align(
        alignment: Alignment.centerLeft,
        child: _AddressFooterButton(
          prefix: (a) => LocaleKeys.swapToAddress.tr(args: [a]),
          address: address,
        ),
      ),
    );
  }

  Widget _fiatLine(BuildContext context) {
    final palette = SwapPalette.of(context);
    final quote = state.selectedQuote;
    if (quote == null) {
      return Text(r'$0.00', style: SwapText.small(context));
    }
    final expected = quote.pricing.expectedUsd;
    if (expected == null) {
      return Text(
        LocaleKeys.swapPriceUnavailable.tr(),
        style: SwapText.small(context),
      );
    }
    final impact = quote.pricing.priceImpact;
    final high = impact != null && impact >= swapHighImpact;
    return Wrap(
      spacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          SwapFormat.usd(expected, rounding: SwapRounding.down),
          style: SwapText.small(context),
        ),
        if (impact != null)
          Text(
            LocaleKeys.swapVsMarket.tr(
              args: [
                '${impact > Decimal.zero ? '−' : '+'}'
                    '${SwapFormat.percent(impact.abs())}',
              ],
            ),
            style: SwapText.small(context).copyWith(
              color: high ? palette.warning : palette.textTertiary,
              fontWeight: high ? FontWeight.w700 : null,
            ),
          ),
      ],
    );
  }
}

/// The price impact from which the form warns: 5%.
final swapHighImpact = Decimal.parse('0.05');
