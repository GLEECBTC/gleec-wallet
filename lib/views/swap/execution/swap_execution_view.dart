import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:web_dex/bloc/swap_execution/swap_execution_bloc.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_bloc.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_event.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/router/state/routing_state.dart';
import 'package:web_dex/shared/swap/swap_execution_snapshot.dart';
import 'package:web_dex/shared/swap/swap_quote.dart';
import 'package:web_dex/shared/swap/swap_services.dart';
import 'package:web_dex/shared/utils/utils.dart';
import 'package:web_dex/views/swap/common/swap_copy.dart';
import 'package:web_dex/views/swap/common/swap_format.dart';
import 'package:web_dex/views/swap/common/swap_palette.dart';
import 'package:web_dex/views/swap/common/swap_widgets.dart';
import 'package:web_dex/views/swap/execution/swap_evidence_sheet.dart';
import 'package:web_dex/views/swap/execution/swap_timeline_view.dart';
import 'package:web_dex/views/swap/swap_shell_controller.dart';

/// Where a swap screen was opened from, which decides where leaving goes.
enum SwapExecutionContext {
  /// Straight after starting, on the Swap destination.
  flow,

  /// From a row in Activity.
  activity,
}

/// One swap, running or finished: its status, how it completes, and — once
/// it has stopped — what happened, where the funds are and what to do next.
class SwapExecutionView extends StatelessWidget {
  const SwapExecutionView({
    required this.id,
    required this.context,
    this.source,
    this.initial,
    super.key,
  });

  final String id;
  final SwapExecutionContext context;
  final SwapLiquiditySource? source;
  final SwapExecutionSnapshot? initial;

  @override
  Widget build(BuildContext context) {
    final services = context.read<SwapServices>();
    return BlocProvider(
      key: ValueKey(id),
      create: (_) =>
          SwapExecutionBloc(registry: services.registry)
            ..add(SwapExecutionWatched(id, source: source, initial: initial)),
      child: _ExecutionBody(id: id, executionContext: this.context),
    );
  }
}

class _ExecutionBody extends StatefulWidget {
  const _ExecutionBody({required this.id, required this.executionContext});

  final String id;
  final SwapExecutionContext executionContext;

  @override
  State<_ExecutionBody> createState() => _ExecutionBodyState();
}

class _ExecutionBodyState extends State<_ExecutionBody> {
  late final SwapServices _services = context.read<SwapServices>();

  @override
  void initState() {
    super.initState();
    _services.viewing.add(widget.id);
  }

  @override
  void dispose() {
    _services.viewing.remove(widget.id);
    super.dispose();
  }

  bool get _inFlow => widget.executionContext == SwapExecutionContext.flow;

  void _leave() {
    if (_inFlow) {
      context.read<UnifiedSwapBloc>().add(const UnifiedSwapProgressLeft());
    } else {
      SwapShellScope.of(context).closeDetail();
    }
  }

  void _viewInActivity(SwapExecutionSnapshot? snapshot) {
    final shell = SwapShellScope.of(context);
    context.read<UnifiedSwapBloc>().add(const UnifiedSwapProgressLeft());
    shell.showActivity(
      swap: snapshot == null
          ? null
          : (id: snapshot.id, source: snapshot.source),
    );
  }

  /// Goes back to the Swap form, after [event] sets it up.
  void _toForm(UnifiedSwapEvent event) {
    context.read<UnifiedSwapBloc>().add(event);
    SwapShellScope.of(context).show(SwapDestination.swap);
  }

  Future<void> _confirmCancel(SwapExecutionSnapshot snapshot) async {
    final approved = snapshot.evidence.approvalTxHashes.isNotEmpty;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final palette = SwapPalette.of(dialogContext);
        return AlertDialog(
          backgroundColor: palette.surfaceRaised,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
          ),
          title: Text(
            LocaleKeys.swapCancelDialogTitle.tr(),
            style: SwapText.heading(dialogContext),
          ),
          content: Text(
            approved
                ? LocaleKeys.swapCancelDialogBodyApproved.tr()
                : LocaleKeys.swapCancelDialogBody.tr(),
            style: SwapText.body(dialogContext),
          ),
          actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          actions: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SwapButton(
                  label: LocaleKeys.swapCancelSwap.tr(),
                  variant: SwapButtonVariant.danger,
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                ),
                const SizedBox(height: 10),
                SwapButton(
                  label: LocaleKeys.swapKeepSwapping.tr(),
                  variant: SwapButtonVariant.secondary,
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                ),
              ],
            ),
          ],
        );
      },
    );
    if (confirmed != true || !mounted) return;
    context.read<SwapExecutionBloc>().add(const SwapExecutionCancelRequested());
  }

  void _onAction(SwapOutcomeAction action, SwapExecutionSnapshot snapshot) {
    final outcome = snapshot.outcome;
    switch (action) {
      case SwapOutcomeAction.followUp:
        final received = outcome?.receivedAsset;
        if (received == null) return;
        _toForm(
          UnifiedSwapFollowUpRequested(
            pay: received,
            receive: snapshot.to,
            amount: outcome?.receivedAmount?.toString(),
          ),
        );
      case SwapOutcomeAction.keepToken || SwapOutcomeAction.startAnother:
        _toForm(const UnifiedSwapResetRequested());
      case SwapOutcomeAction.acceptFreshQuote:
        final fresh = outcome?.failure?.freshQuote;
        if (fresh == null) return;
        _toForm(UnifiedSwapFreshQuoteAccepted(fresh));
      case SwapOutcomeAction.tryAgain:
        final from = snapshot.from;
        if (from == null) {
          _toForm(const UnifiedSwapResetRequested());
          return;
        }
        _toForm(
          UnifiedSwapFollowUpRequested(
            pay: from,
            receive: snapshot.to,
            amount: snapshot.sellAmount?.toString(),
          ),
        );
      case SwapOutcomeAction.openAdvanced:
        routingState.dexState.setDetailsAction(snapshot.id);
        SwapShellScope.of(context).show(SwapDestination.advanced);
      case SwapOutcomeAction.viewOnExplorer:
        final hash = snapshot.evidence.sourceTxHash;
        final url = hash == null
            ? null
            : _services.explorerTxUrl(snapshot.from, hash);
        if (url != null) launchURLString(url.toString());
      case SwapOutcomeAction.contactSupport:
        showSwapEvidenceSheet(context, snapshot: snapshot, services: _services);
    }
  }

  static String _actionLabel(
    SwapOutcomeAction action,
    SwapExecutionCopy copy,
  ) => switch (action) {
    SwapOutcomeAction.followUp => LocaleKeys.swapActionFollowUp.tr(
      args: [copy.receivedTicker, copy.toTicker],
    ),
    SwapOutcomeAction.keepToken => LocaleKeys.swapActionKeepToken.tr(),
    SwapOutcomeAction.acceptFreshQuote =>
      LocaleKeys.swapActionReviewNewPrice.tr(),
    SwapOutcomeAction.tryAgain => LocaleKeys.tryAgain.tr(),
    SwapOutcomeAction.openAdvanced => LocaleKeys.swapActionOpenAdvanced.tr(),
    SwapOutcomeAction.viewOnExplorer => LocaleKeys.viewOnExplorer.tr(),
    SwapOutcomeAction.contactSupport =>
      LocaleKeys.swapActionContactSupport.tr(),
    SwapOutcomeAction.startAnother => LocaleKeys.swapActionStartAnother.tr(),
  };

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SwapExecutionBloc, SwapExecutionState>(
      builder: (context, state) {
        final snapshot = state.snapshot;
        final heading = SwapPageHeading(
          title: _inFlow
              ? LocaleKeys.swapProgressTitle.tr()
              : LocaleKeys.swapNavActivity.tr(),
          leading: SwapIconButton(
            icon: _inFlow ? Icons.close_rounded : Icons.arrow_back_rounded,
            label: _inFlow ? LocaleKeys.close.tr() : LocaleKeys.back.tr(),
            onPressed: _leave,
          ),
        );

        final Widget body;
        if (snapshot == null) {
          body = state.notFound
              ? SwapStatusHero(
                  icon: Icons.search_off_rounded,
                  tone: SwapTone.warning,
                  title: LocaleKeys.swapProgressUnknownTitle.tr(),
                  body: LocaleKeys.swapProgressUnknownBody.tr(),
                )
              : const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Column(
                    children: [
                      SwapSkeleton(height: 64, widthFactor: 0.2),
                      SizedBox(height: 16),
                      SwapSkeleton(widthFactor: 0.6),
                      SizedBox(height: 24),
                      SwapSkeleton(height: 70),
                      SizedBox(height: 8),
                      SwapSkeleton(height: 70),
                    ],
                  ),
                );
        } else {
          body = _content(context, state, snapshot);
        }

        return SingleChildScrollView(
          child: SwapColumn(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [heading, body],
            ),
          ),
        );
      },
    );
  }

  Widget _content(
    BuildContext context,
    SwapExecutionState state,
    SwapExecutionSnapshot snapshot,
  ) {
    final networks = _services.networks();
    final copy = SwapExecutionCopy(snapshot, networks);
    final hero = copy.hero;
    final terminal = snapshot.isTerminal;

    final children = <Widget>[
      if (!_inFlow) ...[
        Text(
          copy.pairLine,
          style: SwapText.strong(context),
          textAlign: TextAlign.center,
        ),
      ],
      SwapStatusHero(
        icon: hero.icon,
        tone: hero.tone,
        title: hero.title,
        body: hero.body,
      ),
      if (copy.priceMoveComparison case final String comparison)
        SwapCallout(
          tone: SwapTone.warning,
          icon: Icons.compare_arrows_rounded,
          message: comparison,
        ),
      SwapTimelineView(steps: SwapTimeline.of(snapshot, networks)),
    ];

    if (terminal) {
      children.addAll(_recovery(context, snapshot, copy));
    } else {
      children.addAll(_running(context, state, snapshot));
    }

    children.add(_evidence(context, snapshot));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }

  List<Widget> _running(
    BuildContext context,
    SwapExecutionState state,
    SwapExecutionSnapshot snapshot,
  ) {
    final routeUrl = snapshot.evidence.providerExplorerUrl;
    final cancelMessage = switch (state.cancelStatus) {
      SwapCancelStatus.refusedAlreadySent =>
        LocaleKeys.swapCancelRefusedSent.tr(),
      SwapCancelStatus.refusedNotSupported =>
        LocaleKeys.swapCancelRefusedAtomic.tr(),
      SwapCancelStatus.unconfirmed => LocaleKeys.swapCancelUnconfirmed.tr(),
      _ => null,
    };
    return [
      SwapCallout(
        tone: SwapTone.info,
        icon: Icons.schedule_rounded,
        message: LocaleKeys.swapProgressLeaveNote.tr(),
      ),
      if (cancelMessage != null) ...[
        const SizedBox(height: 12),
        SwapCallout(
          tone: SwapTone.warning,
          message: cancelMessage,
          liveRegion: true,
        ),
      ],
      const SizedBox(height: 16),
      if (snapshot.stage == SwapProgressStage.actionRequired &&
          routeUrl != null) ...[
        SwapButton(
          label: LocaleKeys.swapOpenRoutePage.tr(),
          icon: Icons.open_in_new_rounded,
          onPressed: () => launchURLString(routeUrl),
        ),
        const SizedBox(height: 10),
      ],
      if (snapshot.canCancel) ...[
        SwapButton(
          key: const Key('swap-cancel'),
          label: state.cancelStatus == SwapCancelStatus.cancelling
              ? LocaleKeys.swapCancelling.tr()
              : LocaleKeys.swapCancelSwap.tr(),
          variant: SwapButtonVariant.secondary,
          busy: state.cancelStatus == SwapCancelStatus.cancelling,
          onPressed: () => _confirmCancel(snapshot),
        ),
        const SizedBox(height: 10),
      ],
      if (_inFlow)
        SwapButton(
          label: LocaleKeys.swapViewInActivity.tr(),
          variant: SwapButtonVariant.secondary,
          onPressed: () => _viewInActivity(snapshot),
        ),
    ];
  }

  List<Widget> _recovery(
    BuildContext context,
    SwapExecutionSnapshot snapshot,
    SwapExecutionCopy copy,
  ) {
    final hero = copy.hero;
    final actions = copy.actions;
    final success = snapshot.isSuccess;
    return [
      if (!success) ...[
        SwapQuestion(
          eyebrow: LocaleKeys.swapQuestionWhat.tr(),
          title: hero.title,
          body: hero.body,
          divider: false,
        ),
        SwapQuestion(
          eyebrow: LocaleKeys.swapQuestionWhere.tr(),
          body: copy.fundsLocation,
        ),
        SwapQuestion(
          eyebrow: LocaleKeys.swapQuestionNext.tr(),
          body: LocaleKeys.swapQuestionNextBody.tr(),
        ),
      ],
      const SizedBox(height: 8),
      for (final (index, action) in actions.indexed) ...[
        SwapButton(
          label: _actionLabel(action, copy),
          variant: index == 0
              ? SwapButtonVariant.primary
              : SwapButtonVariant.secondary,
          onPressed: () => _onAction(action, snapshot),
        ),
        const SizedBox(height: 10),
      ],
      if (_inFlow)
        SwapButton(
          label: success
              ? LocaleKeys.done.tr()
              : LocaleKeys.swapViewInActivity.tr(),
          variant: SwapButtonVariant.secondary,
          onPressed: success ? _leave : () => _viewInActivity(snapshot),
        ),
    ];
  }

  Widget _evidence(BuildContext context, SwapExecutionSnapshot snapshot) {
    final palette = SwapPalette.of(context);
    final updated = snapshot.updatedAt ?? snapshot.finishedAt;
    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: palette.borderStrong),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (updated != null) ...[
            Text(
              LocaleKeys.swapEvidenceUpdated.tr(),
              style: SwapText.eyebrow(context),
            ),
            const SizedBox(height: 2),
            Text(SwapFormat.time(updated), style: SwapText.body(context)),
            const SizedBox(height: 8),
          ],
          Text(
            LocaleKeys.swapEvidenceExecutionId.tr(),
            style: SwapText.eyebrow(context),
          ),
          SwapCopyLine(
            value: snapshot.id,
            label: LocaleKeys.swapEvidenceExecutionId.tr(),
          ),
          SwapLinkButton(
            label: LocaleKeys.swapActionViewEvidence.tr(),
            icon: Icons.receipt_long_outlined,
            onPressed: () => showSwapEvidenceSheet(
              context,
              snapshot: snapshot,
              services: _services,
            ),
          ),
        ],
      ),
    );
  }
}
