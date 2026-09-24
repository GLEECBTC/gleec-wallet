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
  });

  final String message;
  final String? detail;
  final SwapEntryAction action;

  /// The copy for [failure], the evaluation's primary failure; [all] is every
  /// source's, so a firm answer can say another source could not answer.
  static SwapFailureCopy of(
    SwapQuoteFailure failure,
    AssetId? pay, {
    List<SwapQuoteFailure> all = const [],
    SwapPairSupport? support,
    SwapNetworks? networks,
  }) {
    String ticker(AssetId? asset) =>
        asset == null ? '' : SwapFormat.ticker(asset);
    final bound = failure.minimum ?? failure.maximum;
    final boundText = bound == null
        ? ''
        : SwapFormat.tokens(bound, ticker(pay), rounding: SwapRounding.up);
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
      SwapQuoteFailureKind.belowMinimum => SwapFailureCopy(
        message: LocaleKeys.swapErrorBelowMinimum.tr(args: [boundText]),
        action: SwapEntryAction.none,
      ),
      SwapQuoteFailureKind.aboveMaximum => SwapFailureCopy(
        message: LocaleKeys.swapErrorAboveMaximum.tr(
          args: [
            failure.maximum == null
                ? ''
                : SwapFormat.tokens(
                    failure.maximum!,
                    ticker(pay),
                    rounding: SwapRounding.down,
                  ),
          ],
        ),
        action: SwapEntryAction.none,
      ),
      SwapQuoteFailureKind.noRoute => _noRoute(failure, all, support),
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
      SwapQuoteFailureKind.unknown => SwapFailureCopy(
        message: LocaleKeys.swapErrorUnknown.tr(),
      ),
    };
  }

  static SwapFailureCopy _noRoute(
    SwapQuoteFailure failure,
    List<SwapQuoteFailure> all,
    SwapPairSupport? support,
  ) {
    final unanswered = all.any(
      (other) => other.source != failure.source && other.isTransient,
    );
    if (unanswered) {
      return SwapFailureCopy(
        message: failure.source == SwapLiquiditySource.atomic
            ? LocaleKeys.swapErrorNoRouteOrderBook.tr()
            : LocaleKeys.swapErrorNoRouteCrossNetwork.tr(),
      );
    }
    final String? detail;
    if (failure.reasons.isNotEmpty) {
      detail = LocaleKeys.swapHelperNoRouteReasons.tr(
        args: [failure.reasons.join(' · ')],
      );
    } else if (support?.routesUnavailableFor case final AssetId asset) {
      detail = LocaleKeys.swapHelperOrderBookOnly.tr(
        args: [SwapFormat.ticker(asset)],
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

  /// The copy for [issue] in [state], or null for "not finished yet".
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
      SwapFormIssue.amountMissing => null,
      SwapFormIssue.pairUnsupported => _pairUnsupported(
        state.pairSupport,
        networks,
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
