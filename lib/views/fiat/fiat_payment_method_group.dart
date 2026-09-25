import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:web_dex/bloc/fiat/fiat_onramp_form/fiat_form_bloc.dart';
import 'package:web_dex/bloc/fiat/models/fiat_payment_method.dart';
import 'package:web_dex/views/fiat/fiat_payment_method_card.dart';

class FiatPaymentMethodGroup extends StatelessWidget {
  const FiatPaymentMethodGroup({
    required SliverGridDelegate gridDelegate,
    required this.methods,
    required this.selectedPaymentMethod,
    required this.providerId,
    required this.fiatAmount,
    super.key,
  }) : _gridDelegate = gridDelegate;

  final SliverGridDelegate _gridDelegate;
  final String providerId;
  final List<FiatPaymentMethod> methods;
  final FiatPaymentMethod? selectedPaymentMethod;
  final String fiatAmount;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      color: Theme.of(context).scaffoldBackgroundColor,
      elevation: 4,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: Theme.of(context).primaryColor.withValues(
            alpha:
                selectedPaymentMethod != null &&
                    selectedPaymentMethod!.providerId == providerId
                ? 1
                : 0.25,
          ),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(providerId),
            const SizedBox(height: 16),
            GridView.builder(
              shrinkWrap: true,
              itemCount: methods.length,
              // TODO: Improve responsiveness by making crossAxisCount dynamic based on
              // min and max child width.
              gridDelegate: _gridDelegate,
              itemBuilder: (context, index) {
                final method = methods[index];
                final providerId = method.providerId.toLowerCase();
                return FiatPaymentMethodCard(
                  key: Key('fiat-payment-method-$providerId-$index'),
                  fiatAmount: fiatAmount,
                  paymentMethodData: method,
                  selectedPaymentMethod: selectedPaymentMethod,
                  onSelect: (method) => context.read<FiatFormBloc>().add(
                    FiatFormPaymentMethodSelected(method),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
