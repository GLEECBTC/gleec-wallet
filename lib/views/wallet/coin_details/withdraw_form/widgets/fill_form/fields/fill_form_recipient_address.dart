import 'dart:io';

import 'package:app_theme/app_theme.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:komodo_ui/komodo_ui.dart';
import 'package:web_dex/bloc/withdraw_form/withdraw_form_bloc.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/mm2/mm2_api/rpc/base.dart';
import 'package:web_dex/views/wallet/coin_details/withdraw_form/widgets/fill_form/buttons/convert_address_button.dart';
import 'package:komodo_ui_kit/komodo_ui_kit.dart';

class FillFormRecipientAddress extends StatefulWidget {
  const FillFormRecipientAddress({super.key});

  @override
  State<FillFormRecipientAddress> createState() =>
      _FillFormRecipientAddressState();
}

class _FillFormRecipientAddressState extends State<FillFormRecipientAddress> {
  final TextEditingController _addressController = TextEditingController();
  TextSelection _previousTextSelection = const TextSelection.collapsed(
    offset: 0,
  );

  @override
  Widget build(BuildContext context) {
    return BlocSelector<WithdrawFormBloc, WithdrawFormState, BaseError?>(
      selector: (state) {
        //TODO! return state.addressError;
        return state.amountError;
      },
      builder: (context, addressError) {
        return BlocSelector<WithdrawFormBloc, WithdrawFormState, String>(
          selector: (state) => state.recipientAddress,
          builder: (context, address) {
            _addressController
              ..text = address
              ..selection = _previousTextSelection;
            return Column(
              children: [
                UiTextFormField(
                  key: const Key('withdraw-recipient-address-input'),
                  controller: _addressController,
                  autofocus: true,
                  autocorrect: false,
                  textInputAction: TextInputAction.next,
                  enableInteractiveSelection: true,
                  onChanged: (String? address) {
                    setState(() {
                      _previousTextSelection = _addressController.selection;
                    });
                    context.read<WithdrawFormBloc>().add(
                      WithdrawFormRecipientChanged(address ?? ''),
                    );
                  },
                  validator: (String? value) {
                    if (addressError?.message.isEmpty ?? true) return null;
                    if (addressError is MixedCaseAddressError) {
                      return null;
                    }
                    return addressError!.message;
                  },
                  validationMode: InputValidationMode.aggressive,
                  inputFormatters: [LengthLimitingTextInputFormatter(256)],
                  hintText: LocaleKeys.recipientAddress.tr(),
                  hintTextStyle: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                  suffixIcon:
                      (!kIsWeb && (Platform.isAndroid || Platform.isIOS))
                      ? IconButton(
                          icon: const Icon(Icons.qr_code_scanner),
                          onPressed: () async {
                            final address = await Navigator.push<String>(
                              context,
                              MaterialPageRoute(
                                builder: (context) =>
                                    const QrCodeReaderOverlay(),
                              ),
                            );

                            if (context.mounted) {
                              context.read<WithdrawFormBloc>().add(
                                WithdrawFormRecipientChanged(address ?? ''),
                              );
                            }
                          },
                        )
                      : null,
                ),
                if (addressError is MixedCaseAddressError)
                  _ErrorAddressRow(error: addressError),
              ],
            );
          },
        );
      },
    );
  }
}

class _ErrorAddressRow extends StatelessWidget {
  const _ErrorAddressRow({required this.error});
  final MixedCaseAddressError error;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(maxWidth: theme.custom.dexFormWidth),
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisSize: MainAxisSize.max,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            child: SelectableText(
              error.message,
              style: const TextStyle(fontSize: 12),
            ),
          ),
          const Padding(
            padding: EdgeInsets.only(left: 6.0),
            child: ConvertAddressButton(),
          ),
        ],
      ),
    );
  }
}
