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
