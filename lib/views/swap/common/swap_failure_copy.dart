import 'package:decimal/decimal.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_state.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/shared/swap/swap_catalog.dart';
import 'package:web_dex/shared/swap/swap_networks.dart';
import 'package:web_dex/shared/swap/swap_quote.dart';
import 'package:web_dex/shared/swap/swap_quote_failure.dart';
import 'package:web_dex/views/swap/common/swap_format.dart';

/// The entry form's message and primary action for a pricing failure.
class SwapFailureCopy {
  const SwapFailureCopy({
    required this.message,
    this.detail,
    this.action = SwapEntryAction.retry,
    this.amount,
  });

  final String message;
  final String? detail;
  final SwapEntryAction action;

  /// For [SwapEntryAction.useAmount]: the amount of the pay asset to use.
  final Decimal? amount;

  /// The copy for [failure], the evaluation's primary failure; [all] is every
  /// source's, so a firm answer can say another source could not answer.
  /// [amount] is what was asked and [balance] what the wallet can spend, so
  /// an amount that would fill is offered only when it can be paid.
  static SwapFailureCopy of(
    SwapQuoteFailure failure,
    AssetId? pay, {
    AssetId? receive,
    List<SwapQuoteFailure> all = const [],
    SwapPairSupport? support,
    SwapNetworks? networks,
    Decimal? amount,
    Decimal? balance,
  }) {
    String ticker(AssetId? asset) =>
        asset == null ? '' : SwapFormat.ticker(asset);
    return switch (failure.kind) {
      SwapQuoteFailureKind.assetInactive => SwapFailureCopy(
        message: LocaleKeys.swapErrorInactive.tr(
          args: [ticker(failure.asset ?? pay)],
        ),
        action: SwapEntryAction.activate,
      ),
      SwapQuoteFailureKind.pairUnsupported => SwapFailureCopy(
        message: LocaleKeys.swapErrorPairUnsupported.tr(),
        action: SwapEntryAction.chooseAnother,
      ),
      SwapQuoteFailureKind.belowMinimum => _bound(
        failure,
        pay,
        above: false,
        balance: balance,
      ),
      SwapQuoteFailureKind.aboveMaximum => _bound(
        failure,
        pay,
        above: true,
        balance: balance,
      ),
      SwapQuoteFailureKind.noRoute => _noRoute(
        failure,
        all,
        support,
        pay: pay,
        receive: receive,
        networks: networks,
        amount: amount,
        balance: balance,
      ),
      SwapQuoteFailureKind.rateLimited => SwapFailureCopy(
        message: LocaleKeys.swapErrorRateLimited.tr(),
        action: SwapEntryAction.wait,
      ),
      SwapQuoteFailureKind.serviceError => SwapFailureCopy(
        message: _serviceMessage(failure, pay, networks),
      ),
      SwapQuoteFailureKind.timeout => SwapFailureCopy(
        message: LocaleKeys.swapErrorTimeout.tr(),
      ),
      SwapQuoteFailureKind.invalidAmount => SwapFailureCopy(
        message: LocaleKeys.swapErrorInvalidAmount.tr(args: [ticker(pay)]),
        action: SwapEntryAction.none,
      ),
      SwapQuoteFailureKind.insufficientFunds => SwapFailureCopy(
        message: LocaleKeys.swapErrorInsufficientFunds.tr(
          args: [ticker(failure.asset ?? pay)],
        ),
        action: SwapEntryAction.none,
      ),
      SwapQuoteFailureKind.unsupportedSigner => SwapFailureCopy(
        message: LocaleKeys.swapErrorUnsupportedSigner.tr(),
        action: SwapEntryAction.chooseAnother,
      ),
      SwapQuoteFailureKind.notConfigured => SwapFailureCopy(
        message: LocaleKeys.swapErrorNotConfigured.tr(),
        action: SwapEntryAction.chooseAnother,
      ),
      SwapQuoteFailureKind.tradingBlocked => SwapFailureCopy(
        message: LocaleKeys.tradingDisabled.tr(),
        action: SwapEntryAction.none,
      ),
      SwapQuoteFailureKind.clockInvalid => SwapFailureCopy(
        message: LocaleKeys.swapErrorClock.tr(),
        action: SwapEntryAction.none,
      ),
      SwapQuoteFailureKind.signedOut => SwapFailureCopy(
        message: LocaleKeys.swapErrorSignedOutRoutes.tr(),
        action: SwapEntryAction.connect,
      ),
      SwapQuoteFailureKind.unknown => SwapFailureCopy(
        message: LocaleKeys.swapErrorUnknown.tr(),
      ),
    };
  }

  /// The minimum or maximum the amount crossed, and a switch to it.
  static SwapFailureCopy _bound(
    SwapQuoteFailure failure,
    AssetId? pay, {
    required bool above,
    Decimal? balance,
  }) {
    final bound = above ? failure.maximum : failure.minimum;
    if (bound == null || pay == null) {
      return SwapFailureCopy(
        message: above
            ? LocaleKeys.swapErrorAboveMaximum.tr(args: [''])
            : LocaleKeys.swapErrorTooSmall.tr(),
        action: SwapEntryAction.none,
      );
    }
    final rounding = above ? SwapRounding.down : SwapRounding.up;
    final text = SwapFormat.tokens(
      bound,
      SwapFormat.ticker(pay),
      rounding: rounding,
    );
    // An order-book bound is one trader's order, not a limit of the venue.
    final byOffers = failure.offers != null;
    final message = above
        ? (byOffers
                  ? LocaleKeys.swapErrorOffersAbove
                  : LocaleKeys.swapErrorAboveMaximum)
              .tr(args: [text])
        : (byOffers
                  ? LocaleKeys.swapErrorOffersBelow
                  : LocaleKeys.swapErrorBelowMinimum)
              .tr(args: [text]);
    final usable = _usable(bound, pay, rounding: rounding, balance: balance);
    return SwapFailureCopy(
      message: message,
      action: usable == null ? SwapEntryAction.none : SwapEntryAction.useAmount,
      amount: usable,
    );
  }

  /// [value] as the amount a button offers: at the precision it is shown
  /// with, rounded towards filling, within the asset's decimals. Null when
  /// that is nothing or more than [balance].
  static Decimal? _usable(
    Decimal value,
    AssetId pay, {
    required SwapRounding rounding,
    Decimal? balance,
  }) {
    var usable = SwapFormat.shown(value, rounding: rounding);
    final decimals = pay.chainId.decimals;
    if (decimals != null && usable.scale > decimals) {
      usable = rounding == SwapRounding.up
          ? usable.ceil(scale: decimals)
          : usable.floor(scale: decimals);
    }
    if (usable <= Decimal.zero) return null;
    if (balance != null && usable > balance) return null;
    return usable;
  }

  static SwapFailureCopy _noRoute(
    SwapQuoteFailure failure,
    List<SwapQuoteFailure> all,
    SwapPairSupport? support, {
    AssetId? pay,
    AssetId? receive,
    SwapNetworks? networks,
    Decimal? amount,
    Decimal? balance,
  }) {
    final others = all.where((other) => other.source != failure.source);
    if (others.any((other) => other.isTransient)) {
      return SwapFailureCopy(
        message: failure.source == SwapLiquiditySource.atomic
            ? LocaleKeys.swapErrorNoRouteOrderBook.tr()
            : LocaleKeys.swapErrorNoRouteCrossNetwork.tr(),
      );
    }
    if (others.any((other) => other.kind == SwapQuoteFailureKind.signedOut)) {
      return SwapFailureCopy(
        message: LocaleKeys.swapErrorNoRouteSignedOut.tr(),
        action: SwapEntryAction.connect,
      );
    }
    final offers = failure.offers;
    if (offers != null && !offers.isEmpty && amount != null && pay != null) {
      final below = offers.largestUpTo(amount);
      final above = offers.smallestFrom(amount);
      if (below != null && above != null) {
        final ticker = SwapFormat.ticker(pay);
        final usable =
            _usable(
              below,
              pay,
              rounding: SwapRounding.down,
              balance: balance,
            ) ??
            _usable(above, pay, rounding: SwapRounding.up, balance: balance);
        return SwapFailureCopy(
          message: LocaleKeys.swapErrorOffersGap.tr(
            args: [
              SwapFormat.tokens(amount, ticker),
              SwapFormat.tokens(below, ticker, rounding: SwapRounding.down),
              SwapFormat.tokens(above, ticker, rounding: SwapRounding.up),
            ],
          ),
          action: usable == null
              ? SwapEntryAction.none
              : SwapEntryAction.useAmount,
          amount: usable,
        );
      }
    }
    final String? detail;
    if (failure.reasons.isNotEmpty) {
      detail = LocaleKeys.swapHelperNoRouteReasons.tr(
        args: [failure.reasons.join(' · ')],
      );
    } else if (support?.routesUnavailableFor case final AssetId asset) {
      final other = asset == pay ? receive : pay;
      final ticker = SwapFormat.ticker(asset);
      // "1INCH trades only on the order book" says nothing when both sides
      // are 1INCH.
      final sameTicker = other != null && SwapFormat.ticker(other) == ticker;
      detail = LocaleKeys.swapHelperOrderBookOnly.tr(
        args: [
          if (sameTicker && networks != null)
            LocaleKeys.swapAssetOnNetwork.tr(
              args: [ticker, networks.networkOf(asset)],
            )
          else
            ticker,
        ],
      );
    } else {
      detail = null;
    }
    return SwapFailureCopy(
      message: LocaleKeys.swapErrorNoRoute.tr(),
      detail: detail,
    );
  }

  /// A token's cross-network quote fails as a service error when the node
  /// cannot estimate its approval, which is what an address short of the
  /// network's own coin produces. That cause is only likely, never known,
  /// so the copy suggests the check rather than asserting it.
  static String _serviceMessage(
    SwapQuoteFailure failure,
    AssetId? pay,
    SwapNetworks? networks,
  ) {
    final parent = pay?.parentId;
    if (failure.source == SwapLiquiditySource.routed &&
        parent != null &&
        networks != null) {
      return LocaleKeys.swapErrorServiceToken.tr(
        args: [SwapFormat.ticker(parent), networks.networkOf(parent)],
      );
    }
    return LocaleKeys.swapErrorService.tr();
  }
}

/// The entry form's primary action when pricing failed.
enum SwapEntryAction {
  /// Price again.
  retry,

  /// Activate the inactive asset.
  activate,

  /// Pick a different asset.
  chooseAnother,

  /// Wait out a rate limit.
  wait,

  /// Switch to an amount that fills.
  useAmount,

  /// Connect a wallet, which the source that could answer needs.
  connect,

  /// Nothing to do but change the amount.
  none,
}

/// The entry form's message for a form issue.
class SwapIssueCopy {
  const SwapIssueCopy({
    required this.message,
    this.detail,
    this.action = SwapEntryAction.none,
  });

  final String message;
  final String? detail;
  final SwapEntryAction action;

  /// The copy for [issue] in [state], or null for "not finished yet": no
  /// amount, or no wallet.
  static SwapIssueCopy? of(
    SwapFormIssue issue,
    UnifiedSwapState state, {
    required SwapNetworks networks,
    String? feeNeeded,
    String? feeHeld,
  }) {
    final pay = state.pay;
    final ticker = pay == null ? '' : SwapFormat.ticker(pay);
    return switch (issue) {
      SwapFormIssue.amountMissing || SwapFormIssue.signedOut => null,
      SwapFormIssue.pairUnsupported => _pairUnsupported(
        state.pairSupport,
        networks,
      ),
      SwapFormIssue.noOffers => SwapIssueCopy(
        message: LocaleKeys.swapErrorNoOffers.tr(
          args: [
            if (state.receive case final receive?) SwapFormat.ticker(receive),
            ticker,
          ],
        ),
        action: SwapEntryAction.chooseAnother,
      ),
      SwapFormIssue.assetInactive => SwapIssueCopy(
        message: LocaleKeys.swapErrorInactive.tr(
          args: [SwapFormat.ticker(state.inactiveAsset ?? pay!)],
        ),
        action: SwapEntryAction.activate,
      ),
      SwapFormIssue.noFeeBalance => SwapIssueCopy(
        message: LocaleKeys.swapErrorNoFeeBalance.tr(
          args: [
            SwapFormat.ticker(pay!.parentId!),
            networks.networkOf(pay.parentId!),
          ],
        ),
      ),
      SwapFormIssue.amountMalformed => SwapIssueCopy(
        message: LocaleKeys.swapErrorMalformed.tr(),
      ),
      SwapFormIssue.amountZero => SwapIssueCopy(
        message: LocaleKeys.swapErrorZero.tr(),
      ),
      SwapFormIssue.tooManyDecimals => SwapIssueCopy(
        message: LocaleKeys.swapErrorTooManyDecimals.tr(
          args: [ticker, '${pay?.chainId.decimals ?? 8}'],
        ),
      ),
      SwapFormIssue.insufficient => SwapIssueCopy(
        message: LocaleKeys.swapErrorInsufficient.tr(
          args: [
            if (state.balance case final Decimal balance)
              SwapFormat.tokens(balance, ticker, rounding: SwapRounding.down)
            else
              ticker,
          ],
        ),
      ),
      SwapFormIssue.insufficientForFees => SwapIssueCopy(
        message: LocaleKeys.swapErrorInsufficientForFees.tr(
          args: [feeNeeded ?? '', feeHeld ?? ''],
        ),
      ),
      SwapFormIssue.sameAsset => SwapIssueCopy(
        message: LocaleKeys.swapErrorSameAsset.tr(),
        action: SwapEntryAction.chooseAnother,
      ),
      SwapFormIssue.fiatUnavailable => SwapIssueCopy(
        message: LocaleKeys.swapErrorFiatUnavailable.tr(args: [ticker, ticker]),
      ),
    };
  }

  static SwapIssueCopy _pairUnsupported(
    SwapPairSupport? support,
    SwapNetworks networks,
  ) {
    final limiting = support?.limitingAsset;
    final routesOnly = support?.routesOnlyAsset;
    if (limiting == null) {
      return SwapIssueCopy(
        message: LocaleKeys.swapErrorPairUnsupported.tr(),
        action: SwapEntryAction.chooseAnother,
      );
    }
    if (support?.gap == SwapPairGap.notTradable || routesOnly == null) {
      return SwapIssueCopy(
        message: LocaleKeys.swapErrorNotTradable.tr(
          args: [SwapFormat.ticker(limiting)],
        ),
        action: SwapEntryAction.chooseAnother,
      );
    }
    return SwapIssueCopy(
      message: LocaleKeys.swapErrorPairDisjoint.tr(
        args: [SwapFormat.ticker(routesOnly), SwapFormat.ticker(limiting)],
      ),
      detail: routesReachDetail(limiting, networks),
      action: SwapEntryAction.chooseAnother,
    );
  }
}

/// Why cross-network routes cannot trade [asset].
String routesReachDetail(AssetId asset, SwapNetworks networks) =>
    SwapNetworks.evmChainIdOf(asset) != null
    ? LocaleKeys.swapHelperRoutesNoNetwork.tr(args: [networks.networkOf(asset)])
    : LocaleKeys.swapHelperRoutesEvmOnly.tr();
