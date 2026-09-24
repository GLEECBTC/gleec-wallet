import 'package:decimal/decimal.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_bloc.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_event.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_state.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/shared/swap/swap_quote.dart';
import 'package:web_dex/shared/swap/unified_swap_repository.dart';
import 'package:web_dex/views/swap/common/swap_format.dart';
import 'package:web_dex/views/swap/common/swap_palette.dart';
import 'package:web_dex/views/swap/common/swap_sheet.dart';
import 'package:web_dex/views/swap/common/swap_widgets.dart';

/// Opens the options comparison over [bloc]'s live evaluation.
Future<void> showSwapOptionsSheet(BuildContext context, UnifiedSwapBloc bloc) {
  return showSwapSheet<void>(
    context: context,
    label: LocaleKeys.swapOptionsTitle.tr(),
    builder: (_) =>
        BlocProvider.value(value: bloc, child: const SwapOptionsSheet()),
  );
}

/// Every option on offer, compared on what each actually promises.
class SwapOptionsSheet extends StatefulWidget {
  const SwapOptionsSheet({super.key});

  @override
  State<SwapOptionsSheet> createState() => _SwapOptionsSheetState();
}

class _SwapOptionsSheetState extends State<SwapOptionsSheet> {
  String? _pending;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<UnifiedSwapBloc, UnifiedSwapState>(
      builder: (context, state) {
        final quotes = state.quotes;
        final expired = state.evaluation == SwapEvaluationStatus.expired;
        final options = quotes?.options ?? const <SwapQuote>[];
        // A refresh can withdraw the option being considered.
        final pending = _pending != null && quotes?.byId(_pending!) != null
            ? _pending
            : state.selectedId;
        final allUnrankable =
            quotes != null && quotes.ranked.isEmpty && options.length > 1;
        final single = options.length <= 1;

        return SwapSheetScaffold(
          title: single
              ? LocaleKeys.swapOptionDetailsTitle.tr()
              : LocaleKeys.swapOptionsTitle.tr(),
          subtitle: allUnrankable
              ? LocaleKeys.swapOptionsUnrankedNote.tr()
              : LocaleKeys.swapOptionsRankingNote.tr(),
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (expired) ...[
                SwapCallout(
                  tone: SwapTone.warning,
                  icon: Icons.timer_outlined,
                  message: LocaleKeys.swapOptionsExpired.tr(),
                ),
                const SizedBox(height: 12),
              ],
              if (quotes != null)
                ..._cards(context, quotes, pending, expired: expired),
              if (allUnrankable) ...[
                const SizedBox(height: 12),
                SwapCallout(
                  tone: SwapTone.warning,
                  icon: Icons.balance_rounded,
                  title: LocaleKeys.swapOptionsChooseManually.tr(),
                  message: LocaleKeys.swapOptionsChooseManuallyBody.tr(),
                ),
              ],
              if (pending != null && quotes?.byId(pending) != null) ...[
                const SizedBox(height: 12),
                _FeeBreakdown(quote: quotes!.byId(pending)!),
              ],
            ],
          ),
          footer: expired
              ? SwapButton(
                  label: LocaleKeys.swapCtaRefresh.tr(),
                  onPressed: () => context.read<UnifiedSwapBloc>().add(
                    const UnifiedSwapEvaluationRequested(),
                  ),
                )
              : SwapButton(
                  label: pending == null
                      ? LocaleKeys.swapCtaSelectOption.tr()
                      : LocaleKeys.swapUseOption.tr(),
                  onPressed: pending == null
                      ? null
                      : () {
                          context.read<UnifiedSwapBloc>().add(
                            UnifiedSwapOptionSelected(pending),
                          );
                          Navigator.of(context).maybePop();
                        },
                ),
        );
      },
    );
  }

  List<Widget> _cards(
    BuildContext context,
    UnifiedSwapQuotes quotes,
    String? pending, {
    required bool expired,
  }) {
    Widget card(SwapQuote quote, {required bool best}) => Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: _OptionCard(
        quote: quote,
        selected: quote.id == pending,
        best: best,
        onTap: expired ? null : () => setState(() => _pending = quote.id),
      ),
    );
    return [
      for (final (index, quote) in quotes.ranked.indexed)
        card(quote, best: index == 0 && quotes.canClaimBestNetReturn),
      if (quotes.unrankable.isNotEmpty && quotes.ranked.isNotEmpty) ...[
        const SizedBox(height: 6),
        Text(
          LocaleKeys.swapOptionsUnableToCompare.tr(),
          style: SwapText.strong(context),
        ),
        const SizedBox(height: 8),
      ],
      for (final quote in quotes.unrankable) card(quote, best: false),
    ];
  }
}

class _OptionCard extends StatelessWidget {
  const _OptionCard({
    required this.quote,
    required this.selected,
    required this.best,
    required this.onTap,
  });

  final SwapQuote quote;
  final bool selected;
  final bool best;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = SwapPalette.of(context);
    final ticker = SwapFormat.ticker(quote.to);
    final total = quote.pricing.totalCostUsd;
    final badge = best
        ? SwapBadge(
            label: LocaleKeys.swapBestNetReturn.tr(),
            tone: SwapTone.brand,
          )
        : !quote.isRankable
        ? SwapBadge(
            label: LocaleKeys.swapOptionsUnableToCompare.tr(),
            tone: SwapTone.warning,
          )
        : quote.order == SwapQuoteOrder.fastest
        ? SwapBadge(
            label: LocaleKeys.swapOptionFastest.tr(),
            tone: SwapTone.info,
          )
        : null;
    final metrics = [
      (
        LocaleKeys.swapOptionMinimum.tr(),
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
        LocaleKeys.swapOptionEta.tr(),
        SwapFormat.duration(quote.estimatedDuration),
      ),
      (
        LocaleKeys.swapOptionStages.tr(),
        '${quote.stages.where((s) => s.kind != SwapRouteStageKind.prepare).length}',
      ),
      (LocaleKeys.swapOptionPermission.tr(), _permission(quote)),
    ];

    return Semantics(
      inMutuallyExclusiveGroup: true,
      checked: selected,
      button: true,
      child: Material(
        color: selected ? palette.selected : palette.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(
            color: selected ? palette.brand : palette.controlBorder,
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            LocaleKeys.swapOptionExpected.tr(
                              args: [
                                SwapFormat.tokens(
                                  quote.expectedReceive,
                                  ticker,
                                  rounding: SwapRounding.down,
                                ),
                              ],
                            ),
                            style: SwapText.strong(context),
                          ),
                          ?badge,
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _routeLabel(quote.routeKind),
                        style: SwapText.small(context),
                      ),
                      const SizedBox(height: 12),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final columns = constraints.maxWidth < 320 ? 2 : 3;
                          final width =
                              (constraints.maxWidth - (columns - 1) * 8) /
                              columns;
                          return Wrap(
                            spacing: 8,
                            runSpacing: 10,
                            children: [
                              for (final (label, value) in metrics)
                                SizedBox(
                                  width: width,
                                  child: MergeSemantics(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          label,
                                          style: SwapText.small(context),
                                        ),
                                        const SizedBox(height: 3),
                                        Text(
                                          value,
                                          style: SwapText.strong(
                                            context,
                                          ).copyWith(fontSize: 14),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                            ],
                          );
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Icon(
                  selected
                      ? Icons.radio_button_checked_rounded
                      : Icons.radio_button_unchecked_rounded,
                  color: selected ? palette.brand : palette.controlBorder,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static String _permission(SwapQuote quote) {
    final approval = quote.approval;
    if (approval == null) return LocaleKeys.swapPermissionNone.tr();
    return approval.resetsFirst
        ? LocaleKeys.swapPermissionReset.tr()
        : LocaleKeys.swapPermissionExact.tr();
  }
}

String _routeLabel(SwapRouteKind kind) => switch (kind) {
  SwapRouteKind.direct => LocaleKeys.swapRouteDirect.tr(),
  SwapRouteKind.sameChain => LocaleKeys.swapRouteSameChain.tr(),
  SwapRouteKind.crossChain => LocaleKeys.swapRouteCrossChain.tr(),
};

class _FeeBreakdown extends StatelessWidget {
  const _FeeBreakdown({required this.quote});

  final SwapQuote quote;

  @override
  Widget build(BuildContext context) {
    final pricing = quote.pricing;
    String usd(Decimal? value) => value == null
        ? LocaleKeys.swapCostIncomplete.tr()
        : SwapFormat.usd(value, rounding: SwapRounding.up);
    final approval = pricing.approvalNetworkCostUsd;
    return SwapDetails(
      title: LocaleKeys.swapFeeBreakdown.tr(),
      children: [
        SwapDetailRow(
          label: LocaleKeys.swapNetworkCosts.tr(),
          value: usd(pricing.networkCostUsd),
        ),
        if (quote.approval != null && approval != null)
          SwapDetailRow(
            label: '↳ ${LocaleKeys.swapApprovalNetworkCost.tr()}',
            value: usd(approval),
          ),
        SwapDetailRow(
          label: LocaleKeys.swapSwapCosts.tr(),
          value: usd(pricing.swapCostUsd),
        ),
        SwapDetailRow(
          label: LocaleKeys.swapTotalCost.tr(),
          value: pricing.isComplete
              ? usd(pricing.totalCostUsd)
              : LocaleKeys.swapCostIncomplete.tr(),
        ),
      ],
    );
  }
}

/// A route kind's customer-facing name.
String swapRouteKindLabel(SwapRouteKind kind) => _routeLabel(kind);
