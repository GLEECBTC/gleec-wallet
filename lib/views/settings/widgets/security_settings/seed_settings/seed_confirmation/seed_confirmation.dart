import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:web_dex/bloc/auth_bloc/auth_bloc.dart';
import 'package:web_dex/bloc/security_settings/security_settings_bloc.dart';
import 'package:web_dex/bloc/security_settings/security_settings_event.dart';
import 'package:web_dex/common/screen.dart';
import 'package:web_dex/bloc/analytics/analytics_bloc.dart';
import 'package:web_dex/analytics/events/security_events.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/model/text_error.dart';
import 'package:web_dex/model/wallet.dart';
import 'package:web_dex/views/settings/widgets/security_settings/seed_settings/seed_back_button.dart';
import 'package:web_dex/views/settings/widgets/security_settings/seed_settings/seed_word_button.dart';
import 'package:komodo_ui_kit/komodo_ui_kit.dart';
import 'package:web_dex/shared/screenshot/screenshot_sensitivity.dart';

class SeedConfirmation extends StatefulWidget {
  const SeedConfirmation({required this.seedPhrase});
  final String seedPhrase;

  @override
  State<SeedConfirmation> createState() => _SeedConfirmationState();
}

class _SeedConfirmationState extends State<SeedConfirmation> {
  List<_SeedWord> _selectedWords = [];
  late List<_SeedWord> _jumbledWords;
  late List<_SeedWord> _originalWords;
  TextError? _confirmationError;

  @override
  void initState() {
    _originalWords = widget.seedPhrase
        .split(' ')
        .map((w) => _SeedWord(word: w))
        .toList();
    _jumbledWords = List.from(_originalWords)..shuffle();
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    final scrollController = ScrollController();
    return ScreenshotSensitive(
      child: DexScrollbar(
        isMobile: isMobile,
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
                        stageSkipped: 'seed_confirm',
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
                      const ShowSeedEvent(),
                    );
                  }),
                ),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 680),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(right: 10),
                      child: _Title(),
                    ),
                    const SizedBox(height: 16),
                    Padding(
                      padding: const EdgeInsets.only(right: 10),
                      child: _SelectedWordsField(
                        selectedWords: _selectedWords,
                        confirmationError: _confirmationError,
                      ),
                    ),
                    const SizedBox(height: 16),
                    _JumbledSeedWords(
                      words: _jumbledWords,
                      selectedWords: _selectedWords,
                      onWordPressed: _onWordPressed,
                    ),
                    const SizedBox(height: 24),
                    Padding(
                      padding: const EdgeInsets.only(right: 10),
                      child: _ControlButtons(
                        onConfirmPressed: _isReadyForCheck
                            ? () => _onConfirmPressed()
                            : null,
                        onClearPressed: _clear,
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _onWordPressed(_SeedWord word) {
    if (_selectedWords.contains(word)) {
      _selectedWords.remove(word);
    } else {
      _selectedWords.add(word);
    }
    setState(() {
      _selectedWords = _selectedWords;
      _confirmationError = null;
    });
  }

  void _onConfirmPressed() {
    final String result = _selectedWords.map((w) => w.word).join(' ').trim();

    if (result == widget.seedPhrase) {
      final settingsBloc = context.read<SecuritySettingsBloc>();
      // Read before dispatching: `SeedConfirmedEvent` advances the step, and
      // the anchor must be sampled against the state that is still in the flow.
      final backupSeconds = settingsBloc.state.backupElapsed?.inSeconds ?? 0;
      settingsBloc.add(const SeedConfirmedEvent());
      context.read<AuthBloc>().add(AuthSeedBackupConfirmed());
      final walletType =
          context.read<AuthBloc>().state.currentUser?.wallet.config.type.name ??
          '';
      context.read<AnalyticsBloc>().add(
        AnalyticsBackupCompletedEvent(
          backupTime: backupSeconds,
          method: 'manual',
          hdType: walletType,
        ),
      );
      return;
    }
    setState(() {
      _confirmationError = TextError(
        error: LocaleKeys.seedConfirmIncorrectText.tr(),
      );
    });
  }

  void _clear() {
    setState(() {
      _confirmationError = null;
      _selectedWords.clear();
    });
  }

  bool get _isReadyForCheck => _selectedWords.length == _originalWords.length;
}

class _Title extends StatelessWidget {
  const _Title();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          LocaleKeys.seedConfirmTitle.tr(),
          style: Theme.of(context).textTheme.titleLarge?.copyWith(fontSize: 16),
        ),
        const SizedBox(height: 6),
        Text(
          LocaleKeys.seedConfirmDescription.tr(),
          style: Theme.of(context).textTheme.bodyLarge,
        ),
      ],
    );
  }
}

class _ResultWord extends StatelessWidget {
  const _ResultWord(this.word);

  final _SeedWord word;

  @override
  Widget build(BuildContext context) {
    return Text(
      '${word.word} ',
      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
    );
  }
}

class _JumbledSeedWords extends StatelessWidget {
  const _JumbledSeedWords({
    required this.onWordPressed,
    required this.words,
    required this.selectedWords,
  });
  final List<_SeedWord> words;
  final List<_SeedWord> selectedWords;
  final void Function(_SeedWord) onWordPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: Wrap(
        runAlignment: WrapAlignment.spaceBetween,
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.start,
        runSpacing: 11,
        children: words.map((w) {
          return FractionallySizedBox(
            widthFactor: isMobile ? 0.5 : 0.25,
            child: Padding(
              padding: const EdgeInsets.only(right: 10),
              child: SeedWordButton(
                text: w.word,
                onPressed: () => onWordPressed(w),
                isSelected: selectedWords.contains(w),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _SelectedWordsField extends StatelessWidget {
  const _SelectedWordsField({
    required this.selectedWords,
    required this.confirmationError,
  });
  final List<_SeedWord> selectedWords;
  final TextError? confirmationError;

  @override
  Widget build(BuildContext context) {
    final fillColor = Theme.of(context).inputDecorationTheme.fillColor;
    final TextError? error = confirmationError;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          decoration: BoxDecoration(
            border: error != null
                ? Border.all(color: Theme.of(context).colorScheme.error)
                : null,
            borderRadius: BorderRadius.circular(20),
            color: fillColor,
          ),
          constraints: const BoxConstraints(minHeight: 85),
          width: double.infinity,
          padding: const EdgeInsets.all(10),
          child: Wrap(
            runSpacing: 4,
            spacing: 8,
            children: _createResultWords(selectedWords),
          ),
        ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(top: 6.0),
            child: SelectableText(
              error.message,
              style: Theme.of(context).inputDecorationTheme.errorStyle,
            ),
          ),
      ],
    );
  }

  List<_ResultWord> _createResultWords(List<_SeedWord> resultWords) {
    final result = <_ResultWord>[];
    for (int i = 0; i < resultWords.length; i++) {
      result.add(_ResultWord(resultWords[i]));
    }
    return result;
  }
}

class _ControlButtons extends StatelessWidget {
  const _ControlButtons({
    required this.onClearPressed,
    required this.onConfirmPressed,
  });
  final VoidCallback onClearPressed;
  final VoidCallback? onConfirmPressed;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Expanded(
          child: UiBorderButton(
            key: const Key('seed-confirm-clear-button'),
            height: isMobile ? 52 : 40,
            onPressed: onClearPressed,
            text: LocaleKeys.clear.tr(),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: UiPrimaryButton(
            key: const Key('seed-confirm-check-button'),
            height: isMobile ? 52 : 40,
            onPressed: onConfirmPressed,
            text: LocaleKeys.confirm.tr(),
          ),
        ),
      ],
    );
  }
}

class _SeedWord {
  const _SeedWord({required this.word});
  final String word;
}
