import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_state.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/shared/swap/swap_quote.dart';
import 'package:web_dex/views/swap/common/swap_format.dart';
import 'package:web_dex/views/swap/common/swap_palette.dart';
import 'package:web_dex/views/swap/common/swap_widgets.dart';

/// From how many seconds before expiry the countdown shows.
const _countdownFrom = Duration(seconds: 20);

/// The selected option in one line: the minimum, the total cost, the time,
/// and why it was chosen.
class SwapQuoteStrip extends StatefulWidget {
  const SwapQuoteStrip({
    required this.state,
    required this.onCompare,
    this.now = DateTime.now,
    super.key,
  });

  final UnifiedSwapState state;
  final VoidCallback onCompare;
  final DateTime Function() now;

  @override
  State<SwapQuoteStrip> createState() => _SwapQuoteStripState();
}

class _SwapQuoteStripState extends State<SwapQuoteStrip> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final quote = widget.state.selectedQuote;
      if (quote == null) return;
      final left = quote.expiresAt.difference(widget.now());
      // Repaint only while the countdown is visible.
      if (left <= _countdownFrom && !left.isNegative) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final quote = state.selectedQuote;
    if (quote == null) return const SizedBox.shrink();
    final palette = SwapPalette.of(context);
    final ticker = SwapFormat.ticker(quote.to);
    final total = quote.pricing.totalCostUsd;

    final facts = [
      (
        LocaleKeys.swapMinimumReceived.tr(),
        SwapFormat.tokens(
          quote.guaranteedReceive,
          ticker,
          rounding: SwapRounding.down,
        ),
      ),
      (
        LocaleKeys.swapTotalCost.tr(),
        total == null || !quote.pricing.isComplete
            ? LocaleKeys.swapCostIncomplete.tr()
            : SwapFormat.usd(total, rounding: SwapRounding.up),
      ),
      (
        LocaleKeys.swapEstimatedTime.tr(),
        SwapFormat.duration(quote.estimatedDuration),
      ),
    ];

    return Semantics(
      container: true,
      label: LocaleKeys.swapA11yQuoteSummary.tr(),
      child: Container(
        margin: const EdgeInsets.only(top: 14),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: palette.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: palette.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final children = [
                  for (final (label, value) in facts)
                    MergeSemantics(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(label, style: SwapText.small(context)),
                          const SizedBox(height: 4),
                          Text(
                            value,
                            style: SwapText.strong(
                              context,
                            ).copyWith(fontSize: 14),
                          ),
                        ],
                      ),
                    ),
                ];
                final scale = MediaQuery.textScalerOf(context).scale(1);
                if (constraints.maxWidth / scale < 300) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final child in children) ...[
                        child,
                        if (child != children.last) const SizedBox(height: 10),
                      ],
                    ],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final child in children) ...[
                      Expanded(child: child),
                      if (child != children.last) const SizedBox(width: 10),
                    ],
                  ],
                );
              },
            ),
            const SizedBox(height: 10),
            Divider(height: 1, thickness: 1, color: palette.border),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(child: _badges(context, quote)),
                SwapLinkButton(
                  // An aggregator route may have a faster alternative, priced
                  // only once the comparison opens.
                  label:
                      (state.quotes?.hasAlternatives ?? false) ||
                          quote.source == SwapLiquiditySource.routed
                      ? LocaleKeys.swapCompareOptions.tr()
                      : LocaleKeys.swapDetails.tr(),
                  onPressed: widget.onCompare,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _badges(BuildContext context, SwapQuote quote) {
    final state = widget.state;
    final quotes = state.quotes;
    final badges = <Widget>[];
    String? note;

    final isBest =
        quotes != null &&
        quotes.canClaimBestNetReturn &&
        quotes.ranked.first.id == quote.id;
    if (!quote.isRankable && state.manuallySelected) {
      badges.add(
        SwapBadge(
          label: LocaleKeys.swapManuallySelected.tr(),
          tone: SwapTone.warning,
        ),
      );
    } else if (isBest) {
      badges.add(
        SwapBadge(
          label: LocaleKeys.swapBestNetReturn.tr(),
          tone: SwapTone.brand,
        ),
      );
      note = LocaleKeys.swapBestNetReturnNote.tr();
    } else if (quote.order == SwapQuoteOrder.fastest) {
      badges.add(
        SwapBadge(
          label: LocaleKeys.swapFastestSelected.tr(),
          tone: SwapTone.info,
        ),
      );
    } else if (quotes?.hasAlternatives ?? false) {
      badges.add(
        SwapBadge(
          label: LocaleKeys.swapOptionSelectedBadge.tr(),
          tone: SwapTone.info,
        ),
      );
    }

    if (state.evaluation == SwapEvaluationStatus.expired) {
      badges.add(
        SwapBadge(
          label: LocaleKeys.swapReviewExpiredBadge.tr(),
          tone: SwapTone.warning,
          icon: Icons.timer_outlined,
        ),
      );
    } else {
      final left = quote.expiresAt.difference(widget.now());
      if (left <= _countdownFrom && !left.isNegative) {
        badges.add(
          SwapBadge(
            label: LocaleKeys.swapExpiresIn.tr(args: ['${left.inSeconds}']),
            tone: SwapTone.warning,
            icon: Icons.timer_outlined,
          ),
        );
      }
    }

    if (badges.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(spacing: 6, runSpacing: 6, children: badges),
        if (note != null) ...[
          const SizedBox(height: 5),
          Text(note, style: SwapText.small(context)),
        ],
      ],
    );
  }
}

/// "1 ETH ≈ 3,219.42 USDC" — tap to flip it round.
class SwapRateLine extends StatefulWidget {
  const SwapRateLine({required this.quote, super.key});

  final SwapQuote quote;

  @override
  State<SwapRateLine> createState() => _SwapRateLineState();
}

class _SwapRateLineState extends State<SwapRateLine> {
  bool _inverted = false;

  @override
  Widget build(BuildContext context) {
    final quote = widget.quote;
    final rate = quote.expectedRate;
    if (rate == null || rate <= Decimal.zero) return const SizedBox.shrink();
    final from = SwapFormat.ticker(quote.from);
    final to = SwapFormat.ticker(quote.to);
    final inverse = (Decimal.one / rate).toDecimal(
      scaleOnInfinitePrecision: 18,
    );
    final text = _inverted
        ? LocaleKeys.swapRate.tr(args: [to, SwapFormat.amount(inverse), from])
        : LocaleKeys.swapRate.tr(args: [from, SwapFormat.amount(rate), to]);
    final palette = SwapPalette.of(context);
    return Align(
      alignment: Alignment.centerLeft,
      child: Semantics(
        button: true,
        label: '$text. ${LocaleKeys.swapRateInvert.tr()}',
        excludeSemantics: true,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => setState(() => _inverted = !_inverted),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 40),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      text,
                      style: SwapText.small(
                        context,
                      ).copyWith(color: palette.textSecondary),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Icon(
                    Icons.sync_alt_rounded,
                    size: 14,
                    color: palette.textTertiary,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
