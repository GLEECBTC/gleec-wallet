import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:komodo_ui_kit/komodo_ui_kit.dart';
import 'package:web_dex/bloc/security_settings/security_settings_bloc.dart';
import 'package:web_dex/bloc/security_settings/security_settings_event.dart';
import 'package:web_dex/common/app_assets.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';

class SeedConfirmSuccess extends StatelessWidget {
  const SeedConfirmSuccess();

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 415),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 25),
            const ExcludeSemantics(
              child: DexSvgImage(path: Assets.seedSuccess),
            ),
            const SizedBox(height: 20),
            Semantics(header: true, child: const _Title()),
            const SizedBox(height: 9),
            const _Body(),
            const SizedBox(height: 20),
            const _Button(),
          ],
        ),
      ),
    ),
  );
}

class _Title extends StatelessWidget {
  const _Title();

  @override
  Widget build(BuildContext context) {
    return Text(
      LocaleKeys.seedPhraseSuccessTitle.tr(),
      textAlign: TextAlign.center,
      style: Theme.of(context).textTheme.titleLarge?.copyWith(fontSize: 16),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body();

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 415),
      child: Row(
        children: [
          Expanded(
            child: Text(
              LocaleKeys.seedPhraseSuccessBody.tr(),
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          ),
        ],
      ),
    );
  }
}

class _Button extends StatelessWidget {
  const _Button();

  @override
  Widget build(BuildContext context) {
    final bloc = context.read<SecuritySettingsBloc>();
    const event = ResetEvent();
    gotoSecurityMain() => bloc.add(event);

    return UiPrimaryButton(
      key: const Key('seed-confirm-got-it'),
      width: 198,
      height: 52,
      expandForText: true,
      onPressed: gotoSecurityMain,
      text: LocaleKeys.seedPhraseGotIt.tr(),
    );
  }
}
