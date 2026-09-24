import 'package:decimal/decimal.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_state.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
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

  static SwapFailureCopy of(SwapQuoteFailure failure, AssetId? pay) {
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
      SwapQuoteFailureKind.noRoute => SwapFailureCopy(
        message: LocaleKeys.swapErrorNoRoute.tr(),
        detail: failure.reasons.isEmpty
            ? null
            : LocaleKeys.swapHelperNoRouteReasons.tr(
                args: [failure.reasons.join(' · ')],
              ),
      ),
      SwapQuoteFailureKind.rateLimited => SwapFailureCopy(
        message: LocaleKeys.swapErrorRateLimited.tr(),
        action: SwapEntryAction.wait,
      ),
      SwapQuoteFailureKind.serviceError => SwapFailureCopy(
        message: LocaleKeys.swapErrorService.tr(),
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

/// The message for a form issue, or null for "not finished yet".
String? swapIssueMessage(
  SwapFormIssue issue, {
  required AssetId? pay,
  required Decimal? balance,
  String? feeNeeded,
  String? feeHeld,
}) {
  final ticker = pay == null ? '' : SwapFormat.ticker(pay);
  return switch (issue) {
    SwapFormIssue.amountMissing => null,
    SwapFormIssue.amountMalformed => LocaleKeys.swapErrorMalformed.tr(),
    SwapFormIssue.amountZero => LocaleKeys.swapErrorZero.tr(),
    SwapFormIssue.tooManyDecimals => LocaleKeys.swapErrorTooManyDecimals.tr(
      args: [ticker, '${pay?.chainId.decimals ?? 8}'],
    ),
    SwapFormIssue.insufficient => LocaleKeys.swapErrorInsufficient.tr(
      args: [
        balance == null
            ? ticker
            : SwapFormat.tokens(balance, ticker, rounding: SwapRounding.down),
      ],
    ),
    SwapFormIssue.insufficientForFees =>
      LocaleKeys.swapErrorInsufficientForFees.tr(
        args: [feeNeeded ?? '', feeHeld ?? ''],
      ),
    SwapFormIssue.sameAsset => LocaleKeys.swapErrorSameAsset.tr(),
    SwapFormIssue.fiatUnavailable => LocaleKeys.swapErrorFiatUnavailable.tr(
      args: [ticker, ticker],
    ),
  };
}
