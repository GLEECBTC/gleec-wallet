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
import 'package:web_dex/views/swap/common/swap_copy.dart';
import 'package:web_dex/views/swap/common/swap_format.dart';
import 'package:web_dex/views/swap/common/swap_links.dart';
import 'package:web_dex/views/swap/common/swap_palette.dart';
import 'package:web_dex/views/swap/common/swap_widgets.dart';
import 'package:web_dex/views/swap/execution/swap_evidence_sheet.dart';
import 'package:web_dex/views/swap/execution/swap_time_context.dart';
import 'package:web_dex/views/swap/execution/swap_timeline_view.dart';
import 'package:web_dex/views/swap/motion/swap_motion.dart';
import 'package:web_dex/views/swap/swap_shell_controller.dart';

part 'swap_execution_moments.dart';
part 'swap_execution_sections.dart';

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
      create: (_) => SwapExecutionBloc(
        registry: services.registry,
        seed: services.registry.snapshotOf(id) ?? initial,
      )..add(SwapExecutionWatched(id, source: source, initial: initial)),
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
  late final AppLifecycleListener _lifecycle;
  int _resumes = 0;

  /// The snapshot the screen last showed, to tell what is news.
  SwapExecutionSnapshot? _heard;

  @override
  void initState() {
    super.initState();
    _heard = context.read<SwapExecutionBloc>().state.snapshot;
    _services.viewing.add(widget.id);
    _lifecycle = AppLifecycleListener(
      onResume: () {
        if (mounted) setState(() => _resumes++);
      },
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
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
        if (url != null) openSwapLink(context, url.toString());
      case SwapOutcomeAction.contactSupport:
        showSwapEvidenceSheet(context, snapshot: snapshot, services: _services);
    }
  }

  static Widget _hero(SwapHeroCopy hero, {SwapHeroMotion? motion}) =>
      SwapStatusHero(
        icon: hero.icon,
        tone: hero.tone,
        title: hero.title,
        body: hero.body,
        motion: motion,
      );

  /// How the hero moves into [hero]: a success settles with a little
  /// overshoot, a refund's icon unwinds, a delay's hourglass turns over, and
  /// an error arrives without any bounce.
  static SwapHeroMotion _heroMotion(
    SwapExecutionState state,
    SwapExecutionSnapshot snapshot,
    SwapHeroCopy hero, {
    required bool delayed,
  }) {
    final (curve, from, turns, duration) = switch (snapshot.outcome?.kind) {
      null when delayed => (SwapMotion.enter, 0.9, 0.5, SwapMotion.settle),
      null => (SwapMotion.enter, 0.8, 0.0, SwapMotion.pop),
      SwapOutcomeKind.completed => (
        SwapMotion.success,
        0.6,
        0.0,
        SwapMotion.settle,
      ),
      SwapOutcomeKind.refunded => (SwapMotion.enter, 0.8, 1.0, SwapMotion.ring),
      _ when hero.tone == SwapTone.danger => (
        SwapMotion.error,
        0.9,
        0.0,
        SwapMotion.pop,
      ),
      _ => (SwapMotion.warning, 0.7, 0.0, SwapMotion.settle),
    };
    return SwapHeroMotion(
      animate: state.live,
      iconFrom: from,
      iconTurns: turns,
      iconCurve: curve,
      iconDuration: duration,
      ring: snapshot.outcome?.kind == SwapOutcomeKind.completed
          ? snapshot.id
          : null,
    );
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
    return BlocConsumer<SwapExecutionBloc, SwapExecutionState>(
      listenWhen: (previous, next) => previous.snapshot != next.snapshot,
      listener: _onNews,
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
              : state.unanswered
              ? _hero(SwapHeroCopy.delayed())
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

        return SwapScreen(
          onEscape: _leave,
          child: SingleChildScrollView(
            child: SwapColumn(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [heading, body],
              ),
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
    final terminal = snapshot.isTerminal;
    // Until the engine answers, this is Activity's possibly stale snapshot.
    final unanswered = state.unanswered && !terminal;
    final hero = unanswered ? SwapHeroCopy.delayed() : copy.hero;
    final delayed = unanswered || (!terminal && snapshot.delayedSince != null);

    final children = <Widget>[
      if (!_inFlow) ...[
        Text(
          copy.pairLine,
          style: SwapText.strong(context),
          textAlign: TextAlign.center,
        ),
      ],
      _hero(hero, motion: _heroMotion(state, snapshot, hero, delayed: delayed)),
      SwapTimeContext(snapshot: snapshot, delayed: delayed),
      if (copy.priceMoveComparison case final String comparison)
        SwapReveal(
          onMount: state.live,
          animate: state.live,
          delay: _sectionDelay,
          child: SwapCallout(
            tone: SwapTone.warning,
            icon: Icons.compare_arrows_rounded,
            message: comparison,
          ),
        ),
      SwapTimelineView(
        steps: SwapTimeline.of(
          snapshot,
          networks,
          explorer: _services.explorerTxUrl,
        ),
        animate: state.live,
        tracking:
            !terminal &&
            !state.unanswered &&
            snapshot.delayedSince == null &&
            snapshot.stage != SwapProgressStage.actionRequired,
        event: snapshot,
        resumes: _resumes,
      ),
    ];

    children
      ..add(
        SwapSmoothSize(
          animate: state.live,
          child: Column(
            key: ValueKey(terminal),
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: terminal
                ? _recovery(context, snapshot, copy, live: state.live)
                : _running(context, state, snapshot),
          ),
        ),
      )
      ..add(_evidence(context, snapshot, live: state.live));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }
}
