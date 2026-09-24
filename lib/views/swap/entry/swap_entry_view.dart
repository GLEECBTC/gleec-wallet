import 'package:decimal/decimal.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/bloc/trading_status/trading_status_bloc.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_bloc.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_event.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_state.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/shared/swap/swap_quote.dart';
import 'package:web_dex/shared/swap/swap_quote_failure.dart';
import 'package:web_dex/shared/swap/swap_services.dart';
import 'package:web_dex/views/swap/common/swap_card_pair.dart';
import 'package:web_dex/views/swap/common/swap_copy.dart';
import 'package:web_dex/views/swap/common/swap_format.dart';
import 'package:web_dex/views/swap/common/swap_palette.dart';
import 'package:web_dex/views/swap/common/swap_widgets.dart';
import 'package:web_dex/views/swap/entry/swap_amount_cards.dart';
import 'package:web_dex/views/swap/entry/swap_quote_strip.dart';
import 'package:web_dex/views/swap/pickers/swap_asset_picker.dart';
import 'package:web_dex/views/swap/pickers/swap_options_sheet.dart';

/// The swap form: what to pay, what to receive, and the best way to do it.
class SwapEntryView extends StatefulWidget {
  const SwapEntryView({this.panelOpen = false, super.key});

  /// Whether the review is open beside the form, on a wide screen.
  final bool panelOpen;

  @override
  State<SwapEntryView> createState() => _SwapEntryViewState();
}

class _SwapEntryViewState extends State<SwapEntryView> {
  bool _activating = false;

  UnifiedSwapBloc get _bloc => context.read<UnifiedSwapBloc>();
  SwapServices get _services => context.read<SwapServices>();

  /// Editing while the review panel is open closes the review first: the
  /// numbers it asks consent to are about to change.
  void _edit(UnifiedSwapEvent event) {
    if (_bloc.state.view == UnifiedSwapView.review) {
      _bloc.add(const UnifiedSwapReviewClosed());
    }
    _bloc.add(event);
  }

  bool _isBlocked(AssetId asset) {
    try {
      return context.read<TradingStatusBloc>().state.isAssetBlocked(asset);
    } on Object {
      return false;
    }
  }

  Future<void> _pick(SwapPickerSide side) async {
    final state = _bloc.state;
    final chosen = await showSwapAssetPicker(
      context: context,
      side: side,
      tradable: state.tradableAssets,
      selected: side == SwapPickerSide.pay ? state.pay : state.receive,
      other: side == SwapPickerSide.pay ? state.receive : state.pay,
      services: _services,
      isBlocked: _isBlocked,
    );
    if (chosen == null || !mounted) return;
    _edit(
      side == SwapPickerSide.pay
          ? UnifiedSwapPayAssetChanged(chosen)
          : UnifiedSwapReceiveAssetChanged(chosen),
    );
  }

  Future<void> _activate(AssetId asset) async {
    setState(() => _activating = true);
    try {
      await _services.activate(asset);
      if (!mounted) return;
      _bloc
        ..add(const UnifiedSwapBalancesRefreshed())
        ..add(const UnifiedSwapEvaluationRequested());
    } on Object {
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text(
            LocaleKeys.swapPickerActivationFailed.tr(
              args: [SwapFormat.ticker(asset)],
            ),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _activating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<UnifiedSwapBloc, UnifiedSwapState>(
      listenWhen: (previous, current) =>
          previous.evaluation != current.evaluation,
      listener: (context, state) {
        if (state.evaluation == SwapEvaluationStatus.ready) {
          swapAnnounce(context, LocaleKeys.swapAnnounceReady.tr());
        }
      },
      builder: (context, state) {
        final networks = _services.networks();
        final pay = state.pay;
        final receive = state.receive;
        final price = pay == null ? null : _services.usdPrice(pay);

        final cards = Semantics(
          container: true,
          explicitChildNodes: true,
          child: SwapCardPair(
            top: Semantics(
              sortKey: const OrdinalSortKey(0),
              child: SwapPayCard(
                state: state,
                network: pay == null ? null : networks.networkOf(pay),
                tokenAmount: _bloc.amountOf(state),
                usdPrice: price,
                onAmountChanged: (text) =>
                    _edit(UnifiedSwapAmountChanged(text)),
                onModeToggled: () =>
                    _edit(const UnifiedSwapAmountModeToggled()),
                onMax: () {
                  _edit(const UnifiedSwapMaxRequested());
                  swapAnnounce(context, LocaleKeys.swapAnnounceMax.tr());
                },
                onPickAsset: () => _pick(SwapPickerSide.pay),
              ),
            ),
            bottom: Semantics(
              sortKey: const OrdinalSortKey(2),
              child: SwapReceiveCard(
                state: state,
                network: receive == null ? null : networks.networkOf(receive),
                onPickAsset: () => _pick(SwapPickerSide.receive),
              ),
            ),
            switcher: Semantics(
              sortKey: const OrdinalSortKey(1),
              child: SwapSwitchButton(
                onPressed: pay == null && receive == null
                    ? null
                    : () {
                        _edit(const UnifiedSwapSidesSwitched());
                        swapAnnounce(
                          context,
                          LocaleKeys.swapAnnounceSwitched.tr(),
                        );
                      },
              ),
            ),
          ),
        );

        final quote = state.selectedQuote;
        final checking =
            state.evaluation == SwapEvaluationStatus.checking &&
            state.quotes == null;

        return SingleChildScrollView(
          child: SwapColumn(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SwapPageHeading(title: LocaleKeys.swap.tr()),
                if (!state.tradingEnabled) ...[
                  SwapCallout(
                    tone: SwapTone.warning,
                    message: LocaleKeys.tradingDisabled.tr(),
                  ),
                  const SizedBox(height: 14),
                ],
                cards,
                ..._messages(context, state),
                if (checking) ...[
                  const SizedBox(height: 14),
                  const SwapSkeleton(widthFactor: 0.68),
                  const SizedBox(height: 8),
                  const SwapSkeleton(widthFactor: 0.45),
                ],
                if (quote != null) ...[
                  SwapQuoteStrip(
                    state: state,
                    onCompare: () => showSwapOptionsSheet(context, _bloc),
                  ),
                  SwapRateLine(quote: quote),
                ],
                const SizedBox(height: 14),
                if (widget.panelOpen)
                  SwapHelperLine(text: LocaleKeys.swapReviewPanelNote.tr())
                else
                  _primaryAction(context, state),
              ],
            ),
          ),
        );
      },
    );
  }

  /// One line under the cards: an error, else a warning, else a hint.
  List<Widget> _messages(BuildContext context, UnifiedSwapState state) {
    final pay = state.pay;
    final issue = state.issue;
    if (issue != null && issue != SwapFormIssue.amountMissing) {
      final message = swapIssueMessage(
        issue,
        pay: pay,
        balance: state.balance,
        feeNeeded: _feeNeeded(state),
        feeHeld: _feeHeld(state),
      );
      if (message != null) {
        return [SwapHelperLine(text: message, tone: SwapTone.danger)];
      }
    }

    final failure = state.failure;
    if (state.evaluation == SwapEvaluationStatus.failed && failure != null) {
      final copy = SwapFailureCopy.of(failure, pay);
      final tone = failure.kind == SwapQuoteFailureKind.rateLimited
          ? SwapTone.warning
          : SwapTone.danger;
      return [
        SwapHelperLine(text: copy.message, tone: tone),
        if (copy.detail != null) SwapHelperLine(text: copy.detail!),
      ];
    }

    final messages = <Widget>[];
    if (state.structuralNotice) {
      messages.add(
        SwapHelperLine(
          text: LocaleKeys.swapHelperStructural.tr(),
          tone: SwapTone.warning,
        ),
      );
    }
    final quote = state.selectedQuote;
    final impact = quote?.pricing.priceImpact;
    if (impact != null && impact >= swapHighImpact) {
      messages.add(
        SwapHelperLine(
          text: LocaleKeys.swapWarningHighImpact.tr(
            args: [SwapFormat.percent(impact)],
          ),
          tone: SwapTone.warning,
        ),
      );
    }
    if (messages.isNotEmpty) return messages;

    if (state.evaluation == SwapEvaluationStatus.checking) {
      return [SwapHelperLine(text: LocaleKeys.swapHelperChecking.tr())];
    }
    final max = state.maxApplied;
    if (max != null && pay != null) {
      return [SwapHelperLine(text: _maxHint(max, pay))];
    }
    if (quote != null && quote.pricing.expectedUsd == null) {
      return [
        SwapHelperLine(text: LocaleKeys.swapWarningPriceUnavailable.tr()),
      ];
    }
    if (state.loadingAssets) {
      return [SwapHelperLine(text: LocaleKeys.swapHelperLoadingAssets.tr())];
    }
    return const [];
  }

  String _maxHint(SwapMaxAmount max, AssetId pay) {
    final ticker = SwapFormat.ticker(pay);
    final amount = SwapFormat.tokens(max.amount, ticker);
    if (max.reservedForFees > Decimal.zero) {
      final feeTicker = max.feeAsset == null
          ? ticker
          : SwapFormat.ticker(max.feeAsset!);
      return LocaleKeys.swapHelperMaxNative.tr(
        args: [
          amount,
          SwapFormat.tokens(
            max.reservedForFees,
            feeTicker,
            rounding: SwapRounding.up,
          ),
        ],
      );
    }
    final parent = pay.parentId;
    if (parent != null) {
      return LocaleKeys.swapHelperMaxToken.tr(
        args: [amount, SwapFormat.ticker(parent)],
      );
    }
    return LocaleKeys.swapHelperMaxAtomic.tr(args: [amount]);
  }

  String? _feeNeeded(UnifiedSwapState state) {
    final parent = state.pay?.parentId;
    final quote = state.selectedQuote;
    if (parent == null || quote == null) return null;
    var total = Decimal.zero;
    for (final fee in quote.fees) {
      if (fee.asset == parent && !fee.deductedFromReceive) total += fee.amount;
    }
    return SwapFormat.tokens(
      total,
      SwapFormat.ticker(parent),
      rounding: SwapRounding.up,
    );
  }

  String? _feeHeld(UnifiedSwapState state) {
    final parent = state.pay?.parentId;
    final held = state.feeBalance;
    if (parent == null || held == null) return null;
    return SwapFormat.tokens(
      held,
      SwapFormat.ticker(parent),
      rounding: SwapRounding.down,
    );
  }

  Widget _primaryAction(BuildContext context, UnifiedSwapState state) {
    final (label, onPressed, busy) = _cta(state);
    return SwapButton(
      key: const Key('swap-primary-action'),
      label: label,
      onPressed: onPressed,
      busy: busy,
    );
  }

  (String, VoidCallback?, bool) _cta(UnifiedSwapState state) {
    if (!state.tradingEnabled) {
      return (LocaleKeys.tradingDisabled.tr(), null, false);
    }
    if (state.pay == null) {
      return (
        LocaleKeys.swapCtaSelectAsset.tr(),
        () => _pick(SwapPickerSide.pay),
        false,
      );
    }
    if (state.receive == null) {
      return (
        LocaleKeys.swapCtaSelectAsset.tr(),
        () => _pick(SwapPickerSide.receive),
        false,
      );
    }
    final issue = state.issue;
    if (issue == SwapFormIssue.amountMissing) {
      return (LocaleKeys.swapCtaEnterAmount.tr(), null, false);
    }
    if (issue != null) return (LocaleKeys.swapCtaReview.tr(), null, false);

    switch (state.evaluation) {
      case SwapEvaluationStatus.idle || SwapEvaluationStatus.checking:
        return (LocaleKeys.swapCtaChecking.tr(), null, true);
      case SwapEvaluationStatus.expired:
        return (
          LocaleKeys.swapCtaRefresh.tr(),
          () => _bloc.add(const UnifiedSwapEvaluationRequested()),
          false,
        );
      case SwapEvaluationStatus.failed:
        final failure = state.failure;
        if (failure == null) {
          return (
            LocaleKeys.tryAgain.tr(),
            () => _bloc.add(const UnifiedSwapEvaluationRequested()),
            false,
          );
        }
        final copy = SwapFailureCopy.of(failure, state.pay);
        return switch (copy.action) {
          SwapEntryAction.retry => (
            LocaleKeys.tryAgain.tr(),
            () => _bloc.add(const UnifiedSwapEvaluationRequested()),
            false,
          ),
          SwapEntryAction.activate => (
            LocaleKeys.swapCtaActivate.tr(),
            _activating ? null : () => _activate(failure.asset ?? state.pay!),
            _activating,
          ),
          SwapEntryAction.chooseAnother => (
            LocaleKeys.swapCtaChooseAnother.tr(),
            () => _pick(SwapPickerSide.receive),
            false,
          ),
          SwapEntryAction.wait => (
            LocaleKeys.tryAgain.tr(),
            (state.rateLimitedUntil?.isAfter(DateTime.now()) ?? false)
                ? null
                : () => _bloc.add(const UnifiedSwapEvaluationRequested()),
            false,
          ),
          SwapEntryAction.none => (LocaleKeys.swapCtaReview.tr(), null, false),
        };
      case SwapEvaluationStatus.ready:
        if (state.selectedQuote == null) {
          return (
            LocaleKeys.swapCtaSelectOption.tr(),
            () => showSwapOptionsSheet(context, _bloc),
            false,
          );
        }
        return (
          LocaleKeys.swapCtaReview.tr(),
          state.canReview
              ? () => _bloc.add(const UnifiedSwapReviewOpened())
              : null,
          false,
        );
    }
  }
}
