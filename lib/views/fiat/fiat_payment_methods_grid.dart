import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:komodo_ui_kit/komodo_ui_kit.dart';
import 'package:web_dex/bloc/fiat/fiat_onramp_form/fiat_form_bloc.dart';
import 'package:web_dex/bloc/fiat/models/fiat_payment_method.dart';
import 'package:web_dex/common/screen.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/views/fiat/fiat_payment_method_group.dart';

class FiatPaymentMethodsGrid extends StatelessWidget {
  const FiatPaymentMethodsGrid({
    required this.state,
    super.key,
    this.simpleSpinner = true,
  });

  final FiatFormState state;
  final bool simpleSpinner;

  @override
  Widget build(BuildContext context) {
    final isLoading = state.isLoading;
    if (isLoading) {
      return simpleSpinner
          ? const UiSpinner(width: 36, height: 36, strokeWidth: 4)
          : GridView(
              shrinkWrap: true,
              gridDelegate: _gridDelegate,
              children: List.generate(
                4,
                (index) => const Card(child: SkeletonListTile()),
              ),
            );
    }

    final hasPaymentMethods = state.paymentMethods.isNotEmpty;
    final providerFailed =
        state.providerUnavailable ||
        state.currenciesStatus == FiatFormStatus.failure;
    if (providerFailed || !hasPaymentMethods) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            state.providerError ??
                (providerFailed
                    ? LocaleKeys.fiatProviderUnavailable.tr()
                    : LocaleKeys.noOptionsToPurchase.tr(
                        args: [
                          state.selectedAsset.value?.getAbbr() ?? '',
                          state.selectedFiat.value?.getAbbr() ?? '',
                        ],
                      )),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          const SizedBox(height: 8),
          TextButton(
            key: const Key('fiat-provider-retry'),
            onPressed: () => context.read<FiatFormBloc>().add(
              state.currenciesStatus == FiatFormStatus.failure
                  ? const FiatFormCurrenciesRefreshRequested()
                  : const FiatFormPaymentMethodsRefreshRequested(),
            ),
            child: Text(LocaleKeys.tryAgainButton.tr()),
          ),
        ],
      );
    } else {
      final groupedPaymentMethods = groupPaymentMethodsByProviderId(
        state.paymentMethods.toList(),
      );
      return Column(
        children: [
          for (final entry in groupedPaymentMethods.entries) ...[
            FiatPaymentMethodGroup(
              gridDelegate: _gridDelegate,
              providerId: entry.key,
              methods: entry.value,
              fiatAmount: state.fiatAmount.value,
              selectedPaymentMethod: state.selectedPaymentMethod,
            ),
            const SizedBox(height: 16),
          ],
        ],
      );
    }
  }

  Map<String, List<FiatPaymentMethod>> groupPaymentMethodsByProviderId(
    List<FiatPaymentMethod> paymentMethods,
  ) {
    final groupedMethods = <String, List<FiatPaymentMethod>>{};
    for (final method in paymentMethods) {
      final providerId = method.providerId;
      if (!groupedMethods.containsKey(providerId)) {
        groupedMethods[providerId] = [];
      }
      groupedMethods[providerId]!.add(method);
    }
    return groupedMethods;
  }

  SliverGridDelegate get _gridDelegate =>
      SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: isMobile ? 1 : 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        mainAxisExtent: 90,
      );
}
