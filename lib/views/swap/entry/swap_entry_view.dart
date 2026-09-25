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

part 'swap_entry_messages.dart';

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
      bloc: _bloc,
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
      _bloc.add(UnifiedSwapAssetActivated(asset));
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
    if (issue == SwapFormIssue.assetInactive) {
      final asset = state.inactiveAsset!;
      return (
        LocaleKeys.swapCtaActivateAsset.tr(args: [SwapFormat.ticker(asset)]),
        _activating ? null : () => _activate(asset),
        _activating,
      );
    }
    if (issue == SwapFormIssue.pairUnsupported ||
        issue == SwapFormIssue.sameAsset) {
      return (
        LocaleKeys.swapCtaChooseAnother.tr(),
        () => _pick(SwapPickerSide.receive),
        false,
      );
    }
    if (issue == SwapFormIssue.amountMissing) {
      return (LocaleKeys.swapCtaEnterAmount.tr(), null, false);
    }
    final short = _shortOf(state);
    final review = short == null
        ? LocaleKeys.swapCtaReview.tr()
        : LocaleKeys.swapCtaNotEnough.tr(args: [short]);
    if (issue != null && !issue.stillPriced) return (review, null, false);

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
        final copy = _failureCopy(state, failure);
        return switch (copy.action) {
          SwapEntryAction.retry => (
            LocaleKeys.tryAgain.tr(),
            () => _bloc.add(const UnifiedSwapEvaluationRequested()),
            false,
          ),
          SwapEntryAction.activate => (
            LocaleKeys.swapCtaActivateAsset.tr(
              args: [SwapFormat.ticker(failure.asset ?? state.pay!)],
            ),
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
          SwapEntryAction.none => (review, null, false),
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
          review,
          state.canReview
              ? () => _bloc.add(const UnifiedSwapReviewOpened())
              : null,
          false,
        );
    }
  }

  /// The ticker the wallet is short of, when that is what stops the swap.
  String? _shortOf(UnifiedSwapState state) {
    final pay = state.pay;
    if (pay == null) return null;
    return switch (state.issue) {
      SwapFormIssue.insufficient => SwapFormat.ticker(pay),
      SwapFormIssue.insufficientForFees ||
      SwapFormIssue.noFeeBalance => SwapFormat.ticker(pay.parentId ?? pay),
      _ => null,
    };
  }
}
