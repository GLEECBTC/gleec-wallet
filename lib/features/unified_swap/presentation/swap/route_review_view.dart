import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:web_dex/features/unified_swap/domain/route_activity_models.dart';
import 'package:web_dex/features/unified_swap/domain/route_execution_models.dart';
import 'package:web_dex/features/unified_swap/domain/unified_swap_capability_policy.dart';
import 'package:web_dex/features/unified_swap/presentation/swap/swap_widgets.dart';
import 'package:web_dex/features/unified_swap/presentation/unified_swap_design.dart';

class RouteReviewView extends StatefulWidget {
  const RouteReviewView({
    required this.review,
    required this.desktopIntentEditor,
    required this.onBack,
    required this.onAccept,
    required this.acceptInFlight,
    required this.executionEnabled,
    required this.clipboardWriter,
    required this.announcement,
    this.failureMessage,
    this.termsUpdated = false,
    this.previousReview,
    this.desktopIntentSurfaceOpen = false,
    this.now,
    super.key,
  });

  final RouteExecutionReview review;
  final Widget desktopIntentEditor;
  final VoidCallback? onBack;
  final VoidCallback onAccept;
  final bool acceptInFlight;
  final bool executionEnabled;
  final SwapClipboardWriter clipboardWriter;
  final SwapAnnouncement announcement;
  final String? failureMessage;
  final bool termsUpdated;
  final RouteExecutionReview? previousReview;
  final bool desktopIntentSurfaceOpen;
  final DateTime Function()? now;

  @override
  State<RouteReviewView> createState() => _RouteReviewViewState();
}

class _RouteReviewViewState extends State<RouteReviewView> {
  Timer? _expiryTimer;

  RouteExecutionReview get review => widget.review;
  Widget get desktopIntentEditor => widget.desktopIntentEditor;
  VoidCallback? get onBack => widget.onBack;
  VoidCallback get onAccept => widget.onAccept;
  bool get acceptInFlight => widget.acceptInFlight;
  bool get executionEnabled => widget.executionEnabled;
  SwapClipboardWriter get clipboardWriter => widget.clipboardWriter;
  SwapAnnouncement get announcement => widget.announcement;
  String? get failureMessage => widget.failureMessage;
  bool get termsUpdated => widget.termsUpdated;
  RouteExecutionReview? get previousReview => widget.previousReview;
  bool get desktopIntentSurfaceOpen => widget.desktopIntentSurfaceOpen;
  DateTime Function()? get now => widget.now;

  @override
  void initState() {
    super.initState();
    _scheduleExpiry();
  }

  @override
  void didUpdateWidget(RouteReviewView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.review.reviewId != widget.review.reviewId ||
        oldWidget.review.expiresAt != widget.review.expiresAt ||
        oldWidget.now != widget.now) {
      _scheduleExpiry();
    }
  }

  void _scheduleExpiry() {
    _expiryTimer?.cancel();
    final current = now?.call() ?? DateTime.now().toUtc();
    final remaining = review.expiresAt.difference(current.toUtc());
    if (remaining <= Duration.zero) return;
    _expiryTimer = Timer(remaining + const Duration(milliseconds: 1), () {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _expiryTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final current = now?.call() ?? DateTime.now().toUtc();
    final expired = review.isExpiredAt(current);
    final safeReview = _isSafeReview(review);
    final executable = safeReview && !expired && executionEnabled;
    final colors = UnifiedSwapDesign.colors(context);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !acceptInFlight) onBack?.call();
      },
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape): () =>
              onBack?.call(),
        },
        child: ColoredBox(
          color: colors.canvas,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final desktop =
                  constraints.maxWidth >= UnifiedSwapDesign.desktopBreakpoint;
              final panel = _ReviewPanel(
                key: const Key('unified-swap-review'),
                desktop: desktop,
                review: review,
                expired: expired,
                safeReview: safeReview,
                executable: executable,
                acceptInFlight: acceptInFlight,
                executionEnabled: executionEnabled,
                failureMessage: failureMessage,
                termsUpdated: termsUpdated,
                previousReview: previousReview,
                onBack: onBack,
                onAccept: onAccept,
                clipboardWriter: clipboardWriter,
                announcement: announcement,
              );
              if (!desktop) return panel;
              return Padding(
                padding: UnifiedSwapDesign.pagePadding(context),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: UnifiedSwapDesign.detailWidth,
                    ),
                    child: LayoutBuilder(
                      builder: (context, detailConstraints) {
                        final panelWidth = (detailConstraints.maxWidth * .42)
                            .clamp(380.0, 520.0);
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(child: desktopIntentEditor),
                            if (!desktopIntentSurfaceOpen) ...[
                              const SizedBox(width: 24),
                              SizedBox(width: panelWidth, child: panel),
                            ],
                          ],
                        );
                      },
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _ReviewPanel extends StatelessWidget {
  const _ReviewPanel({
    required this.desktop,
    required this.review,
    required this.expired,
    required this.safeReview,
    required this.executable,
    required this.acceptInFlight,
    required this.executionEnabled,
    required this.failureMessage,
    required this.termsUpdated,
    required this.previousReview,
    required this.onBack,
    required this.onAccept,
    required this.clipboardWriter,
    required this.announcement,
    super.key,
  });

  final bool desktop;
  final RouteExecutionReview review;
  final bool expired;
  final bool safeReview;
  final bool executable;
  final bool acceptInFlight;
  final bool executionEnabled;
  final String? failureMessage;
  final bool termsUpdated;
  final RouteExecutionReview? previousReview;
  final VoidCallback? onBack;
  final VoidCallback onAccept;
  final SwapClipboardWriter clipboardWriter;
  final SwapAnnouncement announcement;

  @override
  Widget build(BuildContext context) {
    final colors = UnifiedSwapDesign.colors(context);
    final content = ListView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: desktop
          ? const EdgeInsets.all(18)
          : UnifiedSwapDesign.pagePadding(context),
      children: [..._reviewContent(context)],
    );
    return Container(
      decoration: desktop
          ? BoxDecoration(
              color: colors.surfaceRaised,
              border: Border.all(color: colors.border),
              borderRadius: BorderRadius.circular(22),
              boxShadow: UnifiedSwapDesign.geometry(
                context,
              ).surfaceShadow(colors),
            )
          : null,
      clipBehavior: desktop ? Clip.antiAlias : Clip.none,
      child: Column(
        children: [
          Expanded(child: content),
          _ReviewFooter(
            review: review,
            executable: executable,
            acceptInFlight: acceptInFlight,
            onAccept: onAccept,
            desktop: desktop,
          ),
        ],
      ),
    );
  }

  List<Widget> _reviewContent(BuildContext context) => [
    _ReviewHeading(onBack: onBack),
    const SizedBox(height: 12),
    UnifiedSwapBadge(
      label: unifiedSwapText(context, 'review.readyBadge', 'Ready to review'),
      tone: UnifiedSwapNoticeTone.brand,
    ),
    if (acceptInFlight) ...[
      const SizedBox(height: 12),
      UnifiedSwapNotice(
        key: const Key('swap-review-revalidating'),
        title: unifiedSwapText(
          context,
          'review.revalidatingTitle',
          'Checking latest terms',
        ),
        message: unifiedSwapText(
          context,
          'review.revalidatingBody',
          'The wallet is verifying balances, costs, route structure, and '
              'permissions before anything starts.',
        ),
        tone: UnifiedSwapNoticeTone.info,
        icon: Icons.sync_rounded,
        liveRegion: true,
      ),
    ],
    if (termsUpdated) ...[
      const SizedBox(height: 12),
      _ReviewNotice(
        key: const Key('swap-review-terms-updated'),
        title: unifiedSwapText(
          context,
          'review.refresh.materialTitle',
          'Route terms updated',
        ),
        message: unifiedSwapText(
          context,
          'review.refresh.materialBody',
          'Costs or protected amounts changed. Review these exact new terms '
              'and confirm again before anything starts.',
        ),
        error: false,
      ),
      if (previousReview case final previous?) ...[
        const SizedBox(height: 12),
        _MaterialChangeComparison(previous: previous, current: review),
      ],
    ],
    if (expired) ...[
      const SizedBox(height: 12),
      _ReviewNotice(
        key: const Key('swap-review-expired'),
        title: unifiedSwapText(
          context,
          'review.expiredTitle',
          'Review expired',
        ),
        message: unifiedSwapText(
          context,
          'review.expiredBody',
          'Return to the quote and obtain fresh route terms.',
        ),
        error: true,
      ),
    ] else if (!safeReview) ...[
      const SizedBox(height: 12),
      _ReviewNotice(
        key: const Key('swap-review-inert'),
        title: unifiedSwapText(
          context,
          'review.inertTitle',
          'This Review is not executable',
        ),
        message: unifiedSwapText(
          context,
          'review.inertBody',
          'The wallet received an unknown route, warning, asset, or network '
              'variant. No funds can move.',
        ),
        error: true,
      ),
    ] else if (!executionEnabled) ...[
      const SizedBox(height: 12),
      _ReviewNotice(
        key: const Key('swap-init-disabled'),
        title: unifiedSwapText(
          context,
          'review.executionDisabledTitle',
          'Execution is disabled',
        ),
        message: unifiedSwapText(
          context,
          'review.executionDisabledBody',
          'You can inspect these terms, but new route execution is currently '
              'unavailable.',
        ),
        error: false,
      ),
    ],
    if (failureMessage case final failure?) ...[
      const SizedBox(height: 12),
      _ReviewNotice(
        key: const Key('swap-review-execution-failure'),
        title: unifiedSwapText(
          context,
          'review.executionFailedTitle',
          'Execution did not start',
        ),
        message: failure,
        error: true,
      ),
    ],
    if (review.warnings.isNotEmpty) ...[
      const SizedBox(height: 12),
      _WarningsReview(warnings: review.warnings),
    ],
    const SizedBox(height: 12),
    _ReviewSummary(review: review),
    const SizedBox(height: 12),
    UnifiedSwapNotice(
      title: unifiedSwapText(
        context,
        'review.minimumTitle',
        'You’ll receive at least',
      ),
      message: swapAmount(review.minimumReceive, review.destination),
      tone: UnifiedSwapNoticeTone.success,
      icon: Icons.shield_outlined,
    ),
    const SizedBox(height: 12),
    _DecisionFacts(review: review),
    const SizedBox(height: 12),
    UnifiedSwapDisclosure(
      title: unifiedSwapText(
        context,
        'review.costsProtection',
        'Costs & protection',
      ),
      child: _CostReview(review: review),
    ),
    const SizedBox(height: 8),
    UnifiedSwapDisclosure(
      title: unifiedSwapText(
        context,
        'review.routeIdentities',
        'Route & identities',
      ),
      child: Column(
        children: [
          _AddressReview(
            review: review,
            clipboardWriter: clipboardWriter,
            announcement: announcement,
          ),
          const SizedBox(height: 12),
          _RouteSteps(steps: review.steps),
        ],
      ),
    ),
    const SizedBox(height: 12),
    _PermissionSummary(review: review),
    const SizedBox(height: 16),
  ];
}

class _ReviewHeading extends StatefulWidget {
  const _ReviewHeading({required this.onBack});

  final VoidCallback? onBack;

  @override
  State<_ReviewHeading> createState() => _ReviewHeadingState();
}

class _ReviewHeadingState extends State<_ReviewHeading> {
  late final FocusNode _focusNode;
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode(debugLabel: 'Unified Swap Review heading')
      ..addListener(_handleFocusChanged);
  }

  void _handleFocusChanged() {
    if (mounted && _focused != _focusNode.hasFocus) {
      setState(() => _focused = _focusNode.hasFocus);
    }
  }

  @override
  void dispose() {
    _focusNode
      ..removeListener(_handleFocusChanged)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      child: Semantics(
        container: true,
        header: true,
        focusable: true,
        focused: _focused,
        child: UnifiedSwapPageTitle(
          title: unifiedSwapText(context, 'review.title', 'Review swap'),
          subtitle: unifiedSwapText(
            context,
            'review.subtitle',
            'Confirm the exact outcome, protection, costs, and permission '
                'before funds move.',
          ),
          leading: IconButton(
            key: const Key('swap-review-back'),
            onPressed: widget.onBack,
            tooltip: unifiedSwapText(context, 'common.goBack', 'Go back'),
            icon: const Icon(Icons.arrow_back_rounded),
          ),
        ),
      ),
    );
  }
}

class _ReviewFooter extends StatelessWidget {
  const _ReviewFooter({
    required this.review,
    required this.executable,
    required this.acceptInFlight,
    required this.onAccept,
    required this.desktop,
  });

  final RouteExecutionReview review;
  final bool executable;
  final bool acceptInFlight;
  final VoidCallback onAccept;
  final bool desktop;

  @override
  Widget build(BuildContext context) {
    final colors = UnifiedSwapDesign.colors(context);
    final footer = SafeArea(
      top: false,
      child: Padding(
        padding: desktop
            ? const EdgeInsets.fromLTRB(0, 8, 0, 4)
            : const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              liveRegion: acceptInFlight,
              child: FilledButton.icon(
                key: const Key('swap-review-confirm'),
                style: UnifiedSwapDesign.primaryButtonStyle(context),
                onPressed: executable && !acceptInFlight ? onAccept : null,
                icon: acceptInFlight
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.lock_open_rounded),
                label: Text(_label(context)),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              unifiedSwapText(
                context,
                'review.leavingNotice',
                'Leaving this screen never cancels work after it starts.',
              ),
              textAlign: TextAlign.center,
              style: UnifiedSwapDesign.typography(context).bodySmall,
            ),
          ],
        ),
      ),
    );
    if (desktop) return footer;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.canvas,
        border: Border(top: BorderSide(color: colors.border)),
        boxShadow: [
          BoxShadow(
            color: colors.shadow,
            blurRadius: 26,
            offset: const Offset(0, -14),
          ),
        ],
      ),
      child: footer,
    );
  }

  String _label(BuildContext context) {
    if (acceptInFlight) {
      return unifiedSwapText(
        context,
        'review.checkingLatest',
        'Checking latest terms',
      );
    }
    if (review.approvals.any((approval) => approval.resetRequired)) {
      return unifiedSwapText(
        context,
        'review.continueWithReset',
        'Continue with reset',
      );
    }
    if (review.approvals.length == 1) {
      final approval = review.approvals.single;
      return unifiedSwapText(
        context,
        'review.approveExactlyAndStart',
        'Approve exactly {amount} & start',
        namedArgs: {'amount': swapAmount(approval.exactAmount, approval.token)},
      );
    }
    if (review.approvals.length > 1) {
      return unifiedSwapText(
        context,
        'review.approveExactAmountsAndStart',
        'Approve exact amounts & start',
      );
    }
    return unifiedSwapText(context, 'review.startSwap', 'Start swap');
  }
}

class _ReviewSummary extends StatelessWidget {
  const _ReviewSummary({required this.review});

  final RouteExecutionReview review;

  @override
  Widget build(BuildContext context) {
    return SwapSectionCard(
      title: unifiedSwapText(
        context,
        'review.transferSummary',
        'Transfer summary',
      ),
      icon: Icons.swap_vert_rounded,
      child: Column(
        children: [
          _TransferLeg(
            label: unifiedSwapText(context, 'entry.youPay', 'You pay'),
            amount: swapAmount(review.sourceAmount, review.source),
            asset: review.source,
            address: review.resolvedSourceAddress,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Icon(
              Icons.arrow_downward_rounded,
              size: 20,
              color: UnifiedSwapDesign.colors(context).textTertiary,
            ),
          ),
          _TransferLeg(
            label: unifiedSwapText(context, 'entry.youReceive', 'You receive'),
            amount: swapAmount(review.expectedReceive, review.destination),
            asset: review.destination,
            address: review.recipient,
          ),
        ],
      ),
    );
  }
}

class _TransferLeg extends StatelessWidget {
  const _TransferLeg({
    required this.label,
    required this.amount,
    required this.asset,
    required this.address,
  });

  final String label;
  final String amount;
  final UnifiedSwapAssetIdentity asset;
  final String address;

  @override
  Widget build(BuildContext context) {
    final network = unifiedSwapNetworkLabel(context, asset);
    final shortAddress = unifiedSwapShortIdentity(address);
    return Semantics(
      label: unifiedSwapText(
        context,
        'review.termSemantics',
        '{label}: {value}. {details}',
        namedArgs: {
          'label': label,
          'value': amount,
          'details': '$network · $shortAddress',
        },
      ),
      child: ExcludeSemantics(
        child: Row(
          children: [
            UnifiedSwapAssetAvatar(asset: asset, size: 40),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: Theme.of(context).textTheme.labelLarge),
                  const SizedBox(height: 2),
                  Text(amount, style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 2),
                  Text(
                    '$network · $shortAddress',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DecisionFacts extends StatelessWidget {
  const _DecisionFacts({required this.review});

  final RouteExecutionReview review;

  @override
  Widget build(BuildContext context) {
    final totalCost = _summarizeAmounts(context, [
      for (final fee in review.fees) _AmountPart(fee.asset, fee.amount),
    ]);
    final maximumNetworkCost = _summarizeAmounts(context, [
      for (final cap in review.networkFeeCaps)
        _AmountPart(cap.asset, cap.maximumAmount),
    ]);
    return UnifiedSwapSurface(
      semanticLabel: unifiedSwapText(
        context,
        'review.keyFacts',
        'Key swap facts',
      ),
      padding: const EdgeInsets.all(14),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final facts = [
            _DecisionFact(
              label: unifiedSwapText(context, 'quote.totalCost', 'Total cost'),
              value: totalCost,
            ),
            _DecisionFact(
              label: unifiedSwapText(
                context,
                'review.estimatedTime',
                'Estimated completion',
              ),
              value: review.estimatedDurationKnown
                  ? swapDuration(context, review.estimatedDuration)
                  : unifiedSwapText(
                      context,
                      'common.unavailable',
                      'Unavailable',
                    ),
            ),
            _DecisionFact(
              label: unifiedSwapText(
                context,
                'review.maximumNetworkCost',
                'Maximum network cost',
              ),
              value: maximumNetworkCost,
            ),
          ];
          final stack =
              constraints.maxWidth < 300 ||
              MediaQuery.textScalerOf(context).scale(1) >= 1.5;
          if (stack) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var index = 0; index < facts.length; index++) ...[
                  facts[index],
                  if (index != facts.length - 1) const Divider(height: 20),
                ],
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var index = 0; index < facts.length; index++) ...[
                Expanded(child: facts[index]),
                if (index != facts.length - 1) const SizedBox(width: 10),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _MaterialChangeComparison extends StatelessWidget {
  const _MaterialChangeComparison({
    required this.previous,
    required this.current,
  });

  final RouteExecutionReview previous;
  final RouteExecutionReview current;

  @override
  Widget build(BuildContext context) {
    final oldTotalCost = _summarizeAmounts(context, [
      for (final fee in previous.fees) _AmountPart(fee.asset, fee.amount),
    ]);
    final newTotalCost = _summarizeAmounts(context, [
      for (final fee in current.fees) _AmountPart(fee.asset, fee.amount),
    ]);
    final oldNetworkMaximum = _summarizeAmounts(context, [
      for (final cap in previous.networkFeeCaps)
        _AmountPart(cap.asset, cap.maximumAmount),
    ]);
    final newNetworkMaximum = _summarizeAmounts(context, [
      for (final cap in current.networkFeeCaps)
        _AmountPart(cap.asset, cap.maximumAmount),
    ]);
    final oldPermission = _permissionComparisonSummary(context, previous);
    final newPermission = _permissionComparisonSummary(context, current);
    return SwapSectionCard(
      title: unifiedSwapText(
        context,
        'review.refresh.comparisonTitle',
        'Previous and updated terms',
      ),
      icon: Icons.compare_arrows_rounded,
      child: Column(
        children: [
          _ChangedFact(
            label: unifiedSwapText(
              context,
              'review.refresh.expectedReceive',
              'Expected receive',
            ),
            previous: swapAmount(
              previous.expectedReceive,
              previous.destination,
            ),
            current: swapAmount(current.expectedReceive, current.destination),
          ),
          const Divider(height: 20),
          _ChangedFact(
            label: unifiedSwapText(
              context,
              'review.refresh.minimumReceive',
              'Protected minimum',
            ),
            previous: swapAmount(previous.minimumReceive, previous.destination),
            current: swapAmount(current.minimumReceive, current.destination),
          ),
          const Divider(height: 20),
          _ChangedFact(
            label: unifiedSwapText(
              context,
              'review.refresh.totalCost',
              'Total cost',
            ),
            previous: oldTotalCost,
            current: newTotalCost,
          ),
          const Divider(height: 20),
          _ChangedFact(
            label: unifiedSwapText(
              context,
              'review.refresh.maximumNetworkCost',
              'Maximum network cost',
            ),
            previous: oldNetworkMaximum,
            current: newNetworkMaximum,
          ),
          const Divider(height: 20),
          _ChangedFact(
            label: unifiedSwapText(
              context,
              'review.refresh.tokenPermission',
              'Token permission',
            ),
            previous: oldPermission,
            current: newPermission,
          ),
        ],
      ),
    );
  }
}

class _ChangedFact extends StatelessWidget {
  const _ChangedFact({
    required this.label,
    required this.previous,
    required this.current,
  });

  final String label;
  final String previous;
  final String current;

  @override
  Widget build(BuildContext context) {
    final changed = previous != current;
    return Semantics(
      label: '$label: $previous, $current',
      child: ExcludeSemantics(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: Text(label)),
            const SizedBox(width: 12),
            Flexible(
              child: Text(
                changed ? '$previous → $current' : current,
                textAlign: TextAlign.end,
                style: changed
                    ? const TextStyle(fontWeight: FontWeight.w700)
                    : UnifiedSwapDesign.typography(context).bodySmall,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DecisionFact extends StatelessWidget {
  const _DecisionFact({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$label: $value',
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: Theme.of(context).textTheme.labelSmall),
            const SizedBox(height: 4),
            Text(
              value,
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
            ),
          ],
        ),
      ),
    );
  }
}

class _AddressReview extends StatelessWidget {
  const _AddressReview({
    required this.review,
    required this.clipboardWriter,
    required this.announcement,
  });

  final RouteExecutionReview review;
  final SwapClipboardWriter clipboardWriter;
  final SwapAnnouncement announcement;

  @override
  Widget build(BuildContext context) {
    return SwapSectionCard(
      title: unifiedSwapText(context, 'review.addresses', 'Addresses'),
      icon: Icons.account_balance_wallet_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            unifiedSwapText(
              context,
              'review.sourceIdentity',
              'Source · {asset}',
              namedArgs: {'asset': swapAssetLabel(context, review.source)},
            ),
            style: Theme.of(context).textTheme.labelLarge,
          ),
          SwapCopyableValue(
            label: unifiedSwapText(context, 'entry.from', 'From'),
            value: review.resolvedSourceAddress,
            valueKey: 'swap-review-source-address',
            clipboardWriter: clipboardWriter,
            announcement: announcement,
          ),
          const SizedBox(height: 12),
          Text(
            unifiedSwapText(
              context,
              'review.recipientIdentity',
              'Recipient · {asset}',
              namedArgs: {'asset': swapAssetLabel(context, review.destination)},
            ),
            style: Theme.of(context).textTheme.labelLarge,
          ),
          SwapCopyableValue(
            label: unifiedSwapText(context, 'entry.to', 'To'),
            value: review.recipient,
            valueKey: 'swap-review-recipient',
            clipboardWriter: clipboardWriter,
            announcement: announcement,
          ),
        ],
      ),
    );
  }
}

class _CostReview extends StatelessWidget {
  const _CostReview({required this.review});

  final RouteExecutionReview review;

  @override
  Widget build(BuildContext context) {
    return SwapSectionCard(
      title: unifiedSwapText(
        context,
        'review.feesAndMaximums',
        'Fees and maximum network costs',
      ),
      icon: Icons.payments_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (review.fees.isEmpty)
            Text(
              unifiedSwapText(
                context,
                'review.noFeeComponents',
                'No separate fee components were returned.',
              ),
            )
          else
            for (final fee in review.fees)
              _LineItem(
                label:
                    '${swapFeeKind(context, fee.kind)}'
                    '${fee.included ? ' · ${unifiedSwapText(context, 'fees.included', 'included')}' : ''}',
                value: swapAmount(fee.amount, fee.asset),
                unknown: fee.kind == RouteFeeKind.unknown,
              ),
          if (review.nonNetworkFeeLimits.isNotEmpty) ...[
            const Divider(height: 24),
            Text(
              unifiedSwapText(
                context,
                'review.maximumNonNetworkFees',
                'Maximum non-network fees',
              ),
              style: Theme.of(context).textTheme.labelLarge,
            ),
            for (final limit in review.nonNetworkFeeLimits)
              _LineItem(
                label:
                    '${limit.stageId == null ? '' : '${_reviewStepLabel(context, review, limit.stageId!)} · '}'
                    '${swapFeeKind(context, limit.kind)}',
                value: swapAmount(limit.maximumAmount, limit.asset),
                unknown: limit.kind == RouteFeeKind.unknown,
              ),
          ],
          if (review.networkFeeCaps.isNotEmpty) ...[
            const Divider(height: 24),
            Text(
              unifiedSwapText(
                context,
                'review.maximumNetworkByStep',
                'Maximum network cost by route step',
              ),
              style: Theme.of(context).textTheme.labelLarge,
            ),
            for (final cap in review.networkFeeCaps)
              _LineItem(
                label: _reviewStepLabel(context, review, cap.stageId),
                value: swapAmount(cap.maximumAmount, cap.asset),
                unknown: false,
              ),
          ],
        ],
      ),
    );
  }
}

class _LineItem extends StatelessWidget {
  const _LineItem({
    required this.label,
    required this.value,
    required this.unknown,
  });

  final String label;
  final String value;
  final bool unknown;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: Text(label)),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: TextStyle(
                color: unknown ? Theme.of(context).colorScheme.error : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _reviewStepLabel(
  BuildContext context,
  RouteExecutionReview review,
  String stageId,
) {
  final index = review.steps.indexWhere((step) => step.stageId == stageId);
  if (index < 0) {
    return unifiedSwapText(context, 'review.routeStep', 'Route step');
  }
  return unifiedSwapText(
    context,
    'common.stepNumber',
    'Step {number}',
    namedArgs: {'number': '${index + 1}'},
  );
}

class _RouteSteps extends StatelessWidget {
  const _RouteSteps({required this.steps});

  final List<RouteReviewStep> steps;

  @override
  Widget build(BuildContext context) {
    return SwapSectionCard(
      title: unifiedSwapText(context, 'review.routeSteps', 'Route steps'),
      icon: Icons.route_outlined,
      child: Column(
        children: [
          for (var index = 0; index < steps.length; index++) ...[
            _RouteStep(step: steps[index]),
            if (index != steps.length - 1) const Divider(height: 24),
          ],
        ],
      ),
    );
  }
}

class _RouteStep extends StatelessWidget {
  const _RouteStep({required this.step});

  final RouteReviewStep step;

  @override
  Widget build(BuildContext context) {
    final kind = switch (step.kind) {
      RouteReviewStepKind.atomic => unifiedSwapText(
        context,
        'review.stepKind.exchange',
        'Exchange',
      ),
      RouteReviewStepKind.external => unifiedSwapText(
        context,
        'review.stepKind.transfer',
        'Swap transfer',
      ),
      RouteReviewStepKind.unknown => unifiedSwapText(
        context,
        'review.stepKind.unknown',
        'Unknown route step',
      ),
    };
    return Semantics(
      container: true,
      label: unifiedSwapText(
        context,
        'review.stepSemantics',
        'Step {number}: {kind}. {source} to {destination}.',
        namedArgs: {
          'number': '${step.sequence + 1}',
          'kind': kind,
          'source': swapAssetLabel(context, step.source),
          'destination': swapAssetLabel(context, step.destination),
        },
      ),
      child: ExcludeSemantics(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(radius: 16, child: Text('${step.sequence + 1}')),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(kind, style: Theme.of(context).textTheme.titleSmall),
                  Text('${swapAssetLabel(context, step.source)} →'),
                  Text(swapAssetLabel(context, step.destination)),
                  Text(
                    unifiedSwapText(
                      context,
                      'review.stepAmounts',
                      'Send {send}; minimum {minimum}',
                      namedArgs: {
                        'send': swapAmount(step.sourceAmount, step.source),
                        'minimum': swapAmount(
                          step.minimumReceive,
                          step.destination,
                        ),
                      },
                    ),
                  ),
                  if (!step.isExecutable)
                    Text(
                      unifiedSwapText(
                        context,
                        'review.stepNotExecutable',
                        'This step type is not executable.',
                      ),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PermissionSummary extends StatelessWidget {
  const _PermissionSummary({required this.review});

  final RouteExecutionReview review;

  @override
  Widget build(BuildContext context) {
    final approvals = review.approvals;
    if (approvals.isEmpty) {
      if (review.sufficientAllowances.isNotEmpty) {
        return _sufficientAllowanceNotice(context, review);
      }
      return UnifiedSwapNotice(
        title: unifiedSwapText(
          context,
          'review.noApprovalTitle',
          'No token approval needed',
        ),
        message: unifiedSwapText(
          context,
          'review.noApprovalBody',
          'You’ll only sign the swap request when you start.',
        ),
        tone: UnifiedSwapNoticeTone.info,
        icon: Icons.verified_user_outlined,
      );
    }
    final exactAmounts = _summarizeAmounts(context, [
      for (final approval in approvals)
        _AmountPart(approval.token, approval.exactAmount),
    ]);
    final resetRequired = approvals.any((approval) => approval.resetRequired);
    final exactNotice = UnifiedSwapNotice(
      title: resetRequired
          ? unifiedSwapText(
              context,
              'review.resetThenApprovalTitle',
              'Reset, then exact approval',
            )
          : unifiedSwapText(
              context,
              'review.exactApprovalOnlyTitle',
              'Exact approval only',
            ),
      message: resetRequired
          ? unifiedSwapText(
              context,
              'review.resetThenApprovalBody',
              'Reset the current permission, then approve {amount} for this '
                  'swap only — never unlimited.',
              namedArgs: {'amount': exactAmounts},
            )
          : unifiedSwapText(
              context,
              'review.exactApprovalOnlyBody',
              'Approve {amount} for this swap only — never unlimited.',
              namedArgs: {'amount': exactAmounts},
            ),
      tone: UnifiedSwapNoticeTone.info,
      icon: Icons.verified_user_outlined,
    );
    if (review.sufficientAllowances.isEmpty) return exactNotice;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        exactNotice,
        const SizedBox(height: 8),
        _sufficientAllowanceNotice(context, review),
      ],
    );
  }
}

Widget _sufficientAllowanceNotice(
  BuildContext context,
  RouteExecutionReview review,
) {
  final coveredAmounts = _summarizeAmounts(context, [
    for (final allowance in review.sufficientAllowances)
      _AmountPart(allowance.token, allowance.requiredAmount),
  ]);
  return UnifiedSwapNotice(
    title: unifiedSwapText(
      context,
      'review.sufficientApprovalTitle',
      'No new token approval needed',
    ),
    message: unifiedSwapText(
      context,
      'review.sufficientApprovalBody',
      'Your existing permission already covers {amount}. No broader '
          'permission will be requested.',
      namedArgs: {'amount': coveredAmounts},
    ),
    tone: UnifiedSwapNoticeTone.info,
    icon: Icons.verified_user_outlined,
  );
}

String _permissionComparisonSummary(
  BuildContext context,
  RouteExecutionReview review,
) {
  if (review.approvals.isEmpty && review.sufficientAllowances.isEmpty) {
    return unifiedSwapText(
      context,
      'review.permissionComparisonNone',
      'No token approval',
    );
  }
  return [
    for (final allowance in review.sufficientAllowances)
      unifiedSwapText(
        context,
        'review.permissionComparisonSufficient',
        'Existing permission · {amount} · spender {spender}',
        namedArgs: {
          'amount': swapAmount(allowance.requiredAmount, allowance.token),
          'spender': allowance.spender,
        },
      ),
    for (final approval in review.approvals)
      unifiedSwapText(
        context,
        approval.resetRequired
            ? 'review.permissionComparisonReset'
            : 'review.permissionComparisonExact',
        approval.resetRequired
            ? 'Reset, then exact approval · {amount} · spender {spender}'
            : 'Exact approval · {amount} · spender {spender}',
        namedArgs: {
          'amount': swapAmount(approval.exactAmount, approval.token),
          'spender': approval.spender,
        },
      ),
  ].join('; ');
}

class _WarningsReview extends StatelessWidget {
  const _WarningsReview({required this.warnings});

  final List<RouteReviewWarning> warnings;

  @override
  Widget build(BuildContext context) {
    return SwapSectionCard(
      title: unifiedSwapText(context, 'review.warnings', 'Warnings'),
      icon: Icons.warning_amber_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final warning in warnings)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    warning.isKnown ? Icons.info_outline : Icons.error_outline,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: Text(_warning(context, warning.kind))),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _ReviewNotice extends StatelessWidget {
  const _ReviewNotice({
    required this.title,
    required this.message,
    required this.error,
    super.key,
  });

  final String title;
  final String message;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      liveRegion: true,
      container: true,
      child: Material(
        color: error ? colors.errorContainer : colors.secondaryContainer,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 4),
              Text(message),
            ],
          ),
        ),
      ),
    );
  }
}

String _warning(
  BuildContext context,
  RouteReviewWarningKind kind,
) => switch (kind) {
  RouteReviewWarningKind.highPriceImpact => unifiedSwapText(
    context,
    'review.warning.highPriceImpact',
    'Price impact is 3% or greater. Check minimum received carefully.',
  ),
  RouteReviewWarningKind.lowLiquidity => unifiedSwapText(
    context,
    'review.warning.lowLiquidity',
    'Authoritative route data indicates low liquidity.',
  ),
  RouteReviewWarningKind.unknownToken => unifiedSwapText(
    context,
    'review.warning.unknownToken',
    'Confirm the full token contract and destination network.',
  ),
  RouteReviewWarningKind.notAtomicEndToEnd => unifiedSwapText(
    context,
    'review.warning.multistepSettlement',
    'This route completes in separate protected steps rather than all at once.',
  ),
  RouteReviewWarningKind.makerOrderNotReserved => unifiedSwapText(
    context,
    'review.warning.exchangeAvailability',
    'Exchange availability is checked again before funds move and may change.',
  ),
  RouteReviewWarningKind.bridgeRecoveryRequired => unifiedSwapText(
    context,
    'review.warning.bridgeRecoveryRequired',
    'This route may require recovery if its cross-network transfer is interrupted.',
  ),
  RouteReviewWarningKind.intermediateAssetPossible => unifiedSwapText(
    context,
    'review.warning.intermediateAssetPossible',
    'Recovery may return an intermediate asset instead of the final asset.',
  ),
  RouteReviewWarningKind.unrankableFees => unifiedSwapText(
    context,
    'review.warning.unrankableFees',
    'Fresh comparable fee valuation is unavailable for this route.',
  ),
  RouteReviewWarningKind.externalRecipient => unifiedSwapText(
    context,
    'review.warning.externalRecipient',
    'Funds will be sent to an external recipient.',
  ),
  RouteReviewWarningKind.unknown => unifiedSwapText(
    context,
    'review.warning.unknown',
    'An unknown warning prevents this route from executing.',
  ),
};

class _AmountPart {
  const _AmountPart(this.asset, this.amount);

  final UnifiedSwapAssetIdentity asset;
  final String amount;
}

class _AmountTotal {
  _AmountTotal(this.asset, this.amount);

  final UnifiedSwapAssetIdentity asset;
  BigInt amount;
}

String _summarizeAmounts(BuildContext context, List<_AmountPart> parts) {
  if (parts.isEmpty) {
    return unifiedSwapText(context, 'common.unavailable', 'Unavailable');
  }
  final totals = <_AmountTotal>[];
  for (final part in parts) {
    final index = totals.indexWhere(
      (total) => total.asset.sameIdentity(part.asset),
    );
    final amount = BigInt.parse(part.amount);
    if (index == -1) {
      totals.add(_AmountTotal(part.asset, amount));
    } else {
      totals[index].amount += amount;
    }
  }
  return totals
      .map((total) => swapAmount('${total.amount}', total.asset))
      .join(' + ');
}

bool _isSafeReview(RouteExecutionReview review) =>
    review.isExecutable &&
    review.fees.every(
      (fee) => fee.kind != RouteFeeKind.unknown && _hasKnownIdentity(fee.asset),
    ) &&
    review.nonNetworkFeeLimits.every(
      (limit) =>
          limit.kind != RouteFeeKind.unknown && _hasKnownIdentity(limit.asset),
    ) &&
    review.networkFeeCaps.every((cap) => _hasKnownIdentity(cap.asset)) &&
    review.approvals.every((approval) => _hasKnownIdentity(approval.token)) &&
    review.sufficientAllowances.every(
      (allowance) => _hasKnownIdentity(allowance.token),
    );

bool _hasKnownIdentity(UnifiedSwapAssetIdentity asset) =>
    asset.chainFamily != UnifiedSwapChainFamily.unknown &&
    asset.kind != UnifiedSwapAssetKind.unknown;
