import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:komodo_ui_kit/komodo_ui_kit.dart';
import 'package:web_dex/bloc/auth_bloc/auth_bloc.dart';
import 'package:web_dex/bloc/fiat/fiat_onramp_form/fiat_form_bloc.dart';
import 'package:web_dex/bloc/fiat/fiat_order_status.dart';
import 'package:web_dex/bloc/fiat/models/fiat_mode.dart';
import 'package:web_dex/bloc/fiat/models/i_currency.dart';
import 'package:web_dex/common/screen.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/model/forms/fiat/fiat_amount_input.dart';
import 'package:web_dex/shared/utils/fiat_format.dart';
import 'package:web_dex/shared/widgets/connect_wallet/connect_wallet_wrapper.dart';
import 'package:web_dex/views/fiat/fiat_action_tab.dart';
import 'package:web_dex/views/fiat/fiat_inputs.dart';
import 'package:web_dex/views/fiat/fiat_payment_methods_grid.dart';
import 'package:web_dex/views/fiat/fiat_provider_web_view_settings.dart';
import 'package:web_dex/views/fiat/webview_dialog.dart';
import 'package:web_dex/views/wallets_manager/wallets_manager_events_factory.dart';

class FiatForm extends StatefulWidget {
  const FiatForm({super.key});

  @override
  State<FiatForm> createState() => _FiatFormState();
}

class _FiatFormState extends State<FiatForm> {
  bool _isLoggedIn = false;
  late ScrollController _scrollController;

  @override
  void initState() {
    super.initState();

    _isLoggedIn = RepositoryProvider.of<AuthBloc>(context).state.isSignedIn;

    // Initialize scroll controller and add listener for keyboard dismissal
    _scrollController = ScrollController();
    _scrollController.addListener(_onScroll);

    final fiatFormBloc = context.read<FiatFormBloc>()
      ..add(const FiatFormCurrenciesRefreshRequested())
      ..add(const FiatFormPaymentMethodsRefreshRequested());

    if (_isLoggedIn) {
      fiatFormBloc.add(
        FiatFormCoinSelected(
          fiatFormBloc.state.selectedAsset.value ?? CryptoCurrency.bitcoin(),
        ),
      );
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    // Dismiss keyboard when user starts scrolling
    FocusScope.of(context).unfocus();
  }

  @override
  Widget build(BuildContext context) {
    // TODO: Add optimisations to re-use the generated checkout URL if the user
    // submits the form again without changing any data. When the user presses
    // the "Buy Now" button, we create the checkout URL and open it in a new
    // tab.
    // Previously we would also navigate them to a separate page with a button
    // in case they needed to open the checkout page again, but we removed that
    // because it confused users on how to return and was not needed since user
    // can just press the "Buy Now" button again.
    // However! This may cause issues in the future when implement the order
    // history tab since some providers require creating an order before
    // creating the checkout URL. This could clutter up the order history with
    // orders that were never completed.

    return BlocListener<AuthBloc, AuthBlocState>(
      listener: (context, state) {
        _handleAccountStatusChange(state.isSignedIn);
      },
      child: BlocConsumer<FiatFormBloc, FiatFormState>(
        listenWhen: (previous, current) =>
            previous.fiatOrderStatus != current.fiatOrderStatus,
        listener: (context, state) => _handlePaymentStatusUpdate(state),
        builder: (context, state) => GestureDetector(
          onTap: () => FocusScope.of(context).unfocus(),
          child: DexScrollbar(
            isMobile: isMobile,
            scrollController: _scrollController,
            child: SingleChildScrollView(
              key: const Key('fiat-form-scroll'),
              controller: _scrollController,
              child: Column(
                children: [
                  FiatActionTabBar(
                    currentTabIndex: state.fiatMode.tabIndex,
                    onTabClick: _setActiveTab,
                  ),
                  const SizedBox(height: 16),
                  if (state.fiatMode == FiatMode.offramp)
                    Center(child: Text(LocaleKeys.comingSoon.tr()))
                  else
                    DecoratedBox(
                      decoration: AppSurface.card(AppPalette.of(context)),
                      child: Container(
                        padding: const EdgeInsets.fromLTRB(16, 32, 16, 16),
                        child: Column(
                          children: [
                            FiatInputs(
                              onFiatCurrencyChanged: _onFiatChanged,
                              onCoinChanged: _onCoinChanged,
                              onFiatAmountUpdate: _onFiatAmountChanged,
                              onSourceAddressChanged: _onSourceAddressChanged,
                              initialFiat: state.selectedFiat.value!,
                              selectedAsset: state.selectedAsset.value!,
                              selectedAssetAddress: state.selectedAssetAddress,
                              selectedAssetPubkeys: state.selectedCoinPubkeys,
                              initialFiatAmount:
                                  state.fiatAmount.valueAsDecimal,
                              fiatList: state.fiatList,
                              coinList: state.coinList,
                              selectedPaymentMethodPrice:
                                  state.selectedPaymentMethod.priceInfo,
                              isLoggedIn: _isLoggedIn,
                              fiatMinAmount: state.minFiatAmount,
                              fiatMaxAmount: state.maxFiatAmount,
                              boundariesError: state.fiatAmount.error?.text(
                                state,
                              ),
                            ),
                            const SizedBox(height: 16),
                            FiatPaymentMethodsGrid(state: state),
                            const SizedBox(height: 16),
                            ConnectWalletWrapper(
                              key: const Key('connect-wallet-fiat-form'),
                              eventType: WalletsManagerEventType.fiat,
                              child: UiPrimaryButton(
                                key: const Key('fiat-onramp-submit-button'),
                                height: 40,
                                text: state.fiatOrderStatus.isSubmitting
                                    ? '${LocaleKeys.submitting.tr()}...'
                                    : LocaleKeys.buyNow.tr(),
                                onPressed: state.canSubmit
                                    ? _completeOrder
                                    : null,
                              ),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              _isLoggedIn
                                  ? state.fiatOrderStatus.isFailed
                                        ? LocaleKeys.fiatCantCompleteOrder.tr()
                                        : LocaleKeys.fiatPriceCanChange.tr()
                                  : LocaleKeys.fiatConnectWallet.tr(),
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _completeOrder() {
    // Dismiss keyboard before submitting
    FocusScope.of(context).unfocus();
    context.read<FiatFormBloc>().add(const FiatFormSubmitted());
  }

  void _onFiatChanged(FiatCurrency value) => context.read<FiatFormBloc>()
    ..add(FiatFormFiatSelected(value))
    ..add(const FiatFormPaymentMethodsRefreshRequested());

  void _onCoinChanged(CryptoCurrency value) => context.read<FiatFormBloc>()
    ..add(FiatFormCoinSelected(value))
    ..add(const FiatFormPaymentMethodsRefreshRequested());

  void _onFiatAmountChanged(String? value) => context.read<FiatFormBloc>()
    ..add(FiatFormAmountUpdated(value ?? '0'))
    ..add(const FiatFormPaymentMethodsRefreshRequested());

  void _onSourceAddressChanged(PubkeyInfo? value) {
    context.read<FiatFormBloc>().add(FiatFormAssetAddressUpdated(value));
  }

  void _setActiveTab(int i) =>
      context.read<FiatFormBloc>().add(FiatFormModeUpdated.fromTabIndex(i));

  Future<void> _handleAccountStatusChange(bool isLoggedIn) async {
    if (_isLoggedIn == isLoggedIn) {
      // If the login state hasn't changed, do nothing.
      return;
    }

    setState(() => _isLoggedIn = isLoggedIn);

    if (!mounted) {
      return;
    }

    if (!isLoggedIn) {
      return context.read<FiatFormBloc>().add(const FiatFormResetRequested());
    }

    // Refresh the payment methods and asset addresses (pubkeys)
    // when the user logs in.
    final fiatFormBloc = context.read<FiatFormBloc>();
    fiatFormBloc
      ..add(
        FiatFormCoinSelected(
          fiatFormBloc.state.selectedAsset.value ?? CryptoCurrency.bitcoin(),
        ),
      )
      ..add(const FiatFormPaymentMethodsRefreshRequested());
  }

  void _onConsoleMessage(String message) {
    context.read<FiatFormBloc>().add(
      FiatFormPaymentStatusMessageReceived(message),
    );
  }

  void _onCloseWebView() {
    // When the webview is closed, dispatch an event to reset the form
    // if the order is not currently in progress
    context.read<FiatFormBloc>().add(const FiatFormWebViewClosed());
  }

  Future<void> _handlePaymentStatusUpdate(FiatFormState stateSnapshot) async {
    //TODO? We can still show the alerts if we're no mounted by using the
    // app's navigator key. This will be useful if the user has navigated
    // to another page before completing the order.
    if (!mounted) return;

    final status = stateSnapshot.fiatOrderStatus;
    if (status == FiatOrderStatus.submitted) {
      context.read<FiatFormBloc>().add(const FiatFormOrderStatusWatchStarted());

      await WebViewDialog.show(
        context,
        url: stateSnapshot.checkoutUrl,
        mode: stateSnapshot.webViewMode,
        title: LocaleKeys.buy.tr(),
        onMessage: _onConsoleMessage,
        onCloseWindow: _onCloseWebView,
        settings: FiatProviderWebViewSettings.createSecureProviderSettings(),
      );
    }

    if (status == FiatOrderStatus.windowCloseRequested) {
      Navigator.of(context).pop();
    }

    if (status != FiatOrderStatus.initial) {
      await _showPaymentStatusDialog(stateSnapshot);
    }
  }

  Future<void> _showPaymentStatusDialog(FiatFormState state) async {
    if (!mounted) return;

    String? title;
    String? content;
    Icon? icon;

    final status = state.fiatOrderStatus;

    switch (status) {
      case FiatOrderStatus.inProgress:
      case FiatOrderStatus.windowCloseRequested:
      case FiatOrderStatus.initial:
      case FiatOrderStatus.submitting:
      case FiatOrderStatus.pendingPayment:
        debugPrint('Pending status should not be shown in dialog.');
        return;
      case FiatOrderStatus.submitted:
        title = LocaleKeys.fiatPaymentSubmittedTitle.tr();
        content = LocaleKeys.fiatPaymentSubmittedMessage.tr();
        icon = const Icon(Icons.open_in_new);
      case FiatOrderStatus.success:
        title = LocaleKeys.fiatPaymentSuccessTitle.tr();
        content = LocaleKeys.fiatPaymentSuccessMessage.tr();
        icon = const Icon(Icons.check_circle_outline);
      case FiatOrderStatus.failed:
        title = LocaleKeys.fiatPaymentFailedTitle.tr();
        content = LocaleKeys.fiatPaymentFailedMessage.tr();
        if (state.providerError != null && state.providerError!.isNotEmpty) {
          content =
              '$content\n\n${LocaleKeys.errorDetails.tr()}: '
              '${state.providerError}';
        }
        icon = Icon(Icons.error_outline, color: AppPalette.of(context).danger);
    }

    await showAdaptiveDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (context) => AlertDialog.adaptive(
        title: Text(title!),
        icon: icon,
        content: Text(content!),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(LocaleKeys.ok.tr()),
          ),
        ],
      ),
    );
  }
}

extension on FiatAmountValidationError {
  String? text(FiatFormState state) {
    final fiatId = state.selectedFiat.value?.symbol ?? '';
    switch (this) {
      case FiatAmountValidationError.aboveMaximum:
        final max = state.maxFiatAmount;
        return LocaleKeys.fiatMaximumAmount.tr(
          args: [max == null ? '' : FiatFormat.number(max.toDouble()), fiatId],
        );
      case FiatAmountValidationError.invalid:
      case FiatAmountValidationError.belowMinimum:
        final min = state.minFiatAmount;
        return LocaleKeys.fiatMinimumAmount.tr(
          args: [min == null ? '' : FiatFormat.number(min.toDouble()), fiatId],
        );
      case FiatAmountValidationError.empty:
        return null;
    }
  }
}
