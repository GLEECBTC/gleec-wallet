import 'package:app_theme/app_theme.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:web_dex/bloc/withdraw_form/withdraw_form_bloc.dart';
import 'package:web_dex/common/app_assets.dart';
import 'package:web_dex/common/screen.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/model/text_error.dart';
import 'package:komodo_ui_kit/komodo_ui_kit.dart';
import 'package:web_dex/shared/utils/utils.dart';
import 'package:web_dex/views/wallet/coin_details/constants.dart';

class FailedPage extends StatelessWidget {
  const FailedPage({super.key});

  @override
  Widget build(BuildContext context) {
    final maxWidth = isMobile ? double.infinity : withdrawWidth;

    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: const Column(
        children: [
          DexSvgImage(path: Assets.assetsDenied),
          SizedBox(height: 20),
          _SendErrorText(),
          SizedBox(height: 20),
          _SendErrorHeader(),
          SizedBox(height: 15),
          _SendErrorBody(),
          SizedBox(height: 20),
          _CloseButton(),
        ],
      ),
    );
  }
}

class _SendErrorText extends StatelessWidget {
  const _SendErrorText();

  @override
  Widget build(BuildContext context) {
    return Text(
      LocaleKeys.errorTryAgainSupportHint.tr(),
      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
        fontSize: 14,
        color: Theme.of(context).colorScheme.error,
      ),
      textAlign: TextAlign.center,
    );
  }
}

class _SendErrorHeader extends StatelessWidget {
  const _SendErrorHeader();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.start,
      mainAxisSize: MainAxisSize.max,
      children: [
        Text(
          LocaleKeys.errorDescription.tr(),
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ],
    );
  }
}

class _SendErrorBody extends StatelessWidget {
  const _SendErrorBody();

  @override
  Widget build(BuildContext context) {
    return BlocSelector<WithdrawFormBloc, WithdrawFormState, TextError?>(
      // TODO: Confirm this is the correct error
      selector: (state) => state.transactionError,
      builder: (BuildContext context, error) {
        final iconColor = Theme.of(
          context,
        ).textTheme.bodyMedium?.color?.withValues(alpha: .7);

        return Material(
          color: theme.custom.buttonColorDefault,
          borderRadius: BorderRadius.circular(18),
          child: InkWell(
            onTap: error == null
                ? null
                : () => copyToClipBoard(context, error.error),
            borderRadius: BorderRadius.circular(18),
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 70, maxWidth: 300),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(child: _MultilineText(error?.error ?? '')),
                    const SizedBox(width: 16),
                    Icon(Icons.copy_rounded, color: iconColor, size: 22),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _MultilineText extends StatelessWidget {
  const _MultilineText(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      overflow: TextOverflow.ellipsis,
      textAlign: TextAlign.left,
      style: Theme.of(context).textTheme.bodyMedium,
      softWrap: true,
      maxLines: 3,
    );
  }
}

class _CloseButton extends StatelessWidget {
  const _CloseButton();

  @override
  Widget build(BuildContext context) {
    final height = isMobile ? 52.0 : 40.0;
    return UiPrimaryButton(
      height: height,
      onPressed: () =>
          context.read<WithdrawFormBloc>().add(const WithdrawFormReset()),
      text: LocaleKeys.close.tr(),
    );
  }
}

// class _PageContent extends StatelessWidget {
//   const _PageContent();
//
//   @override
//   Widget build(BuildContext context) {
//     if (isMobile) return const _MobileContent();
//     return const _DesktopContent();
//   }
// }
//
// class _DesktopContent extends StatelessWidget {
//   const _DesktopContent();
//
//   @override
//   Widget build(BuildContext context) {
//     return Column(
//       children: [
//         const SizedBox(height: 20),
//         assets.denied,
//         const SizedBox(height: 19),
//         const _Content(),
//       ],
//     );
//   }
// }
//
// class _MobileContent extends StatelessWidget {
//   const _MobileContent();
//
//   @override
//   Widget build(BuildContext context) {
//     return Column(
//       children: [
//         const SizedBox(height: 22),
//         assets.denied,
//         const SizedBox(height: 19),
//         const _Content(),
//       ],
//     );
//   }
// }
