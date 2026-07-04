import 'package:decimal/decimal.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';

sealed class WithdrawFormEvent {
  const WithdrawFormEvent();
}

class WithdrawFormRecipientChanged extends WithdrawFormEvent {
  final String address;
  const WithdrawFormRecipientChanged(this.address);
}

class WithdrawFormAmountChanged extends WithdrawFormEvent {
  final String amount;
  const WithdrawFormAmountChanged(this.amount);
}

class WithdrawFormSourceChanged extends WithdrawFormEvent {
  final PubkeyInfo address;
  const WithdrawFormSourceChanged(this.address);
}

class WithdrawFormMaxAmountEnabled extends WithdrawFormEvent {
  final bool isEnabled;
  const WithdrawFormMaxAmountEnabled(this.isEnabled);
}

class WithdrawFormCustomFeeEnabled extends WithdrawFormEvent {
  final bool isEnabled;
  const WithdrawFormCustomFeeEnabled(this.isEnabled);
}

class WithdrawFormCustomFeeChanged extends WithdrawFormEvent {
  final FeeInfo fee;
  const WithdrawFormCustomFeeChanged(this.fee);
}

/// Toggles the gas-free (gasless) rail for a TRC20 withdrawal.
class WithdrawFormGaslessToggled extends WithdrawFormEvent {
  final bool isEnabled;
  const WithdrawFormGaslessToggled(this.isEnabled);
}

/// Sets an optional max-fee cap (in token units) for a gasless withdrawal.
class WithdrawFormGaslessMaxFeeChanged extends WithdrawFormEvent {
  final Decimal? maxFee;
  const WithdrawFormGaslessMaxFeeChanged(this.maxFee);
}

/// Requests a (cached) `gasless::account_status` snapshot for the asset.
/// [force] bypasses the TTL cache, e.g. for a user-initiated retry.
class WithdrawFormGaslessStatusRequested extends WithdrawFormEvent {
  final bool force;
  const WithdrawFormGaslessStatusRequested({this.force = false});
}

class WithdrawFormFeePriorityChanged extends WithdrawFormEvent {
  final WithdrawalFeeLevel? priority;
  const WithdrawFormFeePriorityChanged(this.priority);
}

class WithdrawFormMemoChanged extends WithdrawFormEvent {
  final String? memo;
  const WithdrawFormMemoChanged(this.memo);
}

class WithdrawFormPreviewSubmitted extends WithdrawFormEvent {
  const WithdrawFormPreviewSubmitted();
}

class WithdrawFormSubmitted extends WithdrawFormEvent {
  const WithdrawFormSubmitted();
}

class WithdrawFormTronPreviewTicked extends WithdrawFormEvent {
  const WithdrawFormTronPreviewTicked();
}

class WithdrawFormTronPreviewRefreshRequested extends WithdrawFormEvent {
  final bool isAutomatic;

  const WithdrawFormTronPreviewRefreshRequested({this.isAutomatic = false});
}

class WithdrawFormCancelled extends WithdrawFormEvent {
  const WithdrawFormCancelled();
}

class WithdrawFormReset extends WithdrawFormEvent {
  const WithdrawFormReset();
}

class WithdrawFormIbcTransferEnabled extends WithdrawFormEvent {
  final bool isEnabled;
  WithdrawFormIbcTransferEnabled(this.isEnabled);
}

class WithdrawFormIbcChannelChanged extends WithdrawFormEvent {
  final String channel;
  WithdrawFormIbcChannelChanged(this.channel);
}

class WithdrawFormSourcesLoadRequested extends WithdrawFormEvent {
  const WithdrawFormSourcesLoadRequested();
}

class WithdrawFormFeeOptionsRequested extends WithdrawFormEvent {
  const WithdrawFormFeeOptionsRequested();
}

class WithdrawFormStepReverted extends WithdrawFormEvent {
  const WithdrawFormStepReverted();
}

class WithdrawFormConvertAddressRequested extends WithdrawFormEvent {
  const WithdrawFormConvertAddressRequested();
}
