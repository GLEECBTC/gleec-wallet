import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/bloc/auth_bloc/auth_bloc.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_bloc.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_event.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_state.dart';
import 'package:web_dex/bloc/trading_status/trading_status_bloc.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/shared/swap/swap_networks.dart';
import 'package:web_dex/shared/swap/swap_quote.dart';
import 'package:web_dex/shared/swap/swap_quote_failure.dart';
import 'package:web_dex/shared/swap/swap_services.dart';
import 'package:web_dex/views/swap/common/swap_copy.dart';
import 'package:web_dex/views/swap/common/swap_format.dart';
import 'package:web_dex/views/swap/common/swap_links.dart';
import 'package:web_dex/views/swap/common/swap_palette.dart';
import 'package:web_dex/views/swap/common/swap_sheet.dart';
import 'package:web_dex/views/swap/common/swap_widgets.dart';
import 'package:web_dex/views/swap/entry/swap_amount_cards.dart';
import 'package:web_dex/views/swap/motion/swap_motion.dart';
import 'package:web_dex/views/swap/pickers/swap_slippage_sheet.dart';
import 'package:web_dex/views/swap/swap_shell_controller.dart';
import 'package:web_dex/views/swap/common/swap_legal_notice.dart';
import 'package:web_dex/shared/widgets/legal_documents/legal_document_notice.dart';

part 'swap_review_changes.dart';
part 'swap_review_details.dart';
part 'swap_review_footer.dart';
part 'swap_review_sections.dart';

/// How long an action that commits funds ignores presses after it appears,
/// or after what it would commit to changes.
///
/// The action takes the place of the button pressed just before it — the
/// form's Review, or its own "Checking…" — so a double tap, or a tap already
/// on its way, must not land as consent to terms nobody has read.
const swapCommitArmingDelay = Duration(milliseconds: 550);

/// The last look before committing: what is paid, the guaranteed minimum,
/// every cost, the permission asked for, and how the swap completes.
class SwapReviewView extends StatelessWidget {
  const SwapReviewView({this.inPanel = false, super.key});

  /// Whether this renders in the side panel beside the form.
  final bool inPanel;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<UnifiedSwapBloc, UnifiedSwapState>(
      buildWhen: (previous, current) =>
          previous.review != current.review ||
          previous.tradingEnabled != current.tradingEnabled ||
          previous.tradingStatusLoading != current.tradingStatusLoading ||
          previous.tradingStatusUnavailable !=
              current.tradingStatusUnavailable ||
          previous.hardwareWallet != current.hardwareWallet ||
          previous.rateLimitedUntil != current.rateLimitedUntil ||
          previous.payAddress != current.payAddress ||
          previous.receiveAddress != current.receiveAddress,
      builder: (context, state) {
        final review = state.review;
        if (review == null) return const SizedBox.shrink();
        final bloc = context.read<UnifiedSwapBloc>();
        final services = context.read<SwapServices>();

        void back() => bloc.add(const UnifiedSwapReviewClosed());

        return SwapScreen(
          onEscape: back,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final legal = _ReviewLegal.of(
                context,
                review,
                constraints.biggest,
              );
              final content = _ReviewContent(
                review: review,
                state: state,
                networks: services.networks(),
                services: services,
                onBack: back,
                legal: legal,
              );
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      child: inPanel
                          ? Padding(
                              padding: const EdgeInsets.fromLTRB(18, 18, 18, 8),
                              child: content,
                            )
                          : SwapColumn(
                              padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
                              child: content,
                            ),
                    ),
                  ),
                  // A legal notice that failed to load can outgrow a short
                  // window. It stays with the action it blocks, and scrolls
                  // rather than taking the review's own room.
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: constraints.maxHeight * .6,
                    ),
                    child: SingleChildScrollView(
                      key: const Key('swap-review-confirmation-scroll'),
                      primary: false,
                      child: SwapStickyFooter(
                        inPanel: inPanel,
                        child: _ReviewFooter(
                          review: review,
                          legal: legal,
                          tradingEnabled: state.tradingEnabled,
                          tradingStatusLoading: state.tradingStatusLoading,
                          tradingStatusUnavailable:
                              state.tradingStatusUnavailable,
                          hardwareWallet: state.hardwareWallet,
                          paused:
                              state.rateLimitedUntil?.isAfter(DateTime.now()) ??
                              false,
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }
}

class _ReviewContent extends StatelessWidget {
  const _ReviewContent({
    required this.review,
    required this.state,
    required this.networks,
    required this.services,
    required this.onBack,
    required this.legal,
  });

  final SwapReview review;
  final UnifiedSwapState state;
  final SwapNetworks networks;
  final SwapServices services;
  final VoidCallback onBack;
  final _ReviewLegal legal;

  SwapQuote get quote => review.quote;

  @override
  Widget build(BuildContext context) {
    final fromTicker = SwapFormat.ticker(quote.from);
    final toTicker = SwapFormat.ticker(quote.to);
    final fromNetwork = networks.networkOf(quote.from);
    final toNetwork = networks.networkOf(quote.to);
    final fromAddress = quote.fromAddress ?? state.payAddress;
    final toAddress = quote.toAddress ?? state.receiveAddress;
    final impact = quote.pricing.priceImpact;
    final media = MediaQuery.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // At 200% the title alone would fill a third of a phone, above the
        // figures this screen exists to show.
        MediaQuery(
          data: media.copyWith(
            textScaler: media.textScaler.clamp(maxScaleFactor: 1.3),
          ),
          child: SwapPageHeading(
            title: LocaleKeys.swapReviewTitle.tr(),
            leading: SwapIconButton(
              icon: Icons.arrow_back_rounded,
              label: LocaleKeys.back.tr(),
              onPressed: review.startInDoubt ? null : onBack,
            ),
          ),
        ),
        if (_badge(review.status) case final (String, SwapTone) badge)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: SwapBadge(label: badge.$1, tone: badge.$2),
          ),
        // What changed comes first: on a phone the details below run past
        // the screen, while the button asking to accept it is pinned.
        if (_status(context) case final status?) status,
        if (!state.tradingEnabled && !review.startInDoubt) ...[
          const SizedBox(height: 8),
          SwapHelperLine(
            text: state.hardwareWallet
                ? LocaleKeys.trezorWalletOnlyNotice.tr()
                : state.tradingStatusLoading
                ? 'swapAvailabilityChecking'.tr()
                : state.tradingStatusUnavailable
                ? 'swapAvailabilityUnavailable'.tr()
                : LocaleKeys.tradingDisabled.tr(),
            tone: state.tradingStatusLoading
                ? SwapTone.neutral
                : SwapTone.warning,
          ),
        ],
        const SizedBox(height: 12),
        _Summary(
          quote: quote,
          fromNetwork: fromNetwork,
          toNetwork: toNetwork,
          fromAddress: fromAddress,
          toAddress: toAddress,
        ),
        ..._warnings(context, impact),
        const SizedBox(height: 8),
        _DecisionGrid(quote: quote),
        const SizedBox(height: 8),
        _Permission(quote: quote),
        const SizedBox(height: 10),
        _costs(context),
        const SizedBox(height: 8),
        _routeAndIdentities(
          context,
          fromAddress: fromAddress,
          toAddress: toAddress,
          fromTicker: fromTicker,
          toTicker: toTicker,
          fromNetwork: fromNetwork,
          toNetwork: toNetwork,
        ),
        if (legal != _ReviewLegal.none) ...[
          const SizedBox(height: 14),
          const SwapProviderNotice(linked: false),
          if (legal.linksInContent)
            SwapLegalLinks(snapshot: review.legalSnapshot),
        ],
        const SizedBox(height: 8),
      ],
    );
  }

  /// The quiet statuses only. One that needs the user says so in a callout,
  /// and a badge over it would say it twice.
  static (String, SwapTone)? _badge(SwapReviewStatus status) =>
      switch (status) {
        SwapReviewStatus.ready => (
          LocaleKeys.swapReviewReady.tr(),
          SwapTone.brand,
        ),
        SwapReviewStatus.revalidating => (
          LocaleKeys.swapReviewChecking.tr(),
          SwapTone.info,
        ),
        SwapReviewStatus.starting => (
          LocaleKeys.swapReviewStartingBadge.tr(),
          SwapTone.info,
        ),
        SwapReviewStatus.revalidationFailed ||
        SwapReviewStatus.expired ||
        SwapReviewStatus.materialUpdate ||
        SwapReviewStatus.rejected ||
        SwapReviewStatus.unconfirmed => null,
      };
}
