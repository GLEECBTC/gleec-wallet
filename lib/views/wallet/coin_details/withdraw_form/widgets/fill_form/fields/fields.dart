// TODO! Separate out into individual files and remove unused fields
// form_fields.dart

import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/services.dart' show FilteringTextInputFormatter;
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:decimal/decimal.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:komodo_ui/utils.dart';
import 'package:komodo_ui_kit/komodo_ui_kit.dart';
import 'package:web_dex/bloc/withdraw_form/withdraw_form_bloc.dart';
import 'package:web_dex/shared/utils/formatters.dart';

class ToAddressField extends StatelessWidget {
  const ToAddressField({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<WithdrawFormBloc, WithdrawFormState>(
      builder: (context, state) {
        return UiTextFormField(
          key: const Key('withdraw-recipient-address-input'),
          autofocus: true,
          autocorrect: false,
          textInputAction: TextInputAction.next,
          enableInteractiveSelection: true,
          onChanged: (value) {
            context.read<WithdrawFormBloc>().add(
              WithdrawFormRecipientChanged(value ?? ''),
            );
          },
          validator: (value) {
            if (value?.isEmpty ?? true) {
              return 'Please enter recipient address';
            }
            return null;
          },
          labelText: 'Recipient Address',
          hintText: 'Enter recipient address',
          suffixIcon: IconButton(
            icon: const Icon(Icons.qr_code_scanner),
            onPressed: () async {
              // TODO: Implement QR scanner
            },
          ),
        );
      },
    );
  }
}

class AmountField extends StatelessWidget {
  const AmountField({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<WithdrawFormBloc, WithdrawFormState>(
      builder: (context, state) {
        return Column(
          children: [
            UiTextFormField(
              key: const Key('withdraw-amount-input'),
              enabled: !state.isMaxAmount,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: currencyInputFormatters,
              textInputAction: TextInputAction.next,
              onChanged: (value) {
                context.read<WithdrawFormBloc>().add(
                  WithdrawFormAmountChanged(value ?? ''),
                );
              },
              validator: (value) {
                if (state.isMaxAmount) return null;
                if (value?.isEmpty ?? true) return 'Please enter an amount';

                final amount = Decimal.tryParse(value!);
                if (amount == null) return 'Please enter a valid number';
                if (amount <= Decimal.zero) {
                  return 'Amount must be greater than 0';
                }
                return null;
              },
              labelText: 'Amount',
              hintText: 'Enter amount to send',
              suffix: Text(state.asset.id.id),
            ),
            CheckboxListTile(
              value: state.isMaxAmount,
              onChanged: (value) {
                context.read<WithdrawFormBloc>().add(
                  WithdrawFormMaxAmountEnabled(value ?? false),
                );
              },
              title: Text(LocaleKeys.amountFieldCheckboxListTile.tr()),
            ),
          ],
        );
      },
    );
  }
}

/// Fee configuration section
class FeeSection extends StatelessWidget {
  const FeeSection({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<WithdrawFormBloc, WithdrawFormState>(
      builder: (context, state) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              LocaleKeys.networkFee.tr(),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            const CustomFeeToggle(),
            if (state.isCustomFee) ...[
              const SizedBox(height: 8),
              _buildFeeFields(context, state),
              const SizedBox(height: 8),
              // Fee summary display
              // if (state.customFee != null) ...[
              //   const Divider(),
              //   _buildFeeSummary(context, state.customFee!, state.asset),
              // ],
            ],
          ],
        );
      },
    );
  }

  Widget _buildFeeFields(BuildContext context, WithdrawFormState state) {
    final protocol = state.asset.protocol;

    if (protocol is Erc20Protocol) {
      return const EvmFeeFields();
    } else if (protocol is UtxoProtocol) {
      return const UtxoFeeFields();
    }

    return const SizedBox.shrink();
  }
}

/// Toggle for enabling custom fee configuration
class CustomFeeToggle extends StatelessWidget {
  const CustomFeeToggle({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<WithdrawFormBloc, WithdrawFormState>(
      builder: (context, state) {
        return Row(
          children: [
            UiSwitcher(
              value: state.isCustomFee,
              onChanged: (value) {
                context.read<WithdrawFormBloc>().add(
                  WithdrawFormCustomFeeEnabled(value),
                );
              },
            ),
            const SizedBox(width: 10),
            Expanded(child: Text(LocaleKeys.customFeeToggleTitle.tr())),
          ],
        );
      },
    );
  }
}

/// EVM-specific fee configuration fields (gas price & limit)
class EvmFeeFields extends StatelessWidget {
  const EvmFeeFields({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<WithdrawFormBloc, WithdrawFormState>(
      builder: (context, state) {
        final evmFee = state.customFee as FeeInfoEthGas?;

        return Column(
          children: [
            UiTextFormField(
              labelText: 'Gas Price (Gwei)',
              keyboardType: TextInputType.number,
              initialValue: evmFee?.gasPrice.toString(),
              onChanged: (value) {
                final gasPrice = Decimal.tryParse(value ?? '');
                if (gasPrice != null) {
                  context.read<WithdrawFormBloc>().add(
                    WithdrawFormCustomFeeChanged(
                      FeeInfoEthGas(
                        coin: state.asset.id.id,
                        gasPrice: gasPrice,
                        gas: evmFee?.gas ?? 21000,
                      ),
                    ),
                  );
                }
              },
              helperText: 'Higher gas price = faster confirmation',
            ),
            const SizedBox(height: 8),
            UiTextFormField(
              labelText: 'Gas Limit',
              keyboardType: TextInputType.number,
              initialValue: evmFee?.gas.toString() ?? '21000',
              onChanged: (value) {
                final gas = int.tryParse(value ?? '');
                if (gas != null) {
                  context.read<WithdrawFormBloc>().add(
                    WithdrawFormCustomFeeChanged(
                      FeeInfoEthGas(
                        coin: state.asset.id.id,
                        gasPrice: evmFee?.gasPrice ?? Decimal.one,
                        gas: gas,
                      ),
                    ),
                  );
                }
              },
              helperText: 'Estimated: 21000',
            ),
          ],
        );
      },
    );
  }
}

/// UTXO-specific fee configuration with predefined tiers
class UtxoFeeFields extends StatelessWidget {
  const UtxoFeeFields({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<WithdrawFormBloc, WithdrawFormState>(
      builder: (context, state) {
        final protocol = state.asset.protocol as UtxoProtocol;
        final defaultFee = protocol.txFee ?? 10000;
        final currentFee = state.customFee as FeeInfoUtxoFixed?;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SegmentedButton<int>(
              segments: [
                ButtonSegment(
                  value: defaultFee,
                  label: Text('Standard ($defaultFee)'),
                ),
                ButtonSegment(
                  value: defaultFee * 2,
                  label: Text('Fast (${defaultFee * 2})'),
                ),
                ButtonSegment(
                  value: defaultFee * 5,
                  label: Text('Urgent (${defaultFee * 5})'),
                ),
              ],
              selected: {currentFee?.amount.toBigInt().toInt() ?? defaultFee},
              onSelectionChanged: (values) {
                if (values.isNotEmpty) {
                  context.read<WithdrawFormBloc>().add(
                    WithdrawFormCustomFeeChanged(
                      FeeInfoUtxoFixed(
                        coin: state.asset.id.id,
                        amount: Decimal.fromInt(values.first),
                      ),
                    ),
                  );
                }
              },
            ),
            const SizedBox(height: 8),
            Text(
              'Higher fee = faster confirmation',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        );
      },
    );
  }
}

/// Page for confirming withdrawal details
class ConfirmationPage extends StatelessWidget {
  const ConfirmationPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<WithdrawFormBloc, WithdrawFormState>(
      builder: (context, state) {
        if (state.preview == null) {
          return const Center(child: CircularProgressIndicator());
        }

        return Column(
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _ConfirmationItem(
                      label: 'From',
                      value:
                          state.selectedSourceAddress?.address ??
                          'Default Wallet',
                    ),
                    const SizedBox(height: 12),
                    _ConfirmationItem(
                      label: 'To',
                      value: state.recipientAddress,
                    ),
                    const SizedBox(height: 12),
                    _ConfirmationItem(
                      label: 'Amount',
                      value:
                          '${state.preview!.balanceChanges.netChange.abs()} ${state.asset.id.id}',
                    ),
                    const SizedBox(height: 12),
                    _ConfirmationItem(
                      label: 'Network Fee',
                      value: state.preview!.fee.formatTotal(),
                    ),
                    if (state.memo != null) ...[
                      const SizedBox(height: 12),
                      _ConfirmationItem(label: 'Memo', value: state.memo!),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => context.read<WithdrawFormBloc>().add(
                      const WithdrawFormCancelled(),
                    ),
                    child: Text(LocaleKeys.back.tr()),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: FilledButton(
                    //TODO! onPressed: state.submissionInProgress
                    onPressed: state.isSending
                        ? null
                        : () => context.read<WithdrawFormBloc>().add(
                            const WithdrawFormSubmitted(),
                          ),
                    //TODO! child: state.submissionInProgress
                    child: state.isSending
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(LocaleKeys.confirm.tr()),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

/// Helper widget for displaying confirmation details
class _ConfirmationItem extends StatelessWidget {
  final String label;
  final String value;

  const _ConfirmationItem({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(
              context,
            ).colorScheme.onSurface.withValues(alpha: 0.6),
          ),
        ),
        const SizedBox(height: 4),
        Text(value, style: Theme.of(context).textTheme.bodyLarge),
      ],
    );
  }
}

/// Page showing successful withdrawal
class SuccessPage extends StatelessWidget {
  const SuccessPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<WithdrawFormBloc, WithdrawFormState>(
      builder: (context, state) {
        return Column(
          children: [
            Icon(
              Icons.check_circle_outline,
              size: 64,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 24),
            Text(
              LocaleKeys.successPageHeadline.tr(),
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              LocaleKeys.successPageBodySmall.tr(),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            SelectableText(
              state.result!.txHash,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(LocaleKeys.done.tr()),
            ),
          ],
        );
      },
    );
  }
}

/// Page showing withdrawal failure
class FailurePage extends StatelessWidget {
  const FailurePage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<WithdrawFormBloc, WithdrawFormState>(
      builder: (context, state) {
        return Column(
          children: [
            Icon(
              Icons.error_outline,
              size: 64,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 24),
            Text(
              'Withdrawal Failed',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: Theme.of(context).colorScheme.error,
              ),
            ),
            const SizedBox(height: 16),
            if (state.transactionError != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Text(
                  state.transactionError!.error,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                LocaleKeys.errorTryAgainSupportHint.tr(),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(height: 24),
            OutlinedButton(
              onPressed: () => context.read<WithdrawFormBloc>().add(
                const WithdrawFormCancelled(),
              ),
              child: Text(LocaleKeys.tryAgainButton.tr()),
            ),
          ],
        );
      },
    );
  }
}

class IbcTransferField extends StatelessWidget {
  const IbcTransferField({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<WithdrawFormBloc, WithdrawFormState>(
      builder: (context, state) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                UiSwitcher(
                  value: state.isIbcTransfer,
                  onChanged: (value) {
                    context.read<WithdrawFormBloc>().add(
                      WithdrawFormIbcTransferEnabled(value),
                    );
                  },
                ),
                const SizedBox(width: 10),
                Expanded(child: Text(LocaleKeys.ibcTransferFieldTitle.tr())),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              LocaleKeys.ibcTransferFieldSubtitle.tr(),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        );
      },
    );
  }
}

class IbcChannelField extends StatelessWidget {
  const IbcChannelField({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<WithdrawFormBloc, WithdrawFormState>(
      builder: (context, state) {
        return UiTextFormField(
          key: const Key('withdraw-ibc-channel-input'),
          labelText: LocaleKeys.ibcChannel.tr(),
          hintText: LocaleKeys.ibcChannelHint.tr(),
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          onChanged: (value) {
            context.read<WithdrawFormBloc>().add(
              WithdrawFormIbcChannelChanged(value ?? ''),
            );
          },
        );
      },
    );
  }
}
