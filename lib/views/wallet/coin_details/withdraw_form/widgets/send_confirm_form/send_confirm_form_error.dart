import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:web_dex/bloc/withdraw_form/withdraw_form_bloc.dart';

class SendConfirmFormError extends StatelessWidget {
  const SendConfirmFormError({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<WithdrawFormBloc, WithdrawFormState>(
      builder: (BuildContext context, WithdrawFormState state) {
        final sendError = state.transactionError;

        return Container(
          padding: const EdgeInsets.fromLTRB(0, 10, 0, 10),
          width: double.infinity,
          child: Text(
            sendError?.message ?? 'Unknown error',
            textAlign: TextAlign.left,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        );
      },
    );
  }
}
