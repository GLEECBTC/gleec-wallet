import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:web_dex/app_config/app_config.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/shared/swap/swap_execution_snapshot.dart';
import 'package:web_dex/shared/swap/swap_services.dart';
import 'package:web_dex/shared/utils/utils.dart';
import 'package:web_dex/views/swap/common/swap_copy.dart';
import 'package:web_dex/views/swap/common/swap_format.dart';
import 'package:web_dex/views/swap/common/swap_palette.dart';
import 'package:web_dex/views/swap/common/swap_sheet.dart';
import 'package:web_dex/views/swap/common/swap_widgets.dart';

/// Opens the evidence for [snapshot]: identifiers, transactions and links,
/// with a hand-off to support.
Future<void> showSwapEvidenceSheet(
  BuildContext context, {
  required SwapExecutionSnapshot snapshot,
  required SwapServices services,
}) {
  return showSwapSheet<void>(
    context: context,
    label: LocaleKeys.swapEvidenceTitle.tr(),
    builder: (_) => SwapEvidenceSheet(snapshot: snapshot, services: services),
  );
}

/// Copies the support payload for [snapshot] and opens the support contact.
Future<void> contactSwapSupport(
  BuildContext context, {
  required SwapExecutionSnapshot snapshot,
  required SwapServices services,
}) async {
  final payload = SwapExecutionCopy(
    snapshot,
    services.networks(),
  ).supportPayload();
  await copyToClipBoard(
    context,
    payload,
    LocaleKeys.swapEvidenceCopiedAll.tr(),
  );
  await launchURLString(discordSupportChannelUrl.toString());
}

/// Everything a swap left behind as proof.
class SwapEvidenceSheet extends StatelessWidget {
  const SwapEvidenceSheet({
    required this.snapshot,
    required this.services,
    super.key,
  });

  final SwapExecutionSnapshot snapshot;
  final SwapServices services;

  @override
  Widget build(BuildContext context) {
    final evidence = snapshot.evidence;
    final copy = SwapExecutionCopy(snapshot, services.networks());
    final hasTransactions =
        evidence.approvalTxHashes.isNotEmpty ||
        evidence.sourceTxHash != null ||
        evidence.destinationTxHash != null;

    return SwapSheetScaffold(
      title: LocaleKeys.swapEvidenceTitle.tr(),
      subtitle: LocaleKeys.swapEvidenceIntro.tr(),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Field(
            label: LocaleKeys.swapEvidenceExecutionId.tr(),
            child: SwapCopyLine(
              value: snapshot.id,
              label: LocaleKeys.swapEvidenceExecutionId.tr(),
            ),
          ),
          _Field(
            label: LocaleKeys.swapEvidenceRoute.tr(),
            child: Text(copy.pairLine, style: SwapText.strong(context)),
          ),
          if (snapshot.createdAt != null)
            _Field(
              label: LocaleKeys.swapEvidenceStarted.tr(),
              child: Text(
                SwapFormat.time(snapshot.createdAt!),
                style: SwapText.body(context),
              ),
            ),
          if (snapshot.updatedAt != null)
            _Field(
              label: LocaleKeys.swapEvidenceUpdated.tr(),
              child: Text(
                SwapFormat.time(snapshot.updatedAt!),
                style: SwapText.body(context),
              ),
            ),
          if (snapshot.fromAddress != null)
            _Field(
              label: LocaleKeys.swapEvidenceFrom.tr(),
              child: SwapCopyLine(
                value: snapshot.fromAddress!,
                label: LocaleKeys.swapEvidenceFrom.tr(),
              ),
            ),
          if (snapshot.toAddress != null)
            _Field(
              label: LocaleKeys.swapEvidenceTo.tr(),
              child: SwapCopyLine(
                value: snapshot.toAddress!,
                label: LocaleKeys.swapEvidenceTo.tr(),
              ),
            ),
          if (!hasTransactions)
            _Field(
              label: LocaleKeys.swapEvidenceSource.tr(),
              child: Text(
                LocaleKeys.swapEvidenceNoTransactions.tr(),
                style: SwapText.body(context),
              ),
            ),
          for (final hash in evidence.approvalTxHashes)
            _TxField(
              label: LocaleKeys.swapEvidenceApprovals.tr(),
              hash: hash,
              explorer: services.explorerTxUrl(snapshot.from, hash),
            ),
          if (evidence.sourceTxHash != null)
            _TxField(
              label: LocaleKeys.swapEvidenceSource.tr(),
              hash: evidence.sourceTxHash!,
              explorer: services.explorerTxUrl(
                snapshot.from,
                evidence.sourceTxHash!,
              ),
            ),
          if (evidence.destinationTxHash != null)
            _TxField(
              label: LocaleKeys.swapEvidenceDestination.tr(),
              hash: evidence.destinationTxHash!,
              explorer: services.explorerTxUrl(
                snapshot.outcome?.receivedAsset ?? snapshot.to,
                evidence.destinationTxHash!,
              ),
            ),
          if (evidence.providerExplorerUrl != null)
            _Field(
              label: LocaleKeys.swapEvidenceRouteStatus.tr(),
              child: Align(
                alignment: Alignment.centerLeft,
                child: SwapLinkButton(
                  label: LocaleKeys.swapEvidenceRouteLink.tr(),
                  icon: Icons.open_in_new_rounded,
                  onPressed: () =>
                      launchURLString(evidence.providerExplorerUrl!),
                ),
              ),
            ),
          if (evidence.providerRequestId != null)
            _Field(
              label: LocaleKeys.swapEvidenceSupportRef.tr(),
              child: SwapCopyLine(
                value: evidence.providerRequestId!,
                label: LocaleKeys.swapEvidenceSupportRef.tr(),
              ),
            ),
          if (evidence.gasSpent.isNotEmpty)
            _Field(
              label: LocaleKeys.swapEvidenceGasSpent.tr(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final gas in evidence.gasSpent)
                    Text(
                      SwapFormat.tokens(
                        gas.amount,
                        gas.asset == null
                            ? gas.ticker
                            : SwapFormat.ticker(gas.asset!),
                        rounding: SwapRounding.up,
                      ),
                      style: SwapText.body(context),
                    ),
                ],
              ),
            ),
        ],
      ),
      footer: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          SwapButton(
            label: LocaleKeys.swapEvidenceCopyAll.tr(),
            variant: SwapButtonVariant.secondary,
            icon: Icons.content_copy_rounded,
            onPressed: () => copyToClipBoard(
              context,
              copy.supportPayload(),
              LocaleKeys.swapEvidenceCopiedAll.tr(),
            ),
          ),
          const SizedBox(height: 10),
          SwapButton(
            label: LocaleKeys.swapActionContactSupport.tr(),
            icon: Icons.support_agent_rounded,
            onPressed: () => contactSwapSupport(
              context,
              snapshot: snapshot,
              services: services,
            ),
          ),
        ],
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final palette = SwapPalette.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: palette.border)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label.toUpperCase(), style: SwapText.eyebrow(context)),
            const SizedBox(height: 4),
            child,
          ],
        ),
      ),
    );
  }
}

class _TxField extends StatelessWidget {
  const _TxField({required this.label, required this.hash, this.explorer});

  final String label;
  final String hash;
  final Uri? explorer;

  @override
  Widget build(BuildContext context) {
    final explorer = this.explorer;
    return _Field(
      label: label,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SwapCopyLine(value: hash, label: label),
          if (explorer != null)
            SwapLinkButton(
              label: LocaleKeys.viewOnExplorer.tr(),
              icon: Icons.open_in_new_rounded,
              onPressed: () => launchURLString(explorer.toString()),
            ),
        ],
      ),
    );
  }
}
