import 'package:flutter/material.dart';
import 'package:web_dex/features/unified_swap/domain/route_activity_models.dart';
import 'package:web_dex/features/unified_swap/domain/route_execution_models.dart';
import 'package:web_dex/features/unified_swap/domain/unified_swap_capability_policy.dart';
import 'package:web_dex/features/unified_swap/presentation/swap/swap_widgets.dart';
import 'package:web_dex/features/unified_swap/presentation/unified_swap_design.dart';

class RouteReviewView extends StatelessWidget {
  const RouteReviewView({
    required this.review,
    required this.onAccept,
    required this.acceptInFlight,
    required this.executionEnabled,
    required this.clipboardWriter,
    required this.announcement,
    this.failureMessage,
    this.now,
    super.key,
  });

  final RouteExecutionReview review;
  final VoidCallback onAccept;
  final bool acceptInFlight;
  final bool executionEnabled;
  final SwapClipboardWriter clipboardWriter;
  final SwapAnnouncement announcement;
  final String? failureMessage;
  final DateTime Function()? now;

  @override
  Widget build(BuildContext context) {
    final current = now?.call() ?? DateTime.now().toUtc();
    final expired = review.isExpiredAt(current);
    final safeReview = _isSafeReview(review);
    final executable = safeReview && !expired && executionEnabled;
    final colors = UnifiedSwapDesign.colors(context);
    return ColoredBox(
      color: colors.canvas,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final desktop =
              constraints.maxWidth >= UnifiedSwapDesign.desktopBreakpoint;
          final panel = _ReviewPanel(
            key: const Key('unified-swap-review'),
            review: review,
            expired: expired,
            safeReview: safeReview,
            executable: executable,
            acceptInFlight: acceptInFlight,
            executionEnabled: executionEnabled,
            failureMessage: failureMessage,
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
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: _ReviewedIntentPreview(review: review)),
                    const SizedBox(width: 24),
                    SizedBox(width: 520, child: panel),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ReviewPanel extends StatelessWidget {
  const _ReviewPanel({
    required this.review,
    required this.expired,
    required this.safeReview,
    required this.executable,
    required this.acceptInFlight,
    required this.executionEnabled,
    required this.failureMessage,
    required this.onAccept,
    required this.clipboardWriter,
    required this.announcement,
    super.key,
  });

  final RouteExecutionReview review;
  final bool expired;
  final bool safeReview;
  final bool executable;
  final bool acceptInFlight;
  final bool executionEnabled;
  final String? failureMessage;
  final VoidCallback onAccept;
  final SwapClipboardWriter clipboardWriter;
  final SwapAnnouncement announcement;

  @override
  Widget build(BuildContext context) {
    final colors = UnifiedSwapDesign.colors(context);
    final desktop =
        MediaQuery.sizeOf(context).width >= UnifiedSwapDesign.desktopBreakpoint;
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
          Expanded(
            child: ListView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: desktop
                  ? const EdgeInsets.all(18)
                  : UnifiedSwapDesign.pagePadding(context),
              children: [
                UnifiedSwapPageTitle(
                  title: unifiedSwapText(
                    context,
                    'review.title',
                    'Review swap',
                  ),
                  subtitle: unifiedSwapText(
                    context,
                    'review.subtitle',
                    'Confirm the exact outcome, protection, costs, and '
                        'permission before funds move.',
                  ),
                ),
                const SizedBox(height: 12),
                UnifiedSwapBadge(
                  label: unifiedSwapText(
                    context,
                    'review.readyBadge',
                    'Ready to review',
                  ),
                  tone: UnifiedSwapNoticeTone.brand,
                ),
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
                      'The wallet received an unknown route, warning, asset, '
                          'or network variant. No funds can move.',
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
                      'You can inspect these terms, but new route execution '
                          'is currently unavailable.',
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
                const SizedBox(height: 12),
                _ReviewSummary(review: review),
                const SizedBox(height: 12),
                UnifiedSwapNotice(
                  title: unifiedSwapText(
                    context,
                    'review.minimumTitle',
                    'You’ll receive at least',
                  ),
                  message: swapAmount(
                    review.minimumReceive,
                    review.destination,
                  ),
                  tone: UnifiedSwapNoticeTone.success,
                  icon: Icons.shield_outlined,
                ),
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
                      _AddressReview(review: review),
                      const SizedBox(height: 12),
                      _RouteSteps(steps: review.steps),
                      const SizedBox(height: 12),
                      SwapSectionCard(
                        title: unifiedSwapText(
                          context,
                          'review.executionIdentity',
                          'Execution identity',
                        ),
                        icon: Icons.fingerprint_rounded,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              unifiedSwapText(
                                context,
                                'review.fullExecutionId',
                                'Full execution ID',
                              ),
                            ),
                            SwapCopyableValue(
                              label: unifiedSwapText(
                                context,
                                'common.executionId',
                                'Execution ID',
                              ),
                              value: review.routeExecutionId,
                              valueKey: 'swap-review-execution-id',
                              clipboardWriter: clipboardWriter,
                              announcement: announcement,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              unifiedSwapText(
                                context,
                                'review.candidateDigest',
                                'Candidate digest',
                              ),
                            ),
                            SelectableText(review.candidateDigest),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                if (review.approvals.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _ApprovalReview(approvals: review.approvals),
                ] else ...[
                  const SizedBox(height: 12),
                  UnifiedSwapNotice(
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
                  ),
                ],
                if (review.warnings.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _WarningsReview(warnings: review.warnings),
                ],
                const SizedBox(height: 16),
              ],
            ),
          ),
          DecoratedBox(
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
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    FilledButton.icon(
                      key: const Key('swap-review-confirm'),
                      style: UnifiedSwapDesign.primaryButtonStyle(context),
                      onPressed: executable && !acceptInFlight
                          ? onAccept
                          : null,
                      icon: acceptInFlight
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.lock_open_rounded),
                      label: Text(
                        acceptInFlight
                            ? unifiedSwapText(
                                context,
                                'review.startingSwap',
                                'Starting swap',
                              )
                            : unifiedSwapText(
                                context,
                                'review.startSwap',
                                'Start swap',
                              ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      unifiedSwapText(
                        context,
                        'review.leavingNotice',
                        'Leaving this screen never cancels work after it '
                            'starts.',
                      ),
                      textAlign: TextAlign.center,
                      style: UnifiedSwapDesign.typography(context).bodySmall,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReviewedIntentPreview extends StatelessWidget {
  const _ReviewedIntentPreview({required this.review});

  final RouteExecutionReview review;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 500),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              UnifiedSwapPageTitle(
                title: unifiedSwapText(context, 'entry.title', 'Swap'),
              ),
              const SizedBox(height: 20),
              UnifiedSwapSurface(
                borderColor: UnifiedSwapDesign.colors(context).controlBorder,
                radius: 20,
                child: _PreviewLeg(
                  label: unifiedSwapText(context, 'entry.youPay', 'You pay'),
                  amount: swapAmount(review.sourceAmount, review.source),
                  asset: review.source,
                  address: review.resolvedSourceAddress,
                ),
              ),
              Transform.translate(
                offset: const Offset(0, 0),
                child: const SizedBox(
                  height: 48,
                  child: Center(child: Icon(Icons.swap_vert_rounded)),
                ),
              ),
              UnifiedSwapSurface(
                borderColor: UnifiedSwapDesign.colors(context).controlBorder,
                radius: 20,
                child: _PreviewLeg(
                  label: unifiedSwapText(
                    context,
                    'entry.youReceive',
                    'You receive',
                  ),
                  amount: swapAmount(
                    review.expectedReceive,
                    review.destination,
                  ),
                  asset: review.destination,
                  address: review.recipient,
                ),
              ),
              const SizedBox(height: 14),
              UnifiedSwapNotice(
                title: unifiedSwapText(
                  context,
                  'review.sidePanelTitle',
                  'Review is open in the side panel',
                ),
                message: unifiedSwapText(
                  context,
                  'review.sidePanelBody',
                  'Editing the swap closes this Review and checks a fresh '
                      'quote.',
                ),
                tone: UnifiedSwapNoticeTone.neutral,
                icon: Icons.info_outline_rounded,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PreviewLeg extends StatelessWidget {
  const _PreviewLeg({
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: UnifiedSwapDesign.typography(context).labelLarge),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: Text(
                amount,
                style: UnifiedSwapDesign.typography(context).amountDisplay,
              ),
            ),
            const SizedBox(width: 12),
            UnifiedSwapAssetAvatar(asset: asset, size: 38),
            const SizedBox(width: 10),
            Text(
              asset.ticker,
              style: UnifiedSwapDesign.typography(context).cardTitle,
            ),
          ],
        ),
        const SizedBox(height: 14),
        Divider(color: UnifiedSwapDesign.colors(context).border),
        const SizedBox(height: 8),
        Text(
          unifiedSwapShortIdentity(address),
          style: UnifiedSwapDesign.typography(context).bodySmall,
        ),
      ],
    );
  }
}

class _ReviewSummary extends StatelessWidget {
  const _ReviewSummary({required this.review});

  final RouteExecutionReview review;

  @override
  Widget build(BuildContext context) {
    return SwapSectionCard(
      title: unifiedSwapText(context, 'review.exactTerms', 'Exact terms'),
      icon: Icons.receipt_long_outlined,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 680;
          final items = [
            _Term(
              label: unifiedSwapText(context, 'review.youSend', 'You send'),
              value: swapAmount(review.sourceAmount, review.source),
              details: swapAssetLabel(context, review.source),
            ),
            _Term(
              label: unifiedSwapText(
                context,
                'review.expectedReceive',
                'Expected receive',
              ),
              value: swapAmount(review.expectedReceive, review.destination),
              details: swapAssetLabel(context, review.destination),
            ),
            _Term(
              label: unifiedSwapText(
                context,
                'review.minimumReceive',
                'Minimum receive',
              ),
              value: swapAmount(review.minimumReceive, review.destination),
              details: unifiedSwapText(
                context,
                'review.minimumProtected',
                'Protected by the consented minimum',
              ),
            ),
            _Term(
              label: unifiedSwapText(
                context,
                'review.estimatedTime',
                'Estimated time',
              ),
              value: swapDuration(context, review.estimatedDuration),
              details: unifiedSwapText(
                context,
                'review.estimateDisclaimer',
                'Estimate, not a guarantee',
              ),
            ),
          ];
          if (!wide) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var index = 0; index < items.length; index++) ...[
                  items[index],
                  if (index != items.length - 1) const Divider(height: 24),
                ],
              ],
            );
          }
          const gap = 16.0;
          final width = (constraints.maxWidth - gap) / 2;
          return Wrap(
            spacing: gap,
            runSpacing: gap,
            children: [
              for (final item in items) SizedBox(width: width, child: item),
            ],
          );
        },
      ),
    );
  }
}

class _Term extends StatelessWidget {
  const _Term({
    required this.label,
    required this.value,
    required this.details,
  });

  final String label;
  final String value;
  final String details;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: unifiedSwapText(
        context,
        'review.termSemantics',
        '{label}: {value}. {details}',
        namedArgs: {'label': label, 'value': value, 'details': details},
      ),
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 2),
            Text(value, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 2),
            Text(details, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

class _AddressReview extends StatelessWidget {
  const _AddressReview({required this.review});

  final RouteExecutionReview review;

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
          SelectableText(
            review.resolvedSourceAddress,
            key: const Key('swap-review-source-address'),
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
          SelectableText(
            review.recipient,
            key: const Key('swap-review-recipient'),
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
                    '${limit.stageId == null ? '' : '${unifiedSwapText(context, 'common.stepNumber', 'Step {number}', namedArgs: {'number': '${limit.stageId}'})} · '}'
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
                label: unifiedSwapText(
                  context,
                  'common.stepNumber',
                  'Step {number}',
                  namedArgs: {'number': cap.stageId},
                ),
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
        'review.stepKind.atomic',
        'Direct exchange',
      ),
      RouteReviewStepKind.external => unifiedSwapText(
        context,
        'review.stepKind.external',
        'Unified transfer',
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

class _ApprovalReview extends StatelessWidget {
  const _ApprovalReview({required this.approvals});

  final List<RouteApprovalScope> approvals;

  @override
  Widget build(BuildContext context) {
    return SwapSectionCard(
      title: unifiedSwapText(
        context,
        'review.exactTokenApproval',
        'Exact token approval',
      ),
      icon: Icons.verified_user_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var index = 0; index < approvals.length; index++) ...[
            Text(
              '${unifiedSwapText(context, 'common.stepNumber', 'Step {number}', namedArgs: {'number': approvals[index].stageId})} · '
              '${swapAssetLabel(context, approvals[index].token)}',
              style: Theme.of(context).textTheme.labelLarge,
            ),
            Text(
              unifiedSwapText(
                context,
                'review.exactApprovalAmount',
                'Exact amount: {amount}',
                namedArgs: {
                  'amount': swapAmount(
                    approvals[index].exactAmount,
                    approvals[index].token,
                  ),
                },
              ),
            ),
            Text(unifiedSwapText(context, 'review.spender', 'Spender')),
            SelectableText(approvals[index].spender),
            Text(
              approvals[index].resetRequired
                  ? unifiedSwapText(
                      context,
                      'review.allowanceReset',
                      'Existing allowance will be reset before exact approval.',
                    )
                  : unifiedSwapText(
                      context,
                      'review.allowanceNoReset',
                      'No allowance reset is required.',
                    ),
            ),
            if (index != approvals.length - 1) const Divider(height: 24),
          ],
        ],
      ),
    );
  }
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
    'review.warning.notAtomicEndToEnd',
    'This route is not atomic from end to end.',
  ),
  RouteReviewWarningKind.makerOrderNotReserved => unifiedSwapText(
    context,
    'review.warning.makerOrderNotReserved',
    'The atomic order is rechecked before funds move and may become unavailable.',
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
    review.approvals.every((approval) => _hasKnownIdentity(approval.token));

bool _hasKnownIdentity(UnifiedSwapAssetIdentity asset) =>
    asset.chainFamily != UnifiedSwapChainFamily.unknown &&
    asset.kind != UnifiedSwapAssetKind.unknown;
