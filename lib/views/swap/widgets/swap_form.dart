import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:komodo_ui/komodo_ui.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_bloc.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_event.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_state.dart';
import 'package:web_dex/views/swap/widgets/swap_quote_summary.dart';

/// The swap entry form: two assets, an amount, and a price.
class SwapForm extends StatelessWidget {
  const SwapForm({super.key});

  @override
  Widget build(BuildContext context) {
    final bloc = context.read<UnifiedSwapBloc>();

    return BlocBuilder<UnifiedSwapBloc, UnifiedSwapState>(
      builder: (context, state) {
        return SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _AssetRow(
                label: 'You pay',
                asset: state.sellAsset,
                assets: state.tradableAssets,
                onSelected: (asset) =>
                    bloc.add(UnifiedSwapSellAssetChanged(asset)),
              ),
              const SizedBox(height: 8),
              _AmountField(state: state),
              const SizedBox(height: 8),
              Align(
                child: IconButton(
                  key: const Key('swap-reverse'),
                  tooltip: 'Reverse',
                  icon: const Icon(Icons.swap_vert),
                  onPressed: () => bloc.add(const UnifiedSwapSidesReversed()),
                ),
              ),
              _AssetRow(
                label: 'You receive',
                asset: state.receiveAsset,
                assets: state.tradableAssets,
                onSelected: (asset) =>
                    bloc.add(UnifiedSwapReceiveAssetChanged(asset)),
              ),
              const SizedBox(height: 20),
              _QuoteArea(state: state),
              const SizedBox(height: 20),
              FilledButton(
                key: const Key('swap-review'),
                onPressed: state.canReview
                    ? () => bloc.add(const UnifiedSwapReviewRequested())
                    : null,
                child: const Text('Review swap'),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _AssetRow extends StatelessWidget {
  const _AssetRow({
    required this.label,
    required this.asset,
    required this.assets,
    required this.onSelected,
  });

  final String label;
  final AssetId? asset;
  final Set<AssetId> assets;
  final ValueChanged<AssetId> onSelected;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () async {
        final selected = await showCoinSearch(context, coins: assets.toList());
        if (selected != null) onSelected(selected);
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            Expanded(child: Text(label)),
            if (asset != null) AssetIcon(asset!, size: 20),
            const SizedBox(width: 8),
            Text(asset?.id ?? 'Select asset'),
            const Icon(Icons.chevron_right),
          ],
        ),
      ),
    );
  }
}

class _AmountField extends StatelessWidget {
  const _AmountField({required this.state});

  final UnifiedSwapState state;

  @override
  Widget build(BuildContext context) {
    final bloc = context.read<UnifiedSwapBloc>();

    return TextField(
      key: const Key('swap-amount'),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      onChanged: (value) => bloc.add(UnifiedSwapAmountChanged(value)),
      onSubmitted: (_) => bloc.add(const UnifiedSwapQuoteRequested()),
      decoration: InputDecoration(
        labelText: 'Amount',
        errorText: _errorText,
        suffixIcon: state.spendableBalance == null
            ? null
            : TextButton(
                onPressed: () =>
                    bloc.add(const UnifiedSwapMaxAmountRequested()),
                child: const Text('Max'),
              ),
      ),
    );
  }

  String? get _errorText => switch (state.formError) {
    UnifiedSwapFormError.amountMalformed => 'Enter a valid number.',
    UnifiedSwapFormError.amountNotPositive => 'Amount must be more than 0.',
    UnifiedSwapFormError.amountExceedsBalance =>
      'Only ${state.spendableBalance} ${state.sellAsset?.id ?? ''} is spendable.',
    UnifiedSwapFormError.sameAsset => 'Choose two different assets.',
    // An empty field is not an error yet — the user has simply not finished.
    UnifiedSwapFormError.amountMissing || null => null,
  };
}

class _QuoteArea extends StatelessWidget {
  const _QuoteArea({required this.state});

  final UnifiedSwapState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bloc = context.read<UnifiedSwapBloc>();

    switch (state.quoteStatus) {
      case UnifiedSwapQuoteStatus.idle:
        return TextButton(
          key: const Key('swap-get-price'),
          onPressed: state.canRequestQuote
              ? () => bloc.add(const UnifiedSwapQuoteRequested())
              : null,
          child: const Text('Get price'),
        );
      case UnifiedSwapQuoteStatus.loading:
        return const Center(child: CircularProgressIndicator());
      case UnifiedSwapQuoteStatus.ready:
        return SwapQuoteSummary(quote: state.selectedQuote!);
      case UnifiedSwapQuoteStatus.unsupported:
        // Permanent. Offering a retry here would be a lie — no source will
        // ever price this pair, most often because no aggregator indexes one
        // of the chains involved.
        return Text(
          'This pair cannot be swapped in the wallet.',
          key: const Key('swap-unsupported'),
          style: theme.textTheme.bodyMedium,
        );
      case UnifiedSwapQuoteStatus.unavailable:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'No price available right now.',
              key: const Key('swap-unavailable'),
              style: theme.textTheme.bodyMedium,
            ),
            TextButton(
              onPressed: () => bloc.add(const UnifiedSwapQuoteRequested()),
              child: const Text('Try again'),
            ),
          ],
        );
    }
  }
}
