import 'package:app_theme/app_theme.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:komodo_ui_kit/komodo_ui_kit.dart';
import 'package:web_dex/bloc/security_settings/security_settings_bloc.dart';
import 'package:web_dex/bloc/security_settings/security_settings_event.dart';
import 'package:web_dex/bloc/security_settings/security_settings_state.dart';
import 'package:web_dex/common/screen.dart';
import 'package:web_dex/bloc/analytics/analytics_bloc.dart';
import 'package:web_dex/analytics/events/security_events.dart';
import 'package:web_dex/bloc/auth_bloc/auth_bloc.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/model/coin.dart';
import 'package:web_dex/model/wallet.dart';
import 'package:web_dex/shared/utils/formatters.dart';
import 'package:web_dex/shared/utils/utils.dart';
import 'package:web_dex/shared/widgets/coin_item/coin_item.dart';
import 'package:web_dex/shared/widgets/dry_intrinsic.dart';
import 'package:web_dex/views/settings/widgets/security_settings/seed_settings/seed_back_button.dart';
import 'package:web_dex/views/wallet/coin_details/receive/qr_code_address.dart';
import 'package:web_dex/shared/screenshot/screenshot_sensitivity.dart';

class SeedShow extends StatelessWidget {
  const SeedShow({required this.seedPhrase, required this.privKeys});
  final String seedPhrase;
  final Map<Coin, String> privKeys;

  @override
  Widget build(BuildContext context) {
    final scrollController = ScrollController();
    return ScreenshotSensitive(
      child: DexScrollbar(
        scrollController: scrollController,
        child: SingleChildScrollView(
          controller: scrollController,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              if (!isMobile)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16.0),
                  child: SeedBackButton(() {
                    context.read<AnalyticsBloc>().add(
                      AnalyticsBackupSkippedEvent(
                        stageSkipped: 'seed_show',
                        hdType:
                            context
                                .read<AuthBloc>()
                                .state
                                .currentUser
                                ?.wallet
                                .config
                                .type
                                .name ??
                            '',
                      ),
                    );
                    context.read<SecuritySettingsBloc>().add(
                      const ResetEvent(),
                    );
                  }),
                ),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 680),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _TitleRow(),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: Wrap(
                        alignment: WrapAlignment.spaceBetween,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 12,
                        runSpacing: 8,
                        children: [
                          _ShowingSwitcher(),
                          _CopySeedButton(seed: seedPhrase),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Flexible(child: _SeedPlace(seedPhrase: seedPhrase)),
                    const SizedBox(height: 20),
                    _SeedPhraseConfirmButton(seedPhrase: seedPhrase),
                    const SizedBox(height: 40),
                    _PrivateKeysList(privKeys: privKeys),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PrivateKeysList extends StatelessWidget {
  const _PrivateKeysList({
    required this.privKeys,
    // ignore: unused_element_parameter
    super.key,
  });

  final Map<Coin, String> privKeys;

  @override
  Widget build(BuildContext context) {
    if (privKeys.isEmpty) {
      return Container();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          LocaleKeys.privateKeys.tr(),
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        ListView.builder(
          primary: false,
          shrinkWrap: true,
          itemCount: privKeys.length,
          itemBuilder: (context, index) {
            final coin = privKeys.keys.elementAt(index);
            final key = privKeys[coin]!;

            return Card(
              color: Theme.of(context).colorScheme.onSurface,
              margin: const EdgeInsets.symmetric(horizontal: 0, vertical: 4),
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    CoinItem(coin: coin),
                    const Spacer(),
                    Text(
                      truncateMiddleSymbols(key, 5, 5),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    IconButton(
                      iconSize: 20,
                      icon: const Icon(Icons.copy),
                      onPressed: () {
                        copyToClipBoard(context, key);
                      },
                    ),
                    IconButton(
                      iconSize: 20,
                      icon: const Icon(Icons.qr_code),
                      onPressed: () {
                        _showQrDialog(context, coin, key);
                      },
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  void _showQrDialog(BuildContext context, Coin coin, String key) {
    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: SizedBox(
            width: 300,
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CoinItem(coin: coin),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () {
                          Navigator.of(context).pop();
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  QRCodeAddress(currentAddress: key),
                  const SizedBox(height: 16),
                  SelectableText(
                    key,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _TitleRow extends StatelessWidget {
  const _TitleRow();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          LocaleKeys.seedPhraseShowingTitle.tr(),
          style: Theme.of(context).textTheme.titleLarge?.copyWith(fontSize: 16),
        ),
        const SizedBox(height: 6),
        Text(
          LocaleKeys.seedPhraseMakeSureBody.tr(),
          style: Theme.of(context).textTheme.bodyLarge,
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: theme.custom.warningColor.withValues(alpha: 0.1),
            border: Border.all(color: theme.custom.warningColor),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(Icons.warning, color: theme.custom.warningColor),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  LocaleKeys.copyWarning.tr(),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: theme.custom.warningColor,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _CopySeedButton extends StatelessWidget {
  const _CopySeedButton({required this.seed});
  final String seed;

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: () {
          copyToClipBoard(context, seed);
          context.read<SecuritySettingsBloc>().add(const ShowSeedCopiedEvent());
        },
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 5, 10, 5),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.copy,
                size: 16,
                color: theme.currentGlobal.textTheme.bodySmall?.color,
              ),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  LocaleKeys.seedPhraseShowingCopySeed.tr(),
                  style: theme.currentGlobal.textTheme.bodySmall,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ShowingSwitcher extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final bloc = context.read<SecuritySettingsBloc>();

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        UiSwitcher(
          value: bloc.state.showSeedWords,
          onChanged: (isChecked) => bloc.add(ShowSeedWordsEvent(isChecked)),
          width: 38,
          height: 21,
        ),
        const SizedBox(width: 6),
        Flexible(
          child: SelectableText(
            LocaleKeys.seedPhraseShowingShowPhrase.tr(),
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w500,
              fontSize: 12,
            ),
          ),
        ),
      ],
    );
  }
}

class _SeedPlace extends StatelessWidget {
  const _SeedPlace({required this.seedPhrase});
  final String seedPhrase;

  @override
  Widget build(BuildContext context) {
    final isCustom = !context
        .read<KomodoDefiSdk>()
        .mnemonicValidator
        .validateBip39(seedPhrase);
    if (isCustom) return _SeedField(seedPhrase: seedPhrase);
    return _WordsList(seedPhrase: seedPhrase);
  }
}

class _SeedField extends StatelessWidget {
  const _SeedField({required this.seedPhrase});
  final String seedPhrase;

  @override
  Widget build(BuildContext context) {
    final width = screenWidth - 80.0;

    return BlocSelector<SecuritySettingsBloc, SecuritySettingsState, bool>(
      selector: (state) => state.showSeedWords,
      builder: (context, showSeedWords) {
        return ConstrainedBox(
          constraints: BoxConstraints(maxWidth: isMobile ? width : 380),
          child: TextField(
            controller: TextEditingController()
              ..text = showSeedWords ? seedPhrase : _obscured(seedPhrase),
            maxLines: 12,
            minLines: 5,
            readOnly: true,
          ),
        );
      },
    );
  }

  String _obscured(String source, {String obscuringCharacter = '•'}) {
    if (source.isEmpty) return '';
    if (obscuringCharacter.length > 1) {
      obscuringCharacter = obscuringCharacter.substring(0, 1);
    } else if (obscuringCharacter.isEmpty) {
      obscuringCharacter = '•';
    }
    final length = source.length;
    String result = '';
    for (int i = 0; i < length; i++) {
      result += source.codeUnitAt(i) == 32 ? ' ' : obscuringCharacter;
    }
    return result;
  }
}

class _WordsList extends StatelessWidget {
  const _WordsList({required this.seedPhrase});
  final String seedPhrase;

  @override
  Widget build(BuildContext context) {
    final double runSpacing = isMobile ? 15 : 20;

    final bloc = context.read<SecuritySettingsBloc>();
    final showSeedWords = bloc.state.showSeedWords;

    final seedList = seedPhrase.split(' ');

    return SizedBox(
      width: double.infinity,
      child: Wrap(
        runSpacing: runSpacing,
        alignment: WrapAlignment.spaceBetween,
        children: seedList
            .asMap()
            .map<int, Widget>(
              (index, w) => _buildSeedWord(index, w, showSeedWords),
            )
            .values
            .toList(),
      ),
    );
  }

  MapEntry<int, Widget> _buildSeedWord(int i, String word, bool showSeedWords) {
    return MapEntry(
      i,
      _SelectableSeedWord(
        initialValue: word,
        isSeedShown: showSeedWords,
        index: i,
      ),
    );
  }
}

class _SelectableSeedWord extends StatelessWidget {
  const _SelectableSeedWord({
    // ignore: unused_element_parameter
    super.key,
    required this.isSeedShown,
    required this.initialValue,
    required this.index,
  });

  final bool isSeedShown;
  final String initialValue;
  final int index;

  @override
  Widget build(BuildContext context) {
    final numStyle = TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w500,
      color: Theme.of(
        context,
      ).textTheme.bodyMedium?.color?.withValues(alpha: 0.4),
    );
    final text = isSeedShown ? initialValue : '••••••';

    return Focus(
      descendantsAreFocusable: true,
      skipTraversal: true,
      child: FractionallySizedBox(
        widthFactor: isMobile ? 0.5 : 0.25,
        child: Row(
          mainAxisSize: MainAxisSize.max,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(width: 21, child: Text('${index + 1}.', style: numStyle)),
            Expanded(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 31),
                child: DryIntrinsicWidth(
                  child: UiTextFormField(
                    initialValue: text,
                    obscureText: !isSeedShown,
                    readOnly: true,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
          ],
        ),
      ),
    );
  }
}

class _SeedPhraseConfirmButton extends StatelessWidget {
  const _SeedPhraseConfirmButton({required this.seedPhrase});
  final String seedPhrase;

  @override
  Widget build(BuildContext context) {
    final bloc = context.read<SecuritySettingsBloc>();

    // Gated on word count, not on BIP39 validity. The confirmation quiz just
    // splits on whitespace and compares the reassembled string, so it works on
    // any multi-word phrase. Requiring BIP39 left custom-seed users with no
    // route to mark their seed backed up at all except downloading the wallet
    // file - which also meant the receive-time backup gate could never be
    // satisfied for them. Only a single-token passphrase degenerates into
    // "select the one word", so that case still falls back to the file route.
    final wordCount = seedPhrase.trim().split(RegExp(r'\s+')).length;
    if (wordCount < 2) return const SizedBox.shrink();

    void onPressed() => bloc.add(const SeedConfirmEvent());
    final text = LocaleKeys.seedPhraseShowingSavedPhraseButton.tr();

    final contentWidth = screenWidth - 80;
    final width = isMobile ? contentWidth : 207.0;
    final height = isMobile ? 52.0 : 40.0;

    return BlocSelector<SecuritySettingsBloc, SecuritySettingsState, bool>(
      selector: (state) => state.isSeedSaved,
      builder: (context, isSaved) {
        return UiPrimaryButton(
          width: width,
          height: height,
          text: text,
          onPressed: isSaved ? onPressed : null,
        );
      },
    );
  }
}
