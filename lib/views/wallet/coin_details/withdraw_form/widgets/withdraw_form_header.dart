import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/bloc/withdraw_form/withdraw_form_bloc.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/shared/widgets/segwit_icon.dart';
import 'package:web_dex/views/common/page_header/page_header.dart';

class WithdrawFormHeader extends StatelessWidget {
  const WithdrawFormHeader({
    required this.asset,
    this.onBackButtonPressed,
    super.key,
  });

  final Asset asset;
  final VoidCallback? onBackButtonPressed;

  bool get _isSegwit => asset.id.id.toLowerCase().contains('segwit');

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<WithdrawFormBloc, WithdrawFormState>(
      builder: (context, state) {
        return Semantics(
          container: true,
          header: true,
          liveRegion: true,
          label: state.step.title,
          child: PageHeader(
            title: state.step.title,
            widgetTitle: _isSegwit
                ? const Padding(
                    padding: EdgeInsets.only(left: 6.0),
                    child: SegwitIcon(height: 22),
                  )
                : null,
            backText: LocaleKeys.backToWallet.tr(),
            onBackButtonPressed: onBackButtonPressed,
          ),
        );
      },
    );
  }
}
