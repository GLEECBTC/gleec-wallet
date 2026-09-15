import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:web_dex/bloc/security_settings/private_key_export_bloc.dart';
import 'package:web_dex/bloc/security_settings/private_key_export_event.dart';
import 'package:web_dex/bloc/security_settings/private_key_export_state.dart';
import 'package:web_dex/common/screen.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/shared/screenshot/screenshot_sensitivity.dart';
import 'package:web_dex/shared/widgets/notice_banner.dart';
import 'package:web_dex/views/settings/widgets/security_settings/private_key_settings/private_key_actions_widget.dart';
import 'package:web_dex/views/settings/widgets/security_settings/private_key_settings/private_key_export_asset_section.dart';
import 'package:web_dex/views/settings/widgets/security_settings/private_key_settings/widgets/private_key_export_empty_state.dart';
import 'package:web_dex/views/settings/widgets/security_settings/private_key_settings/widgets/private_key_export_header.dart';
import 'package:web_dex/views/settings/widgets/security_settings/private_key_settings/widgets/private_key_export_loading_view.dart';
import 'package:web_dex/views/settings/widgets/security_settings/private_key_settings/widgets/private_key_reveal_gate.dart';
import 'package:web_dex/views/settings/widgets/security_settings/seed_settings/seed_back_button.dart';

/// Private key export.
///
/// The notices are ranked rather than stacked: one critical banner for the
/// standing security rule, one informational banner for what the export does
/// and does not cover, and the clipboard caution moved inside the reveal gate
/// where it is actually actionable. Four identically-weighted full-width
/// blocks meant none of them read as more important than the others.
class PrivateKeyShow extends StatelessWidget {
  const PrivateKeyShow({super.key});

  @override
  Widget build(BuildContext context) => ScreenshotSensitive(
    child: BlocBuilder<PrivateKeyExportBloc, PrivateKeyExportState>(
      builder: (context, state) => switch (state.phase) {
        PrivateKeyExportPhase.starting ||
        PrivateKeyExportPhase.exporting => const PrivateKeyExportLoadingView(),
        PrivateKeyExportPhase.ready => _ReadyView(state: state),
        _ => const SizedBox.shrink(),
      },
    ),
  );
}

class _ReadyView extends StatelessWidget {
  const _ReadyView({required this.state});

  final PrivateKeyExportState state;

  @override
  Widget build(BuildContext context) {
    final bloc = context.read<PrivateKeyExportBloc>();
    final outcomes = state.displayedOutcomes;
    final unavailable = outcomes.where((o) => o.keys.isEmpty).length;

    return Align(
      alignment: Alignment.topLeft,
      // Settings gives this pane the full desktop width, which turned the
      // notices into ~1300px single-column paragraphs. Matches the measure
      // the sibling seed screen already uses.
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!isMobile)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: SeedBackButton(
                  () => bloc.add(const PrivateKeyExportCancelled()),
                ),
              ),
            PrivateKeyExportHeader(
              assetCount: outcomes.length,
              keyCount: outcomes.fold(0, (sum, o) => sum + o.keys.length),
              unavailableCount: unavailable,
            ),
            const SizedBox(height: 16),
            NoticeBanner(
              key: const Key('private-key-export-notice-security'),
              variant: NoticeBannerVariant.critical,
              icon: Icons.gpp_maybe_outlined,
              title: LocaleKeys.privateKeyExportCriticalTitle.tr(),
              child: Text(LocaleKeys.privateKeySecurityWarning.tr()),
            ),
            const SizedBox(height: 12),
            NoticeBanner(
              key: const Key('private-key-export-notice-coverage'),
              variant: NoticeBannerVariant.info,
              icon: Icons.fact_check_outlined,
              title: LocaleKeys.privateKeyExportCoverageDetailsTitle.tr(),
              child: Text(LocaleKeys.privateKeyExportCoverageNotice.tr()),
            ),
            const SizedBox(height: 16),
            const PrivateKeyRevealGate(),
            if (state.hasBlockedAssets)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  children: [
                    Checkbox(
                      value: state.includeBlockedAssets,
                      onChanged: state.isDelivering
                          ? null
                          : (value) => bloc.add(
                              PrivateKeyExportBlockedAssetsChanged(
                                value ?? false,
                              ),
                            ),
                    ),
                    Expanded(child: Text(LocaleKeys.includeBlockedAssets.tr())),
                  ],
                ),
              ),
            const SizedBox(height: 16),
            const PrivateKeyActionsWidget(),
            const SizedBox(height: 16),
            if (outcomes.isEmpty)
              PrivateKeyExportEmptyState(
                hiddenByFilter:
                    state.hasBlockedAssets && !state.includeBlockedAssets,
              )
            else
              for (final outcome in outcomes)
                PrivateKeyExportAssetSection(
                  key: ValueKey((state.operationId, outcome.assetId)),
                  outcome: outcome,
                  showKeys: state.showKeys,
                  canDeliver: state.canDeliver,
                ),
          ],
        ),
      ),
    );
  }
}
