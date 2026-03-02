import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:web_dex/bloc/version_info/version_info_bloc.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/shared/widgets/copied_text.dart';

class AppVersionNumber extends StatelessWidget {
  const AppVersionNumber({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 12),
      child: BlocBuilder<VersionInfoBloc, VersionInfoState>(
        builder: (context, state) {
          if (state is VersionInfoLoaded) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SelectableText(LocaleKeys.komodoWallet.tr(), style: _textStyle),
                if (state.appVersion != null)
                  _MetadataRow(
                    label: LocaleKeys.version.tr(),
                    value: state.appVersion!,
                  ),
                if (state.buildDate != null)
                  _MetadataRow(
                    label: LocaleKeys.buildDate.tr(),
                    value: state.buildDate!,
                  ),
                if (state.commitHash != null)
                  _MetadataRow(
                    label: LocaleKeys.commit.tr(),
                    value: state.commitHash!,
                  ),
                if (state.apiCommitHash != null)
                  _MetadataRow(
                    label: LocaleKeys.api.tr(),
                    value: state.apiCommitHash!,
                  ),
                const SizedBox(height: 4),
                CoinsCommitInfo(state: state),
              ],
            );
          } else if (state is VersionInfoLoading) {
            return const Center(child: CircularProgressIndicator());
          } else if (state is VersionInfoError) {
            return Text('Error: ${state.message}');
          }
          return const SizedBox.shrink();
        },
      ),
    );
  }
}

class CoinsCommitInfo extends StatelessWidget {
  const CoinsCommitInfo({super.key, required this.state});

  final VersionInfoLoaded state;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(LocaleKeys.coinAssets.tr(), style: _textStyle),
        if (state.currentCoinsCommit != null)
          _MetadataRow(
            label: LocaleKeys.bundled.tr(),
            value: state.currentCoinsCommit!,
          ),
        if (state.latestCoinsCommit != null)
          _MetadataRow(
            label: LocaleKeys.updated.tr(),
            value: state.latestCoinsCommit!,
          ),
      ],
    );
  }
}

const _textStyle = TextStyle(fontSize: 13, fontWeight: FontWeight.w500);

class _MetadataRow extends StatelessWidget {
  const _MetadataRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 8,
        runSpacing: 4,
        children: [
          Text('$label:', style: _textStyle),
          CopiedTextV2(
            copiedValue: value,
            isTruncated: true,
            backgroundColor: Theme.of(
              context,
            ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
            textColor: Theme.of(context).textTheme.bodyMedium?.color,
          ),
        ],
      ),
    );
  }
}
