import 'dart:async';
import 'dart:math' as math;

import 'package:decimal/decimal.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_state.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/shared/swap/swap_quote.dart';
import 'package:web_dex/shared/swap/swap_terms_repository.dart';
import 'package:web_dex/views/swap/common/swap_format.dart';
import 'package:web_dex/views/swap/common/swap_links.dart';
import 'package:web_dex/views/swap/common/swap_palette.dart';
import 'package:web_dex/views/swap/common/swap_widgets.dart';

part 'swap_quote_facts.dart';
part 'swap_quote_rate.dart';

/// From how many seconds before expiry the countdown shows.
const _countdownFrom = Duration(seconds: 20);

const _stripPadding = 14.0;

/// The card's padding and its border, which takes room as padding does.
const _stripInset = _stripPadding + 1;

/// The selected option in one card: the minimum, the total cost, the time,
/// and why it was chosen.
///
/// While an option is still being looked for it keeps the same shape with
/// placeholders, so its arrival fills the card in rather than moving the
/// form.
class SwapQuoteStrip extends StatefulWidget {
  const SwapQuoteStrip({
    required this.state,
    required this.onCompare,
    this.now = DateTime.now,
    this.placeholder = false,
    this.waitingLabel,
    this.waitingAnnounced = false,
    super.key,
  });

  final UnifiedSwapState state;
  final VoidCallback onCompare;
  final DateTime Function() now;

  /// Whether the strip holds its place, its figures as placeholders, while
  /// no option is selected. Otherwise it shows nothing until one is.
  final bool placeholder;

  /// What is being waited for, said under the placeholders.
  final String? waitingLabel;

  /// Whether [waitingLabel] is read out when it changes: a delay is worth
  /// hearing about once, a check on every edit is not.
  final bool waitingAnnounced;

  /// The room a strip [width] wide takes once an option to receive [receive]
  /// is in it, [routed] with its provider notice, so the form can keep that
  /// room before the option arrives.
  static double reservedHeight(
    BuildContext context, {
    required double width,
    required AssetId? receive,
    required bool routed,
  }) {
    final inner = math.max(0.0, width - _stripInset * 2);
    return _stripInset * 2 +
        _QuoteFacts.heightOf(context, width: inner, receive: receive) +
        _footerGap +
        _footerHeight(
          context,
          inner,
          note: LocaleKeys.swapBestNetReturnNote.tr(),
        ) +
        (routed ? _noticeGap + _noticeHeight(context, inner) : 0) +
        _roundingSlack;
  }

  @override
  State<SwapQuoteStrip> createState() => _SwapQuoteStripState();
}

/// The space and rule between the facts and the line under them.
const _footerGap = 10.0 + 1 + 4;
const _noticeGap = 4.0;
const _badgeNoteGap = 5.0;

/// Text measured ahead of its layout can differ from it by a fraction of a
/// pixel a line. Room kept for it errs on the generous side: a pixel too
/// many shows nowhere, one too few moves the form.
const _roundingSlack = 2.0;

List<_Fact> _placeholderFacts() => [
  (label: LocaleKeys.swapMinimumReceived.tr(), value: null),
  (label: LocaleKeys.swapTotalCost.tr(), value: null),
  (label: LocaleKeys.swapEstimatedTime.tr(), value: null),
];

/// Whether the line under the facts stacks its badges over its link.
bool _footerStacks(BuildContext context, double width) =>
    width / MediaQuery.textScalerOf(context).scale(1) < 300;

/// How tall the line under the facts is with a badge over [note] in it: the
/// most it usually holds. Without a note, the least it is given: side by
/// side, room for a badge over one line of note, so a badge arriving moves
/// nothing below the strip; stacked, its link alone.
double _footerHeight(BuildContext context, double width, {String? note}) {
  final small = SwapText.small(context);
  final line = SwapText.heightOf(context, const TextSpan(text: '0'), small);
  final linkStyle = SwapText.strong(context).copyWith(fontSize: 14);
  final linkHeight = math.max(
    SwapGeometry.touchTarget,
    SwapText.heightOf(context, const TextSpan(text: '0'), linkStyle) + 20,
  );
  final stacks = _footerStacks(context, width);
  if (stacks && note == null) return linkHeight;
  final noteWidth = stacks
      ? width
      : width -
            math.max(
              SwapGeometry.touchTarget,
              SwapText.widthOf(
                    context,
                    LocaleKeys.swapCompareOptions.tr(),
                    linkStyle,
                  ) +
                  16,
            );
  final noteHeight = note == null
      ? line
      : SwapText.heightOf(
          context,
          TextSpan(text: note),
          small,
          maxWidth: math.max(0, noteWidth),
        );
  final badge = math.max(28.0, line + 8) + _badgeNoteGap + noteHeight;
  return stacks ? badge + linkHeight : math.max(linkHeight, badge);
}

/// How tall the provider notice sets [width] wide. Its link is one
/// unbreakable run in bold, as the notice lays it out, and sits a little
/// proud of its line.
double _noticeHeight(BuildContext context, double width) {
  const provider = SwapTermsRepository.provider;
  final style = SwapText.small(context).copyWith(height: 1.5);
  return SwapText.heightOf(
        context,
        TextSpan(
          children: [
            TextSpan(
              text: '${LocaleKeys.swapRoutedThrough.tr(args: [provider])} ',
            ),
            TextSpan(
              text: LocaleKeys.swapTermsLinkLabel
                  .tr(args: [provider])
                  .replaceAll(' ', '\u00A0'),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ],
        ),
        style,
        maxWidth: width,
      ) +
      3 * MediaQuery.textScalerOf(context).scale(1);
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
    final waiting = widget.waitingLabel;
    if (quote == null && !widget.placeholder) return const SizedBox.shrink();
    final palette = SwapPalette.of(context);

    return Semantics(
      container: true,
      label: LocaleKeys.swapA11yQuoteSummary.tr(),
      child: Container(
        padding: const EdgeInsets.all(_stripPadding),
        decoration: BoxDecoration(
          color: palette.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: palette.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Placeholders say nothing; the line under them says what is
            // being waited for.
            ExcludeSemantics(
              excluding: quote == null,
              child: _QuoteFacts(
                facts: quote == null ? _placeholderFacts() : _facts(quote),
                receive: state.receive,
              ),
            ),
            // With nothing to say under the placeholders, the line is left
            // out; the form keeps its room either way.
            if (quote != null || waiting != null) ...[
              const SizedBox(height: 10),
              Divider(height: 1, thickness: 1, color: palette.border),
              const SizedBox(height: 4),
              LayoutBuilder(
                builder: (context, constraints) => ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: _footerHeight(context, constraints.maxWidth),
                  ),
                  child: quote == null
                      ? Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: _status(context, waiting!),
                        )
                      : _footer(context, quote),
                ),
              ),
            ],
            // Wide screens open the review beside the form, with its own.
            if (quote != null &&
                quote.source == SwapLiquiditySource.routed &&
                state.view != UnifiedSwapView.review) ...[
              const SizedBox(height: _noticeGap),
              const SwapProviderNotice(linkKey: Key('swap-strip-terms-link')),
            ],
          ],
        ),
      ),
    );
  }

  List<_Fact> _facts(SwapQuote quote) => [
    (
      label: LocaleKeys.swapMinimumReceived.tr(),
      value: SwapFormat.tokens(
        quote.guaranteedReceive,
        SwapFormat.ticker(quote.to),
        rounding: SwapRounding.down,
      ),
    ),
    (label: LocaleKeys.swapTotalCost.tr(), value: SwapFormat.totalCost(quote)),
    (
      label: LocaleKeys.swapEstimatedTime.tr(),
      value: SwapFormat.duration(quote.estimatedDuration),
    ),
  ];

  Widget _status(BuildContext context, String text) => Semantics(
    liveRegion: widget.waitingAnnounced,
    child: Text(text, style: SwapText.small(context)),
  );

  Widget _footer(BuildContext context, SwapQuote quote) {
    final state = widget.state;
    return LayoutBuilder(
      builder: (context, constraints) {
        final badges = _badges(context, quote);
        final compare = SwapLinkButton(
          // An aggregator route may have a faster alternative, priced
          // only once the comparison opens.
          label: _hasBetterQuote(quote)
              ? 'swapBetterOptionAvailable'.tr()
              : (state.quotes?.hasAlternatives ?? false) ||
                    quote.source == SwapLiquiditySource.routed
              ? LocaleKeys.swapCompareOptions.tr()
              : LocaleKeys.swapDetails.tr(),
          onPressed: widget.onCompare,
        );
        if (_footerStacks(context, constraints.maxWidth)) {
          // The link keeps to the end edge, where it is side by side.
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              badges,
              Align(alignment: AlignmentDirectional.centerEnd, child: compare),
            ],
          );
        }
        return Row(
          children: [
            Expanded(child: badges),
            compare,
          ],
        );
      },
    );
  }

  bool _hasBetterQuote(SwapQuote selected) {
    if (!selected.isRankable || widget.state.manuallySelected) return false;
    return widget.state.quotes?.ranked.any(
          (candidate) =>
              candidate.id != selected.id &&
              candidate.from == selected.from &&
              candidate.to == selected.to &&
              candidate.sellAmount == selected.sellAmount &&
              candidate.isRankable &&
              candidate.netReturnUsd! > selected.netReturnUsd!,
        ) ??
        false;
  }

  Widget _badges(BuildContext context, SwapQuote quote) {
    final state = widget.state;
    final quotes = state.quotes;
    final badges = <Widget>[];
    String? note;

    final isBest =
        quotes != null &&
        !state.quotesPending &&
        !state.pricingPending &&
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

    // What is still being looked up takes the note's place, where its
    // coming and going moves nothing.
    if (state.evaluation == SwapEvaluationStatus.checking) {
      note = LocaleKeys.swapHelperChecking.tr();
    } else if (state.quotesPending) {
      note = 'swapMoreQuotesChecking'.tr();
    }

    if (badges.isEmpty && note == null) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (badges.isNotEmpty)
          Wrap(spacing: 6, runSpacing: 6, children: badges),
        if (note != null) ...[
          if (badges.isNotEmpty) const SizedBox(height: _badgeNoteGap),
          Text(note, style: SwapText.small(context)),
        ],
      ],
    );
  }
}
