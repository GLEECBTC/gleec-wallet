import 'package:decimal/decimal.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_bloc.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_event.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_state.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/shared/swap/swap_networks.dart';
import 'package:web_dex/shared/swap/swap_quote.dart';
import 'package:web_dex/shared/swap/swap_services.dart';
import 'package:web_dex/shared/swap/swap_terms_repository.dart';
import 'package:web_dex/shared/utils/utils.dart';
import 'package:web_dex/views/swap/common/swap_copy.dart';
import 'package:web_dex/views/swap/common/swap_format.dart';
import 'package:web_dex/views/swap/common/swap_palette.dart';
import 'package:web_dex/views/swap/common/swap_widgets.dart';
import 'package:web_dex/views/swap/entry/swap_amount_cards.dart';
import 'package:web_dex/views/swap/swap_shell_controller.dart';

part 'swap_review_details.dart';
part 'swap_review_sections.dart';

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
          previous.payAddress != current.payAddress ||
          previous.receiveAddress != current.receiveAddress,
      builder: (context, state) {
        final review = state.review;
        if (review == null) return const SizedBox.shrink();
        final bloc = context.read<UnifiedSwapBloc>();
        final services = context.read<SwapServices>();

        void back() => bloc.add(const UnifiedSwapReviewClosed());

        final content = _ReviewContent(
          review: review,
          state: state,
          networks: services.networks(),
          services: services,
          onBack: back,
        );
        final footer = _ReviewFooter(review: review);

        return CallbackShortcuts(
          bindings: {const SingleActivator(LogicalKeyboardKey.escape): back},
          child: Focus(
            autofocus: true,
            child: Column(
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
                _StickyFooter(inPanel: inPanel, child: footer),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _StickyFooter extends StatelessWidget {
  const _StickyFooter({required this.inPanel, required this.child});

  final bool inPanel;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final palette = SwapPalette.of(context);
    final padded = Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: child,
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        color: inPanel ? palette.surfaceRaised : palette.canvas,
        border: Border(top: BorderSide(color: palette.border)),
      ),
      child: inPanel
          ? padded
          : Align(
              alignment: Alignment.topCenter,
              heightFactor: 1,
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: SwapGeometry.contentWidth,
                ),
                child: padded,
              ),
            ),
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
  });

  final SwapReview review;
  final UnifiedSwapState state;
  final SwapNetworks networks;
  final SwapServices services;
  final VoidCallback onBack;

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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SwapPageHeading(
          title: LocaleKeys.swapReviewTitle.tr(),
          leading: SwapIconButton(
            icon: Icons.arrow_back_rounded,
            label: LocaleKeys.back.tr(),
            onPressed: review.status == SwapReviewStatus.starting
                ? null
                : onBack,
          ),
        ),
        if (_badge(review.status) case final (String, SwapTone) badge)
          Align(
            alignment: Alignment.centerLeft,
            child: SwapBadge(label: badge.$1, tone: badge.$2),
          ),
        const SizedBox(height: 12),
        _Summary(
          quote: quote,
          fromNetwork: fromNetwork,
          toNetwork: toNetwork,
          fromAddress: fromAddress,
          toAddress: toAddress,
        ),
        const SizedBox(height: 14),
        _Protection(
          minimum: SwapFormat.tokens(
            quote.guaranteedReceive,
            toTicker,
            rounding: SwapRounding.down,
          ),
        ),
        const SizedBox(height: 14),
        _DecisionGrid(quote: quote),
        const SizedBox(height: 12),
        _costs(context),
        const SizedBox(height: 12),
        _routeAndIdentities(
          context,
          fromAddress: fromAddress,
          toAddress: toAddress,
          fromTicker: fromTicker,
          toTicker: toTicker,
          fromNetwork: fromNetwork,
          toNetwork: toNetwork,
        ),
        ..._warnings(context, impact),
        ..._status(context),
        const SizedBox(height: 14),
        _Permission(quote: quote),
        if (review.termsRequired &&
            quote.source == SwapLiquiditySource.routed) ...[
          const SizedBox(height: 14),
          const _TermsNotice(),
        ],
        const SizedBox(height: 8),
      ],
    );
  }

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
        SwapReviewStatus.revalidationFailed => (
          LocaleKeys.swapReviewCouldNotRefresh.tr(),
          SwapTone.warning,
        ),
        SwapReviewStatus.expired => (
          LocaleKeys.swapReviewExpiredBadge.tr(),
          SwapTone.warning,
        ),
        SwapReviewStatus.materialUpdate => (
          LocaleKeys.swapReviewUpdatedBadge.tr(),
          SwapTone.warning,
        ),
        SwapReviewStatus.starting => (
          LocaleKeys.swapReviewStartingBadge.tr(),
          SwapTone.info,
        ),
        SwapReviewStatus.rejected || SwapReviewStatus.unconfirmed => null,
      };
}
