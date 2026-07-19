import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:web_dex/features/unified_swap/application/unified_swap_bloc.dart';
import 'package:web_dex/features/unified_swap/domain/unified_swap_capability_policy.dart';
import 'package:web_dex/features/unified_swap/domain/unified_swap_quote_models.dart';
import 'package:web_dex/features/unified_swap/domain/unified_swap_selection_models.dart';
import 'package:web_dex/features/unified_swap/presentation/swap/swap_widgets.dart';
import 'package:web_dex/features/unified_swap/presentation/unified_swap_design.dart';

typedef UnifiedSwapMaximumAmountResolver =
    Future<String?> Function(UnifiedSwapIntent intent);

class UnifiedSwapEntryView extends StatefulWidget {
  const UnifiedSwapEntryView({
    required this.state,
    required this.onIntentChanged,
    required this.onCandidateSelected,
    required this.onRevalidate,
    required this.onReviewRequested,
    required this.canReview,
    required this.reviewUnavailableMessage,
    this.maximumAmountResolver,
    this.selectionGateway,
    this.intentEditable = true,
    this.reviewInFlight = false,
    this.reviewFailure,
    this.now,
    super.key,
  });

  final UnifiedSwapState state;
  final ValueChanged<UnifiedSwapIntent> onIntentChanged;
  final ValueChanged<String> onCandidateSelected;
  final VoidCallback onRevalidate;
  final ValueChanged<UnifiedSwapQuoteCandidate> onReviewRequested;
  final bool canReview;
  final String reviewUnavailableMessage;
  final UnifiedSwapMaximumAmountResolver? maximumAmountResolver;
  final UnifiedSwapSelectionGateway? selectionGateway;
  final bool intentEditable;
  final bool reviewInFlight;
  final String? reviewFailure;
  final DateTime Function()? now;

  @override
  State<UnifiedSwapEntryView> createState() => _UnifiedSwapEntryViewState();
}

class _UnifiedSwapEntryViewState extends State<UnifiedSwapEntryView> {
  late final TextEditingController _amountController;
  late final TextEditingController _recipientController;
  final FocusNode _amountFocus = FocusNode();
  final FocusNode _recipientFocus = FocusNode();
  Timer? _intentTimer;
  String? _amountError;
  String? _recipientError;
  bool _draftDirty = false;
  bool _maxInFlight = false;
  bool _selectionInFlight = false;
  int _revisionSeed = 0;

  @override
  void initState() {
    super.initState();
    final intent = widget.state.intent;
    _revisionSeed = intent?.revision ?? 0;
    _amountController = TextEditingController(
      text: intent == null
          ? ''
          : _editableAmount(intent.sourceAmount, intent.source.decimals),
    );
    _recipientController = TextEditingController(text: intent?.recipient ?? '');
  }

  @override
  void didUpdateWidget(UnifiedSwapEntryView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldIntent = oldWidget.state.intent;
    final intent = widget.state.intent;
    if (intent != null && intent != oldIntent) {
      _revisionSeed = intent.revision > _revisionSeed
          ? intent.revision
          : _revisionSeed;
      final sourceAmount = _editableAmount(
        intent.sourceAmount,
        intent.source.decimals,
      );
      if (!_amountFocus.hasFocus && _amountController.text != sourceAmount) {
        _amountController.text = sourceAmount;
      }
      if (!_recipientFocus.hasFocus &&
          _recipientController.text != intent.recipient) {
        _recipientController.text = intent.recipient;
      }
      _draftDirty = false;
    }
  }

  @override
  void dispose() {
    _intentTimer?.cancel();
    _amountController.dispose();
    _recipientController.dispose();
    _amountFocus.dispose();
    _recipientFocus.dispose();
    super.dispose();
  }

  void _draftChanged(String _) {
    _intentTimer?.cancel();
    setState(() {
      _draftDirty = true;
      _amountError = null;
      _recipientError = null;
    });
    _intentTimer = Timer(const Duration(milliseconds: 300), _submitDraft);
  }

  void _submitDraft() {
    final current = widget.state.intent;
    if (current == null || !widget.intentEditable) return;
    final amount = _smallestUnits(
      _amountController.text,
      current.source.decimals,
    );
    final recipient = _recipientController.text.trim();
    if (amount == null || BigInt.parse(amount) == BigInt.zero) {
      setState(() {
        _amountError = unifiedSwapText(
          context,
          'entry.amountError',
          'Enter an amount greater than zero with no more than {decimals} '
              'decimal places.',
          namedArgs: {'decimals': '${current.source.decimals}'},
        );
      });
      return;
    }
    if (recipient.isEmpty) {
      setState(() {
        _recipientError = unifiedSwapText(
          context,
          'entry.recipientRequired',
          'A recipient is required.',
        );
      });
      return;
    }
    _revisionSeed++;
    widget.onIntentChanged(
      UnifiedSwapIntent(
        revision: _revisionSeed,
        source: current.source,
        destination: current.destination,
        sourceAmount: amount,
        sourceSelection: current.sourceSelection,
        recipient: recipient,
        slippageBps: current.slippageBps,
        sourceTokenTrust: current.sourceTokenTrust,
        destinationTokenTrust: current.destinationTokenTrust,
        unknownTokenConfirmed: current.unknownTokenConfirmed,
        externalRecipientConfirmed:
            recipient == current.recipient &&
            current.externalRecipientConfirmed,
      ),
    );
  }

  Future<void> _useMaximum() async {
    final resolver = widget.maximumAmountResolver;
    final intent = widget.state.intent;
    if (resolver == null || intent == null || _maxInFlight) return;
    setState(() => _maxInFlight = true);
    try {
      final maximum = await resolver(intent);
      if (!mounted) return;
      if (maximum == null ||
          !RegExp(r'^(?:0|[1-9][0-9]*)$').hasMatch(maximum) ||
          BigInt.parse(maximum) == BigInt.zero) {
        setState(() {
          _amountError = unifiedSwapText(
            context,
            'entry.maxUnavailable',
            'Max is unavailable until balances and network costs are fresh.',
          );
        });
        return;
      }
      _amountController.text = _editableAmount(maximum, intent.source.decimals);
      _submitDraft();
    } on Object {
      if (mounted) {
        setState(() {
          _amountError = unifiedSwapText(
            context,
            'entry.maxUnavailable',
            'Max is unavailable until balances and network costs are fresh.',
          );
        });
      }
    } finally {
      if (mounted) setState(() => _maxInFlight = false);
    }
  }

  Future<void> _chooseAsset({required bool source}) async {
    final gateway = widget.selectionGateway;
    final current = widget.state.intent;
    if (gateway == null ||
        current == null ||
        _selectionInFlight ||
        !widget.intentEditable) {
      if (current != null) {
        await _showAssetIdentity(
          context,
          source ? current.source : current.destination,
        );
      }
      return;
    }
    setState(() => _selectionInFlight = true);
    try {
      final inventory = await gateway.selectionInventory();
      if (!mounted ||
          inventory == null ||
          widget.state.intent?.revision != current.revision) {
        return;
      }
      final options = source
          ? inventory.sources
          : inventory.destinationsFor(current.source);
      final selected = await _showAssetSelection(
        context,
        source: source,
        options: options,
        selected: source ? current.source : current.destination,
      );
      if (!mounted ||
          selected == null ||
          widget.state.intent?.revision != current.revision) {
        return;
      }
      final next = source
          ? await gateway.selectSourceAsset(current, selected)
          : await gateway.selectDestinationAsset(current, selected);
      if (!mounted ||
          next == null ||
          next.revision <= current.revision ||
          widget.state.intent?.revision != current.revision) {
        return;
      }
      widget.onIntentChanged(next);
    } on Object {
      if (mounted) _showSelectionFailure(source: source);
    } finally {
      if (mounted) setState(() => _selectionInFlight = false);
    }
  }

  Future<void> _chooseSourceAddress() async {
    final gateway = widget.selectionGateway;
    final current = widget.state.intent;
    if (gateway == null ||
        current == null ||
        _selectionInFlight ||
        !widget.intentEditable) {
      if (current != null) await _showSourceIdentity(context, current);
      return;
    }
    setState(() => _selectionInFlight = true);
    try {
      final options = await gateway.sourceAddressOptions(current.source);
      if (!mounted || widget.state.intent?.revision != current.revision) return;
      final selected = await _showSourceAddressSelection(
        context,
        asset: current.source,
        options: options,
        selected: current.sourceSelection,
      );
      if (!mounted ||
          selected == null ||
          widget.state.intent?.revision != current.revision) {
        return;
      }
      final next = await gateway.selectSourceAddress(current, selected);
      if (!mounted ||
          next == null ||
          next.revision <= current.revision ||
          widget.state.intent?.revision != current.revision) {
        return;
      }
      widget.onIntentChanged(next);
    } on Object {
      if (mounted) _showSelectionFailure(source: true);
    } finally {
      if (mounted) setState(() => _selectionInFlight = false);
    }
  }

  void _showSelectionFailure({required bool source}) {
    setState(() {
      final message = unifiedSwapText(
        context,
        'picker.selectionUnavailable',
        'That exact wallet selection is no longer available. Your swap stayed '
            'unchanged.',
      );
      if (source) {
        _amountError = message;
      } else {
        _recipientError = message;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final intent = state.intent;
    if (intent == null) {
      return SwapUnavailable(
        key: const Key('swap-intent-unavailable'),
        title: unifiedSwapText(
          context,
          'entry.detailsUnavailableTitle',
          'Swap details are unavailable',
        ),
        message: unifiedSwapText(
          context,
          'entry.detailsUnavailableBody',
          'Select an activated source, destination, funded address, and '
              'recipient in the wallet before requesting a route.',
        ),
      );
    }
    final selected = state.selectedCandidate;
    final colors = UnifiedSwapDesign.colors(context);
    return ColoredBox(
      color: colors.canvas,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: UnifiedSwapDesign.contentWidth,
          ),
          child: ListView(
            key: const Key('unified-swap-entry'),
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: UnifiedSwapDesign.pagePadding(context),
            children: [
              UnifiedSwapPageTitle(
                title: unifiedSwapText(context, 'entry.title', 'Swap'),
              ),
              const SizedBox(height: 20),
              _SwapAmountStack(
                intent: intent,
                selected: selected,
                amountController: _amountController,
                recipientController: _recipientController,
                amountFocus: _amountFocus,
                recipientFocus: _recipientFocus,
                amountError: _amountError,
                recipientError: _recipientError,
                maxInFlight: _maxInFlight,
                selectionInFlight: _selectionInFlight,
                intentEditable: widget.intentEditable,
                canUseMaximum: widget.maximumAmountResolver != null,
                onDraftChanged: _draftChanged,
                onAmountSubmitted: () {
                  _intentTimer?.cancel();
                  _submitDraft();
                  _recipientFocus.requestFocus();
                },
                onRecipientSubmitted: () {
                  _intentTimer?.cancel();
                  _submitDraft();
                },
                onMaximum: _useMaximum,
                onSourceAsset: () => _chooseAsset(source: true),
                onDestinationAsset: () => _chooseAsset(source: false),
                onSourceAddress: _chooseSourceAddress,
              ),
              // Existing automation reads exact activated identities. Keep the
              // data in the widget tree without adding prototype-visible copy.
              _ExactIdentityAnchors(intent: intent),
              const SizedBox(height: 14),
              AnimatedSwitcher(
                duration: UnifiedSwapDesign.motion(
                  context,
                ).resolve(context, UnifiedSwapDesign.motion(context).standard),
                child: _draftDirty
                    ? const _QuoteCheckingCard(key: Key('swap-draft-progress'))
                    : _QuoteBody(
                        state: state,
                        onCandidateSelected: widget.onCandidateSelected,
                        onRevalidate: widget.onRevalidate,
                        onReviewRequested: widget.onReviewRequested,
                        canReview: widget.canReview,
                        reviewUnavailableMessage:
                            widget.reviewUnavailableMessage,
                        reviewInFlight: widget.reviewInFlight,
                        reviewFailure: widget.reviewFailure,
                        now: widget.now?.call() ?? DateTime.now().toUtc(),
                        destination: intent.destination,
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SwapAmountStack extends StatelessWidget {
  const _SwapAmountStack({
    required this.intent,
    required this.selected,
    required this.amountController,
    required this.recipientController,
    required this.amountFocus,
    required this.recipientFocus,
    required this.amountError,
    required this.recipientError,
    required this.maxInFlight,
    required this.selectionInFlight,
    required this.intentEditable,
    required this.canUseMaximum,
    required this.onDraftChanged,
    required this.onAmountSubmitted,
    required this.onRecipientSubmitted,
    required this.onMaximum,
    required this.onSourceAsset,
    required this.onDestinationAsset,
    required this.onSourceAddress,
  });

  final UnifiedSwapIntent intent;
  final UnifiedSwapQuoteCandidate? selected;
  final TextEditingController amountController;
  final TextEditingController recipientController;
  final FocusNode amountFocus;
  final FocusNode recipientFocus;
  final String? amountError;
  final String? recipientError;
  final bool maxInFlight;
  final bool selectionInFlight;
  final bool intentEditable;
  final bool canUseMaximum;
  final ValueChanged<String> onDraftChanged;
  final VoidCallback onAmountSubmitted;
  final VoidCallback onRecipientSubmitted;
  final VoidCallback onMaximum;
  final VoidCallback onSourceAsset;
  final VoidCallback onDestinationAsset;
  final VoidCallback onSourceAddress;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _AmountCard(
          key: const Key('swap-source-identity'),
          label: unifiedSwapText(context, 'entry.youPay', 'You pay'),
          asset: intent.source,
          amountField: TextField(
            key: const Key('swap-amount-input'),
            controller: amountController,
            focusNode: amountFocus,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
            ],
            textInputAction: TextInputAction.next,
            enabled: intentEditable,
            onChanged: onDraftChanged,
            onSubmitted: (_) => onAmountSubmitted(),
            style: UnifiedSwapDesign.typography(context).amountDisplay,
            decoration: InputDecoration.collapsed(
              hintText: '0',
              hintStyle: UnifiedSwapDesign.typography(context).amountDisplay
                  .copyWith(
                    color: UnifiedSwapDesign.colors(context).textTertiary,
                  ),
            ),
          ),
          fiatText: unifiedSwapText(
            context,
            'entry.priceEstimateUnavailable',
            'Price estimate unavailable',
          ),
          footer: Row(
            children: [
              Expanded(
                child: TextButton(
                  key: const Key('swap-source-selector'),
                  onPressed: !intentEditable || selectionInFlight
                      ? null
                      : onSourceAddress,
                  style: TextButton.styleFrom(
                    minimumSize: const Size(48, 48),
                    alignment: AlignmentDirectional.centerStart,
                    padding: EdgeInsets.zero,
                  ),
                  child: Text(
                    '${unifiedSwapText(context, 'entry.from', 'From')} '
                    '${_sourceSelectionShort(context, intent)}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Tooltip(
                message: canUseMaximum
                    ? unifiedSwapText(
                        context,
                        'entry.maxTooltip',
                        'Use the gas-aware maximum',
                      )
                    : unifiedSwapText(
                        context,
                        'entry.maxDisabledTooltip',
                        'A fresh gas-aware balance check is unavailable',
                      ),
                child: TextButton(
                  key: const Key('swap-max'),
                  onPressed: !intentEditable || !canUseMaximum || maxInFlight
                      ? null
                      : onMaximum,
                  child: maxInFlight
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(unifiedSwapText(context, 'entry.max', 'Max')),
                ),
              ),
            ],
          ),
          assetSelectorKey: const Key('swap-source-asset-selector'),
          onAssetPressed: !intentEditable || selectionInFlight
              ? null
              : onSourceAsset,
          error: amountError,
        ),
        Transform.translate(
          offset: const Offset(0, 0),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: UnifiedSwapDesign.colors(context).surfaceHighest,
              border: Border.all(
                color: UnifiedSwapDesign.colors(context).canvas,
                width: 6,
              ),
              shape: BoxShape.circle,
            ),
            child: const SizedBox.square(
              dimension: 48,
              child: Icon(Icons.swap_vert_rounded, size: 22),
            ),
          ),
        ),
        _AmountCard(
          key: const Key('swap-destination-identity'),
          label: unifiedSwapText(context, 'entry.youReceive', 'You receive'),
          asset: intent.destination,
          amountField: Text(
            selected == null
                ? '—'
                : _editableAmount(
                    selected!.expectedReceive,
                    intent.destination.decimals,
                  ),
            key: const Key('swap-receive-amount'),
            maxLines: 1,
            overflow: TextOverflow.fade,
            softWrap: false,
            style: UnifiedSwapDesign.typography(context).amountDisplay,
          ),
          fiatText: unifiedSwapText(
            context,
            'entry.priceEstimateUnavailable',
            'Price estimate unavailable',
          ),
          footer: TextField(
            key: const Key('swap-recipient-input'),
            controller: recipientController,
            focusNode: recipientFocus,
            keyboardType: TextInputType.text,
            textInputAction: TextInputAction.done,
            enabled: intentEditable,
            autocorrect: false,
            enableSuggestions: false,
            onChanged: onDraftChanged,
            onSubmitted: (_) => onRecipientSubmitted(),
            minLines: 1,
            maxLines: 2,
            style: UnifiedSwapDesign.typography(context).bodyMedium,
            decoration: InputDecoration(
              isDense: true,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(vertical: 12),
              prefixText: '${unifiedSwapText(context, 'entry.to', 'To')} ',
              suffixIcon: Padding(
                padding: const EdgeInsetsDirectional.only(start: 8),
                child: Center(
                  widthFactor: 1,
                  child: Text(
                    unifiedSwapText(context, 'entry.change', 'Change'),
                    style: UnifiedSwapDesign.typography(context).labelLarge
                        .copyWith(
                          color: UnifiedSwapDesign.colors(context).brandHover,
                        ),
                  ),
                ),
              ),
            ),
          ),
          assetSelectorKey: const Key('swap-destination-asset-selector'),
          onAssetPressed: !intentEditable || selectionInFlight
              ? null
              : onDestinationAsset,
          error: recipientError,
        ),
      ],
    );
  }
}

class _AmountCard extends StatelessWidget {
  const _AmountCard({
    required this.label,
    required this.asset,
    required this.amountField,
    required this.fiatText,
    required this.footer,
    required this.assetSelectorKey,
    required this.onAssetPressed,
    this.error,
    super.key,
  });

  final String label;
  final UnifiedSwapAssetIdentity asset;
  final Widget amountField;
  final String fiatText;
  final Widget footer;
  final Key assetSelectorKey;
  final VoidCallback? onAssetPressed;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final colors = UnifiedSwapDesign.colors(context);
    final type = UnifiedSwapDesign.typography(context);
    final network = unifiedSwapNetworkLabel(context, asset);
    return UnifiedSwapSurface(
      padding: const EdgeInsets.all(18),
      borderColor: error == null ? colors.controlBorder : colors.danger,
      radius: 20,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text(label, style: type.labelLarge)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  unifiedSwapText(
                    context,
                    'entry.balanceAvailable',
                    'Balance in selected address',
                  ),
                  textAlign: TextAlign.end,
                  style: type.bodySmall,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final scaled = MediaQuery.textScalerOf(context).scale(16);
              final compact = constraints.maxWidth < 440 || scaled >= 24;
              final amount = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  amountField,
                  const SizedBox(height: 6),
                  Text(fiatText, style: type.bodyMedium),
                ],
              );
              final picker = UnifiedSwapAssetButton(
                key: assetSelectorKey,
                asset: asset,
                networkLabel: network,
                onPressed: onAssetPressed,
              );
              if (compact) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [amount, const SizedBox(height: 14), picker],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(child: amount),
                  const SizedBox(width: 14),
                  Flexible(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 190),
                      child: picker,
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 16),
          Divider(height: 1, color: colors.border),
          const SizedBox(height: 4),
          footer,
          if (error case final error?) ...[
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.error_outline_rounded,
                  size: 18,
                  color: colors.danger,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    error,
                    style: type.bodySmall.copyWith(color: colors.danger),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _ExactIdentityAnchors extends StatelessWidget {
  const _ExactIdentityAnchors({required this.intent});

  final UnifiedSwapIntent intent;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: SizedBox.shrink(
        child: Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            PositionedDirectional(
              start: 0,
              top: 0,
              child: Text(swapAssetLabel(context, intent.source)),
            ),
            PositionedDirectional(
              start: 0,
              top: 0,
              child: Text(swapAssetLabel(context, intent.destination)),
            ),
            if (intent.source.contractAddress case final contract?)
              PositionedDirectional(start: 0, top: 0, child: Text(contract)),
            if (intent.destination.contractAddress case final contract?)
              PositionedDirectional(start: 0, top: 0, child: Text(contract)),
          ],
        ),
      ),
    );
  }
}

class _QuoteCheckingCard extends StatelessWidget {
  const _QuoteCheckingCard({super.key});

  @override
  Widget build(BuildContext context) {
    return UnifiedSwapSurface(
      semanticLabel: unifiedSwapText(
        context,
        'quote.checkingSemantics',
        'Checking latest swap routes',
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 10),
              Text(
                unifiedSwapText(context, 'quote.checking', 'Checking…'),
                style: UnifiedSwapDesign.typography(context).labelLarge,
              ),
            ],
          ),
          const SizedBox(height: 14),
          const UnifiedSwapSkeleton(width: 170),
          const SizedBox(height: 8),
          const UnifiedSwapSkeleton(height: 14),
        ],
      ),
    );
  }
}

class _QuoteBody extends StatelessWidget {
  const _QuoteBody({
    required this.state,
    required this.onCandidateSelected,
    required this.onRevalidate,
    required this.onReviewRequested,
    required this.canReview,
    required this.reviewUnavailableMessage,
    required this.reviewInFlight,
    required this.reviewFailure,
    required this.now,
    required this.destination,
  });

  final UnifiedSwapState state;
  final ValueChanged<String> onCandidateSelected;
  final VoidCallback onRevalidate;
  final ValueChanged<UnifiedSwapQuoteCandidate> onReviewRequested;
  final bool canReview;
  final String reviewUnavailableMessage;
  final bool reviewInFlight;
  final String? reviewFailure;
  final DateTime now;
  final UnifiedSwapAssetIdentity destination;

  @override
  Widget build(BuildContext context) {
    switch (state.status) {
      case UnifiedSwapQuoteStatus.idle:
        return UnifiedSwapNotice(
          title: unifiedSwapText(
            context,
            'quote.idleTitle',
            'Enter an amount to check routes',
          ),
          message: unifiedSwapText(
            context,
            'quote.idleBody',
            'Your exact source, destination, and recipient stay in the wallet.',
          ),
          tone: UnifiedSwapNoticeTone.neutral,
          icon: Icons.route_outlined,
        );
      case UnifiedSwapQuoteStatus.loading:
        return const _QuoteCheckingCard(key: Key('swap-quote-loading'));
      case UnifiedSwapQuoteStatus.expired:
        return _QuoteStateCard(
          key: const Key('swap-quote-expired'),
          title: unifiedSwapText(
            context,
            'quote.expiredTitle',
            'Quote expired',
          ),
          message: unifiedSwapText(
            context,
            'quote.expiredBody',
            'Prices and network costs changed. Check a fresh quote before '
                'continuing.',
          ),
          actionLabel: unifiedSwapText(
            context,
            'quote.newQuote',
            'Get a new quote',
          ),
          onAction: onRevalidate,
          tone: UnifiedSwapNoticeTone.warning,
        );
      case UnifiedSwapQuoteStatus.unavailable:
        return _QuoteStateCard(
          key: const Key('swap-quote-unavailable'),
          title: unifiedSwapText(
            context,
            'quote.unavailableTitle',
            'A safe quote is unavailable',
          ),
          message: _failureMessage(context, state.failure),
          actionLabel: unifiedSwapText(context, 'common.tryAgain', 'Try again'),
          onAction: onRevalidate,
          tone: UnifiedSwapNoticeTone.danger,
        );
      case UnifiedSwapQuoteStatus.ready:
        break;
    }

    final evaluation = state.evaluation;
    if (evaluation == null || evaluation.candidates.isEmpty) {
      return _QuoteStateCard(
        title: unifiedSwapText(
          context,
          'quote.noRoutesTitle',
          'No executable routes',
        ),
        message: unifiedSwapText(
          context,
          'quote.noRoutesBody',
          'No current route satisfies this exact swap.',
        ),
        actionLabel: unifiedSwapText(context, 'quote.revalidate', 'Revalidate'),
        onAction: onRevalidate,
        tone: UnifiedSwapNoticeTone.warning,
      );
    }
    final ranked = [...evaluation.rankedCandidates.where(isSafeSwapCandidate)]
      ..sort((left, right) => left.rank!.compareTo(right.rank!));
    final unranked = evaluation.unrankableCandidates
        .where(isSafeSwapCandidate)
        .toList(growable: false);
    final inert = evaluation.candidates
        .where((candidate) => !isSafeSwapCandidate(candidate))
        .toList(growable: false);
    final bestClaim = inert.isEmpty && evaluation.canClaimBestNetReturnAt(now);
    final selected = state.selectedCandidate;
    final all = [...ranked, ...unranked, ...inert];
    return Semantics(
      container: true,
      label: unifiedSwapText(
        context,
        'quote.optionCount',
        '{count} current route options',
        namedArgs: {'count': '${evaluation.candidates.length}'},
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (selected == null)
            _InlineOptions(
              candidates: all,
              destination: destination,
              bestClaim: bestClaim,
              onSelected: onCandidateSelected,
              onRevalidate: onRevalidate,
            )
          else
            _SelectedQuoteStrip(
              candidate: selected,
              destination: destination,
              bestNetReturn: bestClaim && selected.rank == 1,
              onCompare: () => _showOptions(
                context,
                candidates: all,
                destination: destination,
                selectedId: selected.candidateId,
                bestClaim: bestClaim,
                onSelected: onCandidateSelected,
              ),
              onRevalidate: onRevalidate,
            ),
          if (selected case final selected?) ...[
            if (selected.riskWarnings.highPriceImpact) ...[
              const SizedBox(height: 10),
              UnifiedSwapNotice(
                title: unifiedSwapText(
                  context,
                  'quote.highImpactTitle',
                  'High price impact',
                ),
                message: unifiedSwapText(
                  context,
                  'quote.highImpactBody',
                  'Price impact is 3% or greater. Check minimum received '
                      'carefully.',
                ),
                tone: UnifiedSwapNoticeTone.warning,
                icon: Icons.trending_down_rounded,
              ),
            ],
            if (selected.riskWarnings.lowLiquidity) ...[
              const SizedBox(height: 10),
              UnifiedSwapNotice(
                title: unifiedSwapText(
                  context,
                  'quote.lowLiquidityTitle',
                  'Low liquidity',
                ),
                message: unifiedSwapText(
                  context,
                  'quote.lowLiquidityBody',
                  'Available liquidity may widen the received amount.',
                ),
                tone: UnifiedSwapNoticeTone.warning,
                icon: Icons.water_drop_outlined,
              ),
            ],
          ],
          if (reviewFailure case final failure?) ...[
            const SizedBox(height: 10),
            UnifiedSwapNotice(
              key: const Key('swap-review-failure'),
              title: unifiedSwapText(
                context,
                'review.prepareFailedTitle',
                'Review could not be prepared',
              ),
              message: failure,
              tone: UnifiedSwapNoticeTone.danger,
              icon: Icons.error_outline_rounded,
              liveRegion: true,
            ),
          ],
          const SizedBox(height: 14),
          FilledButton.icon(
            key: const Key('swap-review-route'),
            style: UnifiedSwapDesign.primaryButtonStyle(context),
            onPressed:
                selected != null &&
                    isSafeSwapCandidate(selected) &&
                    !selected.isExpiredAt(now) &&
                    canReview &&
                    !reviewInFlight
                ? () => onReviewRequested(selected)
                : null,
            icon: reviewInFlight
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.fact_check_outlined),
            label: Text(
              reviewInFlight
                  ? unifiedSwapText(
                      context,
                      'review.preparing',
                      'Preparing Review',
                    )
                  : unifiedSwapText(context, 'review.cta', 'Review swap'),
            ),
          ),
          if (!canReview) ...[
            const SizedBox(height: 8),
            Text(
              reviewUnavailableMessage,
              key: const Key('swap-review-unavailable'),
              textAlign: TextAlign.center,
              style: UnifiedSwapDesign.typography(context).bodySmall,
            ),
          ],
        ],
      ),
    );
  }
}

class _QuoteStateCard extends StatelessWidget {
  const _QuoteStateCard({
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.onAction,
    required this.tone,
    super.key,
  });

  final String title;
  final String message;
  final String actionLabel;
  final VoidCallback onAction;
  final UnifiedSwapNoticeTone tone;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        UnifiedSwapNotice(
          title: title,
          message: message,
          tone: tone,
          liveRegion: true,
          icon: tone == UnifiedSwapNoticeTone.warning
              ? Icons.schedule_rounded
              : Icons.cloud_off_outlined,
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          style: UnifiedSwapDesign.secondaryButtonStyle(context),
          onPressed: onAction,
          icon: const Icon(Icons.refresh_rounded),
          label: Text(actionLabel),
        ),
      ],
    );
  }
}

class _InlineOptions extends StatelessWidget {
  const _InlineOptions({
    required this.candidates,
    required this.destination,
    required this.bestClaim,
    required this.onSelected,
    required this.onRevalidate,
  });

  final List<UnifiedSwapQuoteCandidate> candidates;
  final UnifiedSwapAssetIdentity destination;
  final bool bestClaim;
  final ValueChanged<String> onSelected;
  final VoidCallback onRevalidate;

  @override
  Widget build(BuildContext context) {
    final maxHeight = (candidates.length * 132.0).clamp(132.0, 440.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                unifiedSwapText(
                  context,
                  'quote.chooseOption',
                  'Choose a route option',
                ),
                style: UnifiedSwapDesign.typography(context).cardTitle,
              ),
            ),
            IconButton(
              key: const Key('swap-revalidate'),
              onPressed: onRevalidate,
              tooltip: unifiedSwapText(
                context,
                'quote.revalidateTooltip',
                'Check routes again',
              ),
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: maxHeight,
          child: ListView.separated(
            itemCount: candidates.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final candidate = candidates[index];
              return _CandidateCard(
                candidate: candidate,
                destination: destination,
                selected: false,
                bestNetReturn: bestClaim && candidate.rank == 1,
                onSelected: onSelected,
              );
            },
          ),
        ),
      ],
    );
  }
}

class _SelectedQuoteStrip extends StatelessWidget {
  const _SelectedQuoteStrip({
    required this.candidate,
    required this.destination,
    required this.bestNetReturn,
    required this.onCompare,
    required this.onRevalidate,
  });

  final UnifiedSwapQuoteCandidate candidate;
  final UnifiedSwapAssetIdentity destination;
  final bool bestNetReturn;
  final VoidCallback onCompare;
  final VoidCallback onRevalidate;

  @override
  Widget build(BuildContext context) {
    final colors = UnifiedSwapDesign.colors(context);
    return UnifiedSwapSurface(
      backgroundColor: colors.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final compact =
                  constraints.maxWidth < 420 ||
                  MediaQuery.textScalerOf(context).scale(16) >= 24;
              final facts = [
                _QuoteFact(
                  label: unifiedSwapText(
                    context,
                    'quote.minimumReceived',
                    'Minimum received',
                  ),
                  value: swapAmount(candidate.minimumReceive, destination),
                ),
                _QuoteFact(
                  label: unifiedSwapText(
                    context,
                    'quote.totalCost',
                    'Total cost',
                  ),
                  value: _feeSummary(context, candidate),
                ),
                _QuoteFact(
                  label: unifiedSwapText(
                    context,
                    'quote.estimatedTime',
                    'Estimated time',
                  ),
                  value: unifiedSwapText(
                    context,
                    'quote.timeInReview',
                    'Shown in Review',
                  ),
                ),
              ];
              if (compact) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var index = 0; index < facts.length; index++) ...[
                      facts[index],
                      if (index < facts.length - 1)
                        Divider(height: 18, color: colors.border),
                    ],
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [for (final fact in facts) Expanded(child: fact)],
              );
            },
          ),
          const SizedBox(height: 10),
          Divider(height: 1, color: colors.border),
          const SizedBox(height: 8),
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 4,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  UnifiedSwapBadge(
                    label: bestNetReturn
                        ? unifiedSwapText(
                            context,
                            'quote.bestNetReturn',
                            'Best net return',
                          )
                        : _topology(context, candidate.topology),
                    tone: bestNetReturn
                        ? UnifiedSwapNoticeTone.brand
                        : UnifiedSwapNoticeTone.neutral,
                  ),
                  if (bestNetReturn) ...[
                    const SizedBox(height: 4),
                    Text(
                      unifiedSwapText(
                        context,
                        'quote.rankingNote',
                        'Among currently available, comparable options',
                      ),
                      style: UnifiedSwapDesign.typography(context).bodySmall,
                    ),
                  ],
                ],
              ),
              Wrap(
                spacing: 4,
                children: [
                  IconButton(
                    key: const Key('swap-revalidate'),
                    onPressed: onRevalidate,
                    tooltip: unifiedSwapText(
                      context,
                      'quote.revalidateTooltip',
                      'Check routes again',
                    ),
                    icon: const Icon(Icons.refresh_rounded),
                  ),
                  TextButton(
                    key: const Key('swap-compare-options'),
                    onPressed: onCompare,
                    child: Text(
                      unifiedSwapText(
                        context,
                        'quote.compareOptions',
                        'Compare options',
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _QuoteFact extends StatelessWidget {
  const _QuoteFact({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(end: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: UnifiedSwapDesign.typography(context).bodySmall),
          const SizedBox(height: 4),
          Text(
            value,
            style: UnifiedSwapDesign.typography(context).tabularAmountCompact,
          ),
        ],
      ),
    );
  }
}

class _CandidateCard extends StatelessWidget {
  const _CandidateCard({
    required this.candidate,
    required this.destination,
    required this.selected,
    required this.bestNetReturn,
    required this.onSelected,
  });

  final UnifiedSwapQuoteCandidate candidate;
  final UnifiedSwapAssetIdentity destination;
  final bool selected;
  final bool bestNetReturn;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final inert = !isSafeSwapCandidate(candidate);
    final colors = UnifiedSwapDesign.colors(context);
    return Semantics(
      container: true,
      button: !inert,
      enabled: !inert,
      selected: selected,
      label:
          '${_topology(context, candidate.topology)}, '
          '${unifiedSwapText(context, 'quote.expected', 'expected')} '
          '${swapAmount(candidate.expectedReceive, destination)}, '
          '${unifiedSwapText(context, 'quote.minimum', 'minimum')} '
          '${swapAmount(candidate.minimumReceive, destination)}',
      child: Material(
        key: Key('swap-candidate-${candidate.candidateId}'),
        color: selected ? colors.selected : colors.surface,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: inert ? null : () => onSelected(candidate.candidateId),
          borderRadius: BorderRadius.circular(14),
          child: Container(
            constraints: const BoxConstraints(minHeight: 116),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              border: Border.all(
                color: selected ? colors.brand : colors.controlBorder,
              ),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        _topology(context, candidate.topology),
                        style: UnifiedSwapDesign.typography(context).labelLarge,
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (bestNetReturn)
                      UnifiedSwapBadge(
                        label: unifiedSwapText(
                          context,
                          'quote.bestNetReturn',
                          'Best net return',
                        ),
                        tone: UnifiedSwapNoticeTone.brand,
                      )
                    else if (!candidate.rankable && !inert)
                      UnifiedSwapBadge(
                        label: unifiedSwapText(
                          context,
                          'quote.notRanked',
                          'Not ranked',
                        ),
                      )
                    else if (inert)
                      UnifiedSwapBadge(
                        label: unifiedSwapText(
                          context,
                          'quote.unavailableType',
                          'Unavailable route type',
                        ),
                        tone: UnifiedSwapNoticeTone.danger,
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  '${unifiedSwapText(context, 'quote.expectedLabel', 'Expected')}: '
                  '${swapAmount(candidate.expectedReceive, destination)}',
                  key: Key('swap-candidate-expected-${candidate.candidateId}'),
                  style: UnifiedSwapDesign.typography(
                    context,
                  ).tabularAmountCompact,
                ),
                const SizedBox(height: 3),
                Text(
                  '${unifiedSwapText(context, 'quote.minimumLabel', 'Minimum')}: '
                  '${swapAmount(candidate.minimumReceive, destination)}',
                  style: UnifiedSwapDesign.typography(context).bodySmall,
                ),
                const SizedBox(height: 3),
                Text(
                  _feeSummary(context, candidate),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: UnifiedSwapDesign.typography(context).bodySmall,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

Future<void> _showOptions(
  BuildContext context, {
  required List<UnifiedSwapQuoteCandidate> candidates,
  required UnifiedSwapAssetIdentity destination,
  required String selectedId,
  required bool bestClaim,
  required ValueChanged<String> onSelected,
}) async {
  final selected = await showUnifiedSwapPicker<String>(
    context: context,
    title: unifiedSwapText(context, 'quote.optionsTitle', 'Route options'),
    subtitle: unifiedSwapText(
      context,
      'quote.optionsSubtitle',
      'Compare the current executable outcomes and protections.',
    ),
    builder: (sheetContext) => ListView.separated(
      shrinkWrap: true,
      itemCount: candidates.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final candidate = candidates[index];
        return _CandidateCard(
          candidate: candidate,
          destination: destination,
          selected: candidate.candidateId == selectedId,
          bestNetReturn: bestClaim && candidate.rank == 1,
          onSelected: (id) => Navigator.pop(sheetContext, id),
        );
      },
    ),
  );
  if (selected != null) onSelected(selected);
}

Future<UnifiedSwapAssetIdentity?> _showAssetSelection(
  BuildContext context, {
  required bool source,
  required List<UnifiedSwapAssetOption> options,
  required UnifiedSwapAssetIdentity selected,
}) {
  UnifiedSwapNetworkIdentity? network;
  return showUnifiedSwapPicker<UnifiedSwapAssetIdentity>(
    context: context,
    title: unifiedSwapText(context, 'picker.chooseAssetTitle', 'Choose asset'),
    subtitle: unifiedSwapText(
      context,
      source ? 'picker.sourceAssetSubtitle' : 'picker.destinationAssetSubtitle',
      source
          ? 'Only activated software-key sources with an executable route are '
                'shown.'
          : 'Choose an exact KDF-supported asset and network identity.',
    ),
    builder: (sheetContext) => StatefulBuilder(
      builder: (context, setSheetState) {
        final networks = <UnifiedSwapNetworkIdentity>[];
        for (final option in options) {
          if (!networks.contains(option.network)) networks.add(option.network);
        }
        final visible = network == null
            ? options
            : options
                  .where((option) => option.network == network)
                  .toList(growable: false);
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              unifiedSwapText(context, 'picker.networks', 'Networks'),
              style: UnifiedSwapDesign.typography(context).labelLarge,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _NetworkFilterButton(
                  label: unifiedSwapText(
                    context,
                    'picker.allNetworks',
                    'All networks',
                  ),
                  selected: network == null,
                  onPressed: () => setSheetState(() => network = null),
                ),
                for (final item in networks)
                  _NetworkFilterButton(
                    key: Key(
                      'swap-${source ? 'source' : 'destination'}-network-'
                      '${item.chainFamily.name}-${item.chainId}',
                    ),
                    label: _networkLabel(context, item, options),
                    selected: network == item,
                    onPressed: () => setSheetState(() => network = item),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            if (visible.isEmpty)
              UnifiedSwapNotice(
                title: unifiedSwapText(
                  context,
                  'picker.noAssetsTitle',
                  'No eligible assets',
                ),
                message: unifiedSwapText(
                  context,
                  'picker.noAssetsBody',
                  'The current wallet and route capabilities do not expose an '
                      'exact match.',
                ),
                tone: UnifiedSwapNoticeTone.warning,
                icon: Icons.search_off_rounded,
              )
            else
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: visible.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final option = visible[index];
                    final isSelected = option.identity.sameIdentity(selected);
                    return _AssetSelectionRow(
                      key: Key(
                        'swap-${source ? 'source' : 'destination'}-option-'
                        '${option.identity.ticker}-${option.identity.chainId}-'
                        '$index',
                      ),
                      option: option,
                      selected: isSelected,
                      onPressed: isSelected
                          ? () => Navigator.pop(sheetContext)
                          : () => Navigator.pop(sheetContext, option.identity),
                    );
                  },
                ),
              ),
          ],
        );
      },
    ),
  );
}

Future<UnifiedSwapSourceSelection?> _showSourceAddressSelection(
  BuildContext context, {
  required UnifiedSwapAssetIdentity asset,
  required List<UnifiedSwapSourceAddressOption> options,
  required UnifiedSwapSourceSelection selected,
}) {
  return showUnifiedSwapPicker<UnifiedSwapSourceSelection>(
    context: context,
    title: unifiedSwapText(
      context,
      'picker.chooseSourceTitle',
      'Choose source address',
    ),
    subtitle: unifiedSwapText(
      context,
      'picker.chooseSourceSubtitle',
      'Fresh balance at each wallet-owned address on {network}.',
      namedArgs: {'network': unifiedSwapNetworkLabel(context, asset)},
    ),
    builder: (sheetContext) => options.isEmpty
        ? UnifiedSwapNotice(
            title: unifiedSwapText(
              context,
              'picker.noAddressesTitle',
              'No eligible source addresses',
            ),
            message: unifiedSwapText(
              context,
              'picker.noAddressesBody',
              'The wallet could not verify a fresh executable address and '
                  'balance.',
            ),
            tone: UnifiedSwapNoticeTone.warning,
            icon: Icons.account_balance_wallet_outlined,
          )
        : ListView.separated(
            shrinkWrap: true,
            itemCount: options.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final option = options[index];
              final isSelected = option.selection == selected;
              return _SourceAddressSelectionRow(
                key: Key('swap-source-address-option-$index'),
                asset: asset,
                option: option,
                selected: isSelected,
                onPressed: isSelected
                    ? () => Navigator.pop(sheetContext)
                    : () => Navigator.pop(sheetContext, option.selection),
              );
            },
          ),
  );
}

class _NetworkFilterButton extends StatelessWidget {
  const _NetworkFilterButton({
    required this.label,
    required this.selected,
    required this.onPressed,
    super.key,
  });

  final String label;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 48),
      child: FilterChip(
        selected: selected,
        onSelected: (_) => onPressed(),
        label: Text(label),
      ),
    );
  }
}

class _AssetSelectionRow extends StatelessWidget {
  const _AssetSelectionRow({
    required this.option,
    required this.selected,
    required this.onPressed,
    super.key,
  });

  final UnifiedSwapAssetOption option;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = UnifiedSwapDesign.colors(context);
    final asset = option.identity;
    return Semantics(
      selected: selected,
      button: true,
      label: unifiedSwapText(
        context,
        'picker.assetSemantics',
        '{asset} on {network}, {identity}',
        namedArgs: {
          'asset': asset.ticker,
          'network': unifiedSwapNetworkLabel(context, asset),
          'identity': swapAssetLabel(context, asset),
        },
      ),
      child: UnifiedSwapSurface(
        padding: EdgeInsets.zero,
        borderColor: selected ? colors.brand : colors.controlBorder,
        backgroundColor: selected ? colors.selected : colors.surface,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(16),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 72),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                children: [
                  UnifiedSwapAssetAvatar(asset: asset, size: 42),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          asset.ticker,
                          style: UnifiedSwapDesign.typography(
                            context,
                          ).labelLarge,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          unifiedSwapText(
                            context,
                            'picker.assetDetails',
                            '{network} · {kind} · {decimals} decimals',
                            namedArgs: {
                              'network': unifiedSwapNetworkLabel(
                                context,
                                asset,
                              ),
                              'kind': swapAssetKind(context, asset.kind),
                              'decimals': '${asset.decimals}',
                            },
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: UnifiedSwapDesign.typography(
                            context,
                          ).bodySmall,
                        ),
                        if (asset.contractAddress case final contract?)
                          Text(
                            unifiedSwapShortIdentity(contract),
                            style: UnifiedSwapDesign.typography(
                              context,
                            ).bodySmall,
                          ),
                      ],
                    ),
                  ),
                  if (selected)
                    Icon(Icons.check_circle_rounded, color: colors.brand),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SourceAddressSelectionRow extends StatelessWidget {
  const _SourceAddressSelectionRow({
    required this.asset,
    required this.option,
    required this.selected,
    required this.onPressed,
    super.key,
  });

  final UnifiedSwapAssetIdentity asset;
  final UnifiedSwapSourceAddressOption option;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = UnifiedSwapDesign.colors(context);
    return Semantics(
      selected: selected,
      button: true,
      label: unifiedSwapText(
        context,
        'picker.sourceAddressSemantics',
        '{label}, {address}, {balance}',
        namedArgs: {
          'label':
              option.label ??
              unifiedSwapText(
                context,
                'picker.walletAddress',
                'Wallet address',
              ),
          'address': unifiedSwapShortIdentity(option.address),
          'balance': swapAmount(option.balance, asset),
        },
      ),
      child: UnifiedSwapSurface(
        padding: EdgeInsets.zero,
        borderColor: selected ? colors.brand : colors.controlBorder,
        backgroundColor: selected ? colors.selected : colors.surface,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(16),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 72),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                children: [
                  const Icon(Icons.account_balance_wallet_outlined),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          option.label ??
                              unifiedSwapText(
                                context,
                                'picker.walletAddress',
                                'Wallet address',
                              ),
                          style: UnifiedSwapDesign.typography(
                            context,
                          ).labelLarge,
                        ),
                        Text(
                          unifiedSwapShortIdentity(option.address),
                          style: UnifiedSwapDesign.typography(
                            context,
                          ).bodySmall,
                        ),
                        Text(
                          swapAmount(option.balance, asset),
                          style: UnifiedSwapDesign.typography(
                            context,
                          ).tabularAmountCompact,
                        ),
                      ],
                    ),
                  ),
                  if (option.isActive && !selected)
                    UnifiedSwapBadge(
                      label: unifiedSwapText(
                        context,
                        'picker.activeAddress',
                        'Active',
                      ),
                      tone: UnifiedSwapNoticeTone.brand,
                    ),
                  if (selected)
                    Icon(Icons.check_circle_rounded, color: colors.brand),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

String _networkLabel(
  BuildContext context,
  UnifiedSwapNetworkIdentity network,
  List<UnifiedSwapAssetOption> options,
) {
  final asset = options
      .map((option) => option.identity)
      .firstWhere(network.matches);
  return unifiedSwapNetworkLabel(context, asset);
}

Future<void> _showAssetIdentity(
  BuildContext context,
  UnifiedSwapAssetIdentity asset,
) {
  return showUnifiedSwapPicker<void>(
    context: context,
    title: unifiedSwapText(
      context,
      'picker.assetIdentityTitle',
      'Asset and network',
    ),
    subtitle: unifiedSwapText(
      context,
      'picker.assetIdentitySubtitle',
      'Exact activated identity selected by your wallet.',
    ),
    builder: (context) => SingleChildScrollView(
      child: UnifiedSwapSurface(
        borderColor: UnifiedSwapDesign.colors(context).brand,
        backgroundColor: UnifiedSwapDesign.colors(context).selected,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            UnifiedSwapAssetAvatar(asset: asset, size: 44),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${asset.ticker} · ${unifiedSwapNetworkLabel(context, asset)}',
                    style: UnifiedSwapDesign.typography(context).cardTitle,
                  ),
                  const SizedBox(height: 6),
                  Text(swapAssetLabel(context, asset)),
                  const SizedBox(height: 6),
                  SelectableText(swapAssetContract(context, asset)),
                ],
              ),
            ),
            const Icon(Icons.check_circle_rounded),
          ],
        ),
      ),
    ),
  );
}

Future<void> _showSourceIdentity(
  BuildContext context,
  UnifiedSwapIntent intent,
) {
  return showUnifiedSwapPicker<void>(
    context: context,
    title: unifiedSwapText(
      context,
      'picker.sourceIdentityTitle',
      'Source address',
    ),
    subtitle: unifiedSwapText(
      context,
      'picker.sourceIdentitySubtitle',
      'The exact wallet-owned source is resolved before Review.',
    ),
    builder: (context) => SingleChildScrollView(
      child: UnifiedSwapNotice(
        title: _sourceSelection(context, intent),
        message: unifiedSwapText(
          context,
          'picker.sourceBody',
          'The full resolved address and exact network are shown in Review '
              'before any consent.',
        ),
        tone: UnifiedSwapNoticeTone.brand,
        icon: Icons.account_balance_wallet_outlined,
      ),
    ),
  );
}

String _failureMessage(
  BuildContext context,
  UnifiedSwapQuoteFailure? failure,
) => switch (failure) {
  UnifiedSwapQuoteFailure.invalidIntent => unifiedSwapText(
    context,
    'quote.invalidIntent',
    'The wallet rejected this exact amount, source, or destination recipient. '
        'Check the shown network details and try again.',
  ),
  UnifiedSwapQuoteFailure.capabilityUnavailable => unifiedSwapText(
    context,
    'quote.capabilityUnavailable',
    'This exact asset, funded source, or destination is not currently '
        'executable.',
  ),
  UnifiedSwapQuoteFailure.quoteExpired => unifiedSwapText(
    context,
    'quote.expiredBeforeSelection',
    'The quote expired before it could be selected.',
  ),
  UnifiedSwapQuoteFailure.suspiciousToken => unifiedSwapText(
    context,
    'quote.suspiciousToken',
    'A suspicious token is blocked for your protection.',
  ),
  UnifiedSwapQuoteFailure.unknownTokenConfirmationRequired => unifiedSwapText(
    context,
    'quote.unknownToken',
    'Confirm the full token contract and network in the wallet first.',
  ),
  UnifiedSwapQuoteFailure.networkUnavailable => unifiedSwapText(
    context,
    'quote.networkUnavailable',
    'The wallet could not safely reach the route service.',
  ),
  UnifiedSwapQuoteFailure.serviceUnavailable => unifiedSwapText(
    context,
    'quote.serviceUnavailable',
    'Executable routes are temporarily unavailable.',
  ),
  UnifiedSwapQuoteFailure.unknown || null => unifiedSwapText(
    context,
    'quote.unknownFailure',
    'The wallet could not verify an executable route. No funds moved.',
  ),
};

String _sourceSelection(BuildContext context, UnifiedSwapIntent intent) =>
    switch (intent.sourceSelection) {
      UnifiedSwapActiveSourceSelection() => unifiedSwapText(
        context,
        'sourceSelection.active',
        'Active software-key address',
      ),
      UnifiedSwapHdAddressSourceSelection(
        :final accountId,
        :final chain,
        :final addressId,
      ) =>
        unifiedSwapText(
          context,
          'sourceSelection.hdAddress',
          'HD account {accountId}, {chain} address {addressId}',
          namedArgs: {
            'accountId': '$accountId',
            'chain': chain.name,
            'addressId': '$addressId',
          },
        ),
      UnifiedSwapHdPathSourceSelection(:final derivationPath) =>
        unifiedSwapText(
          context,
          'sourceSelection.hdPath',
          'HD path {path}',
          namedArgs: {'path': derivationPath},
        ),
      UnifiedSwapUnknownSourceSelection() => unifiedSwapText(
        context,
        'sourceSelection.unsupported',
        'Unsupported source selector',
      ),
    };

String _sourceSelectionShort(BuildContext context, UnifiedSwapIntent intent) =>
    switch (intent.sourceSelection) {
      UnifiedSwapActiveSourceSelection() => unifiedSwapText(
        context,
        'sourceSelection.activeShort',
        'active wallet address',
      ),
      UnifiedSwapHdAddressSourceSelection(:final addressId) => unifiedSwapText(
        context,
        'sourceSelection.hdAddressShort',
        'wallet address {number}',
        namedArgs: {'number': '${addressId + 1}'},
      ),
      UnifiedSwapHdPathSourceSelection() => unifiedSwapText(
        context,
        'sourceSelection.selectedShort',
        'selected wallet address',
      ),
      UnifiedSwapUnknownSourceSelection() => unifiedSwapText(
        context,
        'sourceSelection.unsupportedShort',
        'unsupported source',
      ),
    };

String _topology(BuildContext context, UnifiedSwapTopology topology) =>
    switch (topology) {
      UnifiedSwapTopology.atomic => unifiedSwapText(
        context,
        'topology.atomic',
        'Direct exchange',
      ),
      UnifiedSwapTopology.external => unifiedSwapText(
        context,
        'topology.external',
        'Unified route',
      ),
      UnifiedSwapTopology.externalToAtomic => unifiedSwapText(
        context,
        'topology.externalToAtomic',
        'Move, then exchange',
      ),
      UnifiedSwapTopology.atomicToExternal => unifiedSwapText(
        context,
        'topology.atomicToExternal',
        'Exchange, then move',
      ),
      UnifiedSwapTopology.externalToAtomicToExternal => unifiedSwapText(
        context,
        'topology.multiStage',
        'Multi-step route',
      ),
      UnifiedSwapTopology.unknown => unifiedSwapText(
        context,
        'topology.unknown',
        'Unknown route type',
      ),
    };

String _feeSummary(BuildContext context, UnifiedSwapQuoteCandidate candidate) {
  if (candidate.fees.isEmpty) {
    return unifiedSwapText(context, 'quote.noSeparateFees', 'No separate fees');
  }
  if (candidate.fees.length == 1) {
    final fee = candidate.fees.single;
    return '${swapFeeKind(context, fee.kind)} '
        '${swapAmount(fee.amount, fee.asset)}';
  }
  return unifiedSwapText(
    context,
    'quote.feeComponents',
    '{count} fee components',
    namedArgs: {'count': '${candidate.fees.length}'},
  );
}

String _editableAmount(String smallestUnits, int decimals) {
  if (decimals <= 0) return smallestUnits;
  final padded = smallestUnits.padLeft(decimals + 1, '0');
  final split = padded.length - decimals;
  final whole = padded.substring(0, split);
  final fraction = padded.substring(split).replaceFirst(RegExp(r'0+$'), '');
  return fraction.isEmpty ? whole : '$whole.$fraction';
}

String? _smallestUnits(String input, int decimals) {
  final value = input.trim();
  if (!RegExp(r'^(?:0|[1-9][0-9]*)(?:\.[0-9]+)?$').hasMatch(value)) {
    return null;
  }
  final parts = value.split('.');
  final fraction = parts.length == 1 ? '' : parts[1];
  if (fraction.length > decimals) return null;
  final padded = fraction.padRight(decimals, '0');
  final combined = '${parts[0]}$padded';
  return BigInt.parse(combined).toString();
}
