import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:web_dex/features/unified_swap/application/unified_swap_bloc.dart';
import 'package:web_dex/features/unified_swap/domain/unified_swap_capability_policy.dart';
import 'package:web_dex/features/unified_swap/domain/unified_swap_model_limits.dart';
import 'package:web_dex/features/unified_swap/domain/unified_swap_product_policy.dart';
import 'package:web_dex/features/unified_swap/domain/unified_swap_quote_models.dart';
import 'package:web_dex/features/unified_swap/domain/unified_swap_selection_models.dart';
import 'package:web_dex/features/unified_swap/presentation/swap/swap_widgets.dart';
import 'package:web_dex/features/unified_swap/presentation/unified_swap_design.dart';
import 'package:web_dex/features/unified_swap/presentation/unified_swap_sensitive_dialog.dart';

typedef UnifiedSwapMaximumAmountResolver =
    Future<String?> Function(UnifiedSwapIntent intent);

typedef UnifiedSwapRecipientValidator =
    Future<bool> Function({
      required UnifiedSwapAssetIdentity asset,
      required String address,
    });

typedef UnifiedSwapIntentCommitter =
    Future<bool> Function(UnifiedSwapIntent intent);

const _walletInteractionDeadline = Duration(seconds: 15);
const _maximumRecipientLength =
    UnifiedSwapAssetIdentity.maximumIdentifierLength;

enum _SelectionFailureTarget {
  sourceAsset,
  destinationAsset,
  sourceAddress,
  direction,
}

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
    this.recipientValidator,
    this.selectionGateway,
    this.intentEditable = true,
    this.reviewInFlight = false,
    this.reviewFailure,
    this.reviewFocusNode,
    this.onIntentEditStarted,
    this.onPickerPresentationChanged,
    this.initialAmountDraft,
    this.now,
    super.key,
  });

  final UnifiedSwapState state;
  final UnifiedSwapIntentCommitter onIntentChanged;
  final ValueChanged<String> onCandidateSelected;
  final VoidCallback onRevalidate;
  final ValueChanged<UnifiedSwapQuoteCandidate> onReviewRequested;
  final bool canReview;
  final String reviewUnavailableMessage;
  final UnifiedSwapMaximumAmountResolver? maximumAmountResolver;
  final UnifiedSwapRecipientValidator? recipientValidator;
  final UnifiedSwapSelectionGateway? selectionGateway;
  final bool intentEditable;
  final bool reviewInFlight;
  final String? reviewFailure;
  final FocusNode? reviewFocusNode;
  final VoidCallback? onIntentEditStarted;
  final ValueChanged<bool>? onPickerPresentationChanged;
  final String? initialAmountDraft;
  final DateTime Function()? now;

  @override
  State<UnifiedSwapEntryView> createState() => _UnifiedSwapEntryViewState();
}

class _UnifiedSwapEntryViewState extends State<UnifiedSwapEntryView> {
  late final TextEditingController _amountController;
  late final TextEditingController _recipientController;
  final FocusNode _amountFocus = FocusNode();
  final FocusNode _recipientFocus = FocusNode();
  String? _amountError;
  String? _recipientError;
  String? _sourceAssetError;
  String? _destinationAssetError;
  String? _sourceAddressError;
  String? _directionError;
  bool _draftDirty = false;
  late bool _initialDraftPending;
  bool _maxInFlight = false;
  bool _selectionInFlight = false;
  bool _pickerPresented = false;
  bool _reportedIntentSurfaceActive = false;
  UnifiedSwapSourceAddressOption? _sourceAddressOption;
  int _sourceAddressLookup = 0;
  int _revisionSeed = 0;
  int _draftGeneration = 0;

  @override
  void initState() {
    super.initState();
    final intent = widget.state.intent;
    _initialDraftPending = widget.initialAmountDraft?.trim().isNotEmpty == true;
    _revisionSeed = intent?.revision ?? 0;
    _amountController = TextEditingController(
      text: widget.initialAmountDraft?.trim().isNotEmpty == true
          ? widget.initialAmountDraft!.trim()
          : intent == null
          ? ''
          : _editableAmount(intent.sourceAmount, intent.source.decimals),
    );
    _draftDirty = intent != null && _initialDraftPending;
    _recipientController = TextEditingController(text: intent?.recipient ?? '');
    unawaited(_refreshSourceAddressOption());
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
      final sourceChanged =
          oldIntent == null || !oldIntent.source.sameIdentity(intent.source);
      if (!_initialDraftPending &&
          (sourceChanged || !_draftDirty) &&
          !_amountFocus.hasFocus &&
          _amountController.text != sourceAmount) {
        _amountController.text = sourceAmount;
      }
      if (!_recipientFocus.hasFocus &&
          _recipientController.text != intent.recipient) {
        _recipientController.text = intent.recipient;
      }
      if (_initialDraftPending) {
        _draftDirty = true;
      } else if (sourceChanged ||
          _smallestUnits(_amountController.text, intent.source.decimals) ==
              intent.sourceAmount) {
        _draftDirty = false;
      }
      _sourceAssetError = null;
      _destinationAssetError = null;
      _sourceAddressError = null;
      _directionError = null;
      if (oldIntent == null ||
          !oldIntent.source.sameIdentity(intent.source) ||
          oldIntent.sourceSelection != intent.sourceSelection) {
        unawaited(_refreshSourceAddressOption());
      }
    }
  }

  @override
  void dispose() {
    _sourceAddressLookup++;
    _amountController.dispose();
    _recipientController.dispose();
    _amountFocus.dispose();
    _recipientFocus.dispose();
    super.dispose();
  }

  void _draftChanged(String _) {
    if (!widget.intentEditable) return;
    widget.onIntentEditStarted?.call();
    _draftGeneration++;
    final focusContext = _amountFocus.context;
    if (focusContext != null) UnifiedSwapPickerHost.dismiss(focusContext);
    setState(() {
      _draftDirty = true;
      _amountError = null;
      _recipientError = null;
      _sourceAssetError = null;
      _destinationAssetError = null;
      _sourceAddressError = null;
      _directionError = null;
    });
  }

  void _handlePickerPresentationChanged(bool visible) {
    _pickerPresented = visible;
    _notifyIntentSurfaceActive();
  }

  void _notifyIntentSurfaceActive() {
    final active = _pickerPresented || _selectionInFlight || _maxInFlight;
    if (active == _reportedIntentSurfaceActive) return;
    _reportedIntentSurfaceActive = active;
    widget.onPickerPresentationChanged?.call(active);
  }

  Future<void> _refreshSourceAddressOption() async {
    final gateway = widget.selectionGateway;
    final intent = widget.state.intent;
    final lookup = ++_sourceAddressLookup;
    if (gateway == null || intent == null) {
      if (mounted) setState(() => _sourceAddressOption = null);
      return;
    }
    try {
      final options = await gateway
          .sourceAddressOptions(intent.source)
          .timeout(_walletInteractionDeadline);
      if (!mounted || lookup != _sourceAddressLookup) return;
      final matches = options
          .where((option) => option.selection == intent.sourceSelection)
          .toList(growable: false);
      setState(() {
        _sourceAddressOption = matches.length == 1 ? matches.single : null;
      });
    } on Object {
      if (mounted && lookup == _sourceAddressLookup) {
        setState(() => _sourceAddressOption = null);
      }
    }
  }

  Future<bool> _submitDraft() async {
    final current = widget.state.intent;
    if (current == null || !widget.intentEditable) return false;
    final amount = _smallestUnits(
      _amountController.text,
      current.source.decimals,
    );
    final recipient = _recipientController.text.trim();
    if (amount == null || BigInt.parse(amount) == BigInt.zero) {
      setState(() {
        _draftDirty = true;
        _amountError = unifiedSwapText(
          context,
          'entry.amountError',
          'Enter an amount greater than zero with no more than {decimals} '
              'decimal places.',
          namedArgs: {'decimals': '${current.source.decimals}'},
        );
      });
      return false;
    }
    if (recipient.isEmpty || recipient.length > _maximumRecipientLength) {
      setState(() {
        _draftDirty = true;
        _recipientError = recipient.isEmpty
            ? unifiedSwapText(
                context,
                'entry.recipientRequired',
                'A recipient is required.',
              )
            : unifiedSwapText(
                context,
                'entry.recipientTooLong',
                'The receiving address is too long.',
              );
      });
      return false;
    }
    _revisionSeed++;
    late final UnifiedSwapIntent next;
    try {
      next = UnifiedSwapIntent(
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
      );
    } on ArgumentError {
      if (mounted) {
        setState(() {
          _recipientError = unifiedSwapText(
            context,
            'entry.recipientInvalid',
            'The receiving address is invalid.',
          );
          _draftDirty = true;
        });
      }
      return false;
    }
    final committed = await widget.onIntentChanged(next);
    if (mounted && committed) {
      setState(() {
        _initialDraftPending = false;
        _draftDirty = false;
      });
    }
    return committed;
  }

  Future<void> _useMaximum() async {
    final resolver = widget.maximumAmountResolver;
    final intent = widget.state.intent;
    if (resolver == null ||
        intent == null ||
        _maxInFlight ||
        !widget.intentEditable) {
      return;
    }
    final draftGeneration = _draftGeneration;
    setState(() => _maxInFlight = true);
    _notifyIntentSurfaceActive();
    try {
      final maximum = await resolver(
        intent,
      ).timeout(_walletInteractionDeadline);
      if (!mounted) return;
      final current = widget.state.intent;
      if (current == null ||
          draftGeneration != _draftGeneration ||
          current.revision != intent.revision ||
          !current.source.sameIdentity(intent.source) ||
          current.sourceSelection != intent.sourceSelection) {
        return;
      }
      if (maximum == null ||
          maximum.length > UnifiedSwapModelLimits.amountDigits ||
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
      _draftGeneration++;
      _initialDraftPending = false;
      setState(() {
        _draftDirty = true;
        _amountError = null;
      });
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
      if (mounted) {
        setState(() => _maxInFlight = false);
        _notifyIntentSurfaceActive();
      }
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
    setState(() {
      _selectionInFlight = true;
      if (source) {
        _sourceAssetError = null;
      } else {
        _destinationAssetError = null;
      }
    });
    _notifyIntentSurfaceActive();
    try {
      final selected = await _showAssetSelection(
        context,
        source: source,
        options: gateway
            .selectionInventory()
            .timeout(_walletInteractionDeadline)
            .then((inventory) {
              if (inventory == null) {
                throw StateError('Selection inventory is unavailable');
              }
              return source
                  ? inventory.sources
                  : inventory.destinationsFor(current.source);
            }),
        selected: source ? current.source : current.destination,
      );
      if (!mounted ||
          selected == null ||
          widget.state.intent?.revision != current.revision) {
        return;
      }
      var next = source
          ? await gateway
                .selectSourceAsset(current, selected)
                .timeout(_walletInteractionDeadline)
          : await gateway
                .selectDestinationAsset(current, selected)
                .timeout(_walletInteractionDeadline);
      if (!mounted ||
          next == null ||
          next.revision <= current.revision ||
          widget.state.intent?.revision != current.revision) {
        if (mounted &&
            widget.state.intent?.revision == current.revision &&
            next == null) {
          _showSelectionFailure(
            source
                ? _SelectionFailureTarget.sourceAsset
                : _SelectionFailureTarget.destinationAsset,
          );
        }
        return;
      }
      next = await _confirmUnknownTokenSelection(next);
      if (!mounted || next == null) return;
      await widget.onIntentChanged(next);
    } on Object {
      if (mounted) {
        _showSelectionFailure(
          source
              ? _SelectionFailureTarget.sourceAsset
              : _SelectionFailureTarget.destinationAsset,
        );
      }
    } finally {
      if (mounted) {
        setState(() => _selectionInFlight = false);
        _notifyIntentSurfaceActive();
      }
    }
  }

  Future<UnifiedSwapIntent?> _confirmUnknownTokenSelection(
    UnifiedSwapIntent intent,
  ) async {
    if (intent.tokenFailure !=
        UnifiedSwapQuoteFailure.unknownTokenConfirmationRequired) {
      return intent;
    }
    final unknown = <UnifiedSwapAssetIdentity>[
      if (intent.sourceTokenTrust == UnifiedSwapTokenTrust.unknown)
        intent.source,
      if (intent.destinationTokenTrust == UnifiedSwapTokenTrust.unknown)
        intent.destination,
    ];
    if (unknown.isEmpty) return null;
    final confirmed = await showUnifiedSwapSensitiveConfirmation(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          unifiedSwapText(
            dialogContext,
            'picker.unknownTokenTitle',
            'Confirm token identity',
          ),
        ),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                UnifiedSwapNotice(
                  title: unifiedSwapText(
                    dialogContext,
                    'picker.unknownTokenWarningTitle',
                    'Unknown custom token',
                  ),
                  message: unifiedSwapText(
                    dialogContext,
                    'picker.unknownTokenWarningBody',
                    'Verify every full contract and network. A ticker or icon '
                        'is not proof of token identity.',
                  ),
                  tone: UnifiedSwapNoticeTone.warning,
                  icon: Icons.gpp_maybe_outlined,
                ),
                for (final asset in unknown) ...[
                  const SizedBox(height: 12),
                  UnifiedSwapSurface(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${asset.ticker} · '
                          '${unifiedSwapNetworkLabel(dialogContext, asset)}',
                          style: UnifiedSwapDesign.typography(
                            dialogContext,
                          ).labelLarge,
                        ),
                        const SizedBox(height: 6),
                        SelectableText(swapAssetContract(dialogContext, asset)),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(
              unifiedSwapText(dialogContext, 'common.goBack', 'Go back'),
            ),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(
              unifiedSwapText(
                dialogContext,
                'picker.confirmToken',
                'Confirm token',
              ),
            ),
          ),
        ],
      ),
    );
    return confirmed ? intent.copyWith(unknownTokenConfirmed: true) : null;
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
    setState(() {
      _selectionInFlight = true;
      _sourceAddressError = null;
    });
    _notifyIntentSurfaceActive();
    try {
      final selected = await _showSourceAddressSelection(
        context,
        asset: current.source,
        options: gateway
            .sourceAddressOptions(current.source)
            .timeout(_walletInteractionDeadline),
        selected: current.sourceSelection,
      );
      if (!mounted ||
          selected == null ||
          widget.state.intent?.revision != current.revision) {
        return;
      }
      final next = await gateway
          .selectSourceAddress(current, selected)
          .timeout(_walletInteractionDeadline);
      if (!mounted ||
          next == null ||
          next.revision <= current.revision ||
          widget.state.intent?.revision != current.revision) {
        if (mounted &&
            widget.state.intent?.revision == current.revision &&
            next == null) {
          _showSelectionFailure(_SelectionFailureTarget.sourceAddress);
        }
        return;
      }
      await widget.onIntentChanged(next);
    } on Object {
      if (mounted) {
        _showSelectionFailure(_SelectionFailureTarget.sourceAddress);
      }
    } finally {
      if (mounted) {
        setState(() => _selectionInFlight = false);
        _notifyIntentSurfaceActive();
      }
    }
  }

  Future<void> _reverseDirection() async {
    final gateway = widget.selectionGateway;
    final current = widget.state.intent;
    if (gateway == null ||
        current == null ||
        _selectionInFlight ||
        !widget.intentEditable) {
      return;
    }
    setState(() {
      _selectionInFlight = true;
      _amountError = null;
      _recipientError = null;
      _directionError = null;
    });
    _notifyIntentSurfaceActive();
    try {
      final inventory = await gateway.selectionInventory().timeout(
        _walletInteractionDeadline,
      );
      if (!mounted || widget.state.intent?.revision != current.revision) return;
      if (inventory == null ||
          !inventory.supportsPair(current.destination, current.source)) {
        setState(() {
          _directionError = unifiedSwapText(
            context,
            'entry.reverseUnavailable',
            'The reverse route is not available for these exact networks.',
          );
        });
        return;
      }
      final withSource = await gateway
          .selectSourceAsset(current, current.destination)
          .timeout(_walletInteractionDeadline);
      if (!mounted ||
          withSource == null ||
          widget.state.intent?.revision != current.revision) {
        if (mounted && widget.state.intent?.revision == current.revision) {
          _showSelectionFailure(_SelectionFailureTarget.direction);
        }
        return;
      }
      final reversed = await gateway
          .selectDestinationAsset(withSource, current.source)
          .timeout(_walletInteractionDeadline);
      if (!mounted ||
          reversed == null ||
          widget.state.intent?.revision != current.revision) {
        if (mounted && widget.state.intent?.revision == current.revision) {
          _showSelectionFailure(_SelectionFailureTarget.direction);
        }
        return;
      }
      _revisionSeed = [
        _revisionSeed,
        current.revision,
        withSource.revision,
        reversed.revision,
      ].reduce((left, right) => left > right ? left : right);
      final next = reversed.copyWith(
        revision: ++_revisionSeed,
        sourceAmount: '0',
        externalRecipientConfirmed: false,
      );
      _amountController.clear();
      _draftGeneration++;
      _initialDraftPending = false;
      _draftDirty = false;
      final committed = await widget.onIntentChanged(next);
      if (!committed && mounted) {
        _amountController.text = _editableAmount(
          current.sourceAmount,
          current.source.decimals,
        );
      }
    } on Object {
      if (mounted) _showSelectionFailure(_SelectionFailureTarget.direction);
    } finally {
      if (mounted) {
        setState(() => _selectionInFlight = false);
        _notifyIntentSurfaceActive();
      }
    }
  }

  Future<void> _chooseRecipient() async {
    final current = widget.state.intent;
    if (current == null || !widget.intentEditable || _selectionInFlight) return;
    setState(() {
      _selectionInFlight = true;
      _recipientError = null;
    });
    _notifyIntentSurfaceActive();
    var committed = false;
    try {
      final selected = await _showRecipientSelection(
        context,
        asset: current.destination,
        controller: _recipientController,
        focusNode: _recipientFocus,
        validator: widget.recipientValidator,
      );
      if (!mounted || selected == null || selected == current.recipient) return;
      _recipientController.text = selected;
      _draftGeneration++;
      setState(() => _draftDirty = true);
      committed = await _submitDraft();
    } finally {
      if (mounted) {
        if (!committed) {
          final canonical = widget.state.intent;
          _recipientController.text = canonical?.recipient ?? current.recipient;
        }
        setState(() {
          _selectionInFlight = false;
          if (!committed) _draftDirty = false;
        });
        _notifyIntentSurfaceActive();
      }
    }
  }

  void _showSelectionFailure(_SelectionFailureTarget target) {
    setState(() {
      final message = unifiedSwapText(
        context,
        'picker.selectionUnavailable',
        'That exact wallet selection is no longer available. Your swap stayed '
            'unchanged.',
      );
      switch (target) {
        case _SelectionFailureTarget.sourceAsset:
          _sourceAssetError = message;
          break;
        case _SelectionFailureTarget.destinationAsset:
          _destinationAssetError = message;
          break;
        case _SelectionFailureTarget.sourceAddress:
          _sourceAddressError = message;
          break;
        case _SelectionFailureTarget.direction:
          _directionError = message;
          break;
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
      child: UnifiedSwapPickerHost(
        onPresentationChanged: _handlePickerPresentationChanged,
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
                  selected: _draftDirty ? null : selected,
                  sourceAddressOption: _sourceAddressOption,
                  amountController: _amountController,
                  amountFocus: _amountFocus,
                  amountError: _amountError,
                  recipientError: _recipientError,
                  sourceAssetError: _sourceAssetError,
                  destinationAssetError: _destinationAssetError,
                  sourceAddressError: _sourceAddressError,
                  directionError: _directionError,
                  maxInFlight: _maxInFlight,
                  selectionInFlight: _selectionInFlight || _draftDirty,
                  intentEditable: widget.intentEditable,
                  canUseMaximum: widget.maximumAmountResolver != null,
                  onDraftChanged: _draftChanged,
                  onAmountSubmitted: () {
                    unawaited(_submitDraft());
                  },
                  onMaximum: _useMaximum,
                  onSourceAsset: () => _chooseAsset(source: true),
                  onDestinationAsset: () => _chooseAsset(source: false),
                  onSourceAddress: _chooseSourceAddress,
                  onRecipient: _chooseRecipient,
                  onReverse: _reverseDirection,
                ),
                // Existing automation reads exact activated identities. Keep the
                // data in the widget tree without adding prototype-visible copy.
                _ExactIdentityAnchors(intent: intent),
                const SizedBox(height: 14),
                AnimatedSwitcher(
                  duration: UnifiedSwapDesign.motion(context).resolve(
                    context,
                    UnifiedSwapDesign.motion(context).standard,
                  ),
                  child: _draftDirty
                      ? _DraftRouteCheckCard(
                          key: const Key('swap-draft-progress'),
                          onCheck: () => unawaited(_submitDraft()),
                        )
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
                          reviewFocusNode: widget.reviewFocusNode,
                          now: widget.now?.call() ?? DateTime.now().toUtc(),
                          destination: intent.destination,
                        ),
                ),
              ],
            ),
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
    required this.sourceAddressOption,
    required this.amountController,
    required this.amountFocus,
    required this.amountError,
    required this.recipientError,
    required this.sourceAssetError,
    required this.destinationAssetError,
    required this.sourceAddressError,
    required this.directionError,
    required this.maxInFlight,
    required this.selectionInFlight,
    required this.intentEditable,
    required this.canUseMaximum,
    required this.onDraftChanged,
    required this.onAmountSubmitted,
    required this.onMaximum,
    required this.onSourceAsset,
    required this.onDestinationAsset,
    required this.onSourceAddress,
    required this.onRecipient,
    required this.onReverse,
  });

  final UnifiedSwapIntent intent;
  final UnifiedSwapQuoteCandidate? selected;
  final UnifiedSwapSourceAddressOption? sourceAddressOption;
  final TextEditingController amountController;
  final FocusNode amountFocus;
  final String? amountError;
  final String? recipientError;
  final String? sourceAssetError;
  final String? destinationAssetError;
  final String? sourceAddressError;
  final String? directionError;
  final bool maxInFlight;
  final bool selectionInFlight;
  final bool intentEditable;
  final bool canUseMaximum;
  final ValueChanged<String> onDraftChanged;
  final VoidCallback onAmountSubmitted;
  final VoidCallback onMaximum;
  final VoidCallback onSourceAsset;
  final VoidCallback onDestinationAsset;
  final VoidCallback onSourceAddress;
  final VoidCallback onRecipient;
  final VoidCallback onReverse;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _AmountCard(
          key: const Key('swap-source-identity'),
          label: unifiedSwapText(context, 'entry.youPay', 'You pay'),
          asset: intent.source,
          amountField: Semantics(
            label: amountError == null
                ? unifiedSwapText(context, 'entry.amountLabel', 'Swap amount')
                : unifiedSwapText(
                    context,
                    'entry.amountErrorSemantics',
                    'Swap amount error: {error}',
                    namedArgs: {'error': amountError!},
                  ),
            child: TextField(
              key: const Key('swap-amount-input'),
              controller: amountController,
              focusNode: amountFocus,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: [
                LengthLimitingTextInputFormatter(
                  UnifiedSwapModelLimits.amountDigits + 1,
                ),
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
              ],
              textInputAction: TextInputAction.done,
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
          ),
          fiatText: _sourceValuationSummary(context, selected),
          balanceText: sourceAddressOption == null
              ? unifiedSwapText(
                  context,
                  'entry.balanceUnavailable',
                  'Balance unavailable',
                )
              : unifiedSwapText(
                  context,
                  'entry.balanceValue',
                  'Balance {amount}',
                  namedArgs: {
                    'amount': swapAmount(
                      sourceAddressOption!.balance,
                      intent.source,
                    ),
                  },
                ),
          footer: Row(
            children: [
              Expanded(
                child: Semantics(
                  label: sourceAddressError == null
                      ? unifiedSwapText(
                          context,
                          'entry.sourceAddressLabel',
                          'Source address: {address}',
                          namedArgs: {
                            'address':
                                sourceAddressOption?.address ??
                                _sourceSelectionShort(context, intent),
                          },
                        )
                      : unifiedSwapText(
                          context,
                          'entry.sourceAddressErrorSemantics',
                          'Source address error: {error}',
                          namedArgs: {'error': sourceAddressError!},
                        ),
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
                      '${_sourceAddressShort(context, intent, sourceAddressOption)}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
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
          assetError: sourceAssetError,
          footerError: sourceAddressError,
        ),
        Column(
          children: [
            SizedBox(
              height: 32,
              child: Center(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: UnifiedSwapDesign.colors(context).surfaceHighest,
                    border: Border.all(
                      color: UnifiedSwapDesign.colors(context).canvas,
                      width: 6,
                    ),
                    shape: BoxShape.circle,
                  ),
                  child: Semantics(
                    label: directionError == null
                        ? unifiedSwapText(
                            context,
                            'entry.reverseDirection',
                            'Reverse swap direction',
                          )
                        : unifiedSwapText(
                            context,
                            'entry.directionErrorSemantics',
                            'Swap direction error: {error}',
                            namedArgs: {'error': directionError!},
                          ),
                    child: IconButton(
                      key: const Key('swap-reverse-direction'),
                      onPressed: !intentEditable || selectionInFlight
                          ? null
                          : onReverse,
                      tooltip: unifiedSwapText(
                        context,
                        'entry.reverseDirection',
                        'Reverse swap direction',
                      ),
                      icon: const Icon(Icons.swap_vert_rounded, size: 22),
                    ),
                  ),
                ),
              ),
            ),
            if (directionError case final error?)
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 4, 18, 8),
                child: _SwapControlError(error: error),
              ),
          ],
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
          fiatText: _valuationSummary(context, selected),
          footer: Semantics(
            label: recipientError == null
                ? unifiedSwapText(
                    context,
                    'entry.recipientLabel',
                    'Recipient: {recipient}',
                    namedArgs: {'recipient': intent.recipient},
                  )
                : unifiedSwapText(
                    context,
                    'entry.recipientErrorSemantics',
                    'Recipient error: {error}',
                    namedArgs: {'error': recipientError!},
                  ),
            child: TextButton(
              key: const Key('swap-recipient-selector'),
              onPressed: !intentEditable || selectionInFlight
                  ? null
                  : onRecipient,
              style: TextButton.styleFrom(
                minimumSize: const Size(48, 48),
                alignment: AlignmentDirectional.centerStart,
                padding: EdgeInsets.zero,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${unifiedSwapText(context, 'entry.to', 'To')} '
                      '${unifiedSwapShortIdentity(intent.recipient)}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    unifiedSwapText(context, 'entry.change', 'Change'),
                    style: UnifiedSwapDesign.typography(context).labelLarge
                        .copyWith(
                          color: UnifiedSwapDesign.colors(context).brandHover,
                        ),
                  ),
                ],
              ),
            ),
          ),
          assetSelectorKey: const Key('swap-destination-asset-selector'),
          onAssetPressed: !intentEditable || selectionInFlight
              ? null
              : onDestinationAsset,
          error: recipientError,
          assetError: destinationAssetError,
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
    this.balanceText,
    this.error,
    this.assetError,
    this.footerError,
    super.key,
  });

  final String label;
  final UnifiedSwapAssetIdentity asset;
  final Widget amountField;
  final String fiatText;
  final Widget footer;
  final Key assetSelectorKey;
  final VoidCallback? onAssetPressed;
  final String? balanceText;
  final String? error;
  final String? assetError;
  final String? footerError;

  @override
  Widget build(BuildContext context) {
    final colors = UnifiedSwapDesign.colors(context);
    final type = UnifiedSwapDesign.typography(context);
    final network = unifiedSwapNetworkLabel(context, asset);
    final hasError = error != null || assetError != null || footerError != null;
    return UnifiedSwapSurface(
      padding: const EdgeInsets.all(18),
      borderColor: hasError ? colors.danger : colors.controlBorder,
      radius: 20,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text(label, style: type.labelLarge)),
              const SizedBox(width: 8),
              if (balanceText case final balance?)
                Expanded(
                  child: Text(
                    balance,
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
                semanticLabel: assetError == null
                    ? null
                    : unifiedSwapText(
                        context,
                        'entry.assetErrorSemantics',
                        'Asset selection error: {error}',
                        namedArgs: {'error': assetError!},
                      ),
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
          if (assetError case final assetError?) ...[
            const SizedBox(height: 8),
            _SwapControlError(error: assetError),
          ],
          const SizedBox(height: 16),
          Divider(height: 1, color: colors.border),
          const SizedBox(height: 4),
          footer,
          if (footerError case final footerError?) ...[
            const SizedBox(height: 8),
            _SwapControlError(error: footerError),
          ],
          if (error case final error?) ...[
            const SizedBox(height: 8),
            _SwapControlError(error: error),
          ],
        ],
      ),
    );
  }
}

class _SwapControlError extends StatelessWidget {
  const _SwapControlError({required this.error});

  final String error;

  @override
  Widget build(BuildContext context) {
    final colors = UnifiedSwapDesign.colors(context);
    return Semantics(
      liveRegion: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline_rounded, size: 18, color: colors.danger),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              error,
              style: UnifiedSwapDesign.typography(
                context,
              ).bodySmall.copyWith(color: colors.danger),
            ),
          ),
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

class _DraftRouteCheckCard extends StatelessWidget {
  const _DraftRouteCheckCard({required this.onCheck, super.key});

  final VoidCallback onCheck;

  @override
  Widget build(BuildContext context) {
    return UnifiedSwapSurface(
      semanticLabel: unifiedSwapText(
        context,
        'quote.draftSemantics',
        'Amount changed. Check routes to update the quote.',
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            unifiedSwapText(
              context,
              'quote.draftTitle',
              'Amount not checked yet',
            ),
            style: UnifiedSwapDesign.typography(context).labelLarge,
          ),
          const SizedBox(height: 8),
          Text(
            unifiedSwapText(
              context,
              'quote.draftBody',
              'The visible amount is a draft. Existing route options are '
                  'hidden until you check this amount.',
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            key: const Key('swap-check-routes'),
            onPressed: onCheck,
            icon: const Icon(Icons.route_rounded),
            label: Text(
              unifiedSwapText(context, 'quote.checkRoutes', 'Check routes'),
            ),
          ),
        ],
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
      child: Row(
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
    required this.reviewFocusNode,
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
  final FocusNode? reviewFocusNode;
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
            focusNode: reviewFocusNode,
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
    final safeCount = candidates.where(isSafeSwapCandidate).length;
    return UnifiedSwapSurface(
      backgroundColor: UnifiedSwapDesign.colors(context).surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            unifiedSwapText(
              context,
              'quote.chooseOption',
              'Choose a route option',
            ),
            style: UnifiedSwapDesign.typography(context).cardTitle,
          ),
          const SizedBox(height: 4),
          Text(
            unifiedSwapText(
              context,
              'quote.chooseOptionBody',
              '{count} current options cannot be compared automatically. '
                  'Review their outcomes and choose one to continue.',
              namedArgs: {'count': '$safeCount'},
            ),
            style: UnifiedSwapDesign.typography(context).bodySmall,
          ),
          const SizedBox(height: 10),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 4,
            runSpacing: 4,
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
                onPressed: safeCount == 0
                    ? null
                    : () => _showOptions(
                        context,
                        candidates: candidates,
                        destination: destination,
                        selectedId: null,
                        bestClaim: bestClaim,
                        onSelected: onSelected,
                      ),
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
                  value: _candidateDuration(context, candidate),
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
    this.expired = false,
    this.rovingFocus = false,
    this.focusNode,
  });

  final UnifiedSwapQuoteCandidate candidate;
  final UnifiedSwapAssetIdentity destination;
  final bool selected;
  final bool bestNetReturn;
  final ValueChanged<String> onSelected;
  final bool expired;
  final bool rovingFocus;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    final inert = expired || !isSafeSwapCandidate(candidate);
    final colors = UnifiedSwapDesign.colors(context);
    return Semantics(
      container: true,
      button: !inert,
      enabled: !inert,
      selected: selected,
      inMutuallyExclusiveGroup: true,
      label:
          '${_topology(context, candidate.topology)}, '
          '${unifiedSwapText(context, 'quote.expected', 'expected')} '
          '${swapAmount(candidate.expectedReceive, destination)}, '
          '${unifiedSwapText(context, 'quote.minimum', 'minimum')} '
          '${swapAmount(candidate.minimumReceive, destination)}',
      child: Material(
        key: ValueKey<int>(
          Object.hash('swap-candidate', candidate.candidateId),
        ),
        color: selected ? colors.selected : colors.surface,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: inert ? null : () => onSelected(candidate.candidateId),
          canRequestFocus: !inert && (!rovingFocus || selected),
          focusNode: focusNode,
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
                    else if (expired)
                      UnifiedSwapBadge(
                        label: unifiedSwapText(
                          context,
                          'quote.expired',
                          'Expired',
                        ),
                        tone: UnifiedSwapNoticeTone.warning,
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
                  key: ValueKey<int>(
                    Object.hash(
                      'swap-candidate-expected',
                      candidate.candidateId,
                    ),
                  ),
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
                const SizedBox(height: 6),
                Wrap(
                  spacing: 12,
                  runSpacing: 4,
                  children: [
                    _CandidateMeta(
                      label: unifiedSwapText(context, 'quote.etaShort', 'ETA'),
                      value: _candidateDuration(context, candidate),
                    ),
                    _CandidateMeta(
                      label: unifiedSwapText(context, 'quote.stages', 'Stages'),
                      value: candidate.stageCount == null
                          ? '—'
                          : '${candidate.stageCount}',
                    ),
                    _CandidateMeta(
                      label: unifiedSwapText(
                        context,
                        'quote.permission',
                        'Permission',
                      ),
                      value: unifiedSwapText(
                        context,
                        'quote.permissionInReview',
                        'Checked in Review',
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CandidateMeta extends StatelessWidget {
  const _CandidateMeta({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final type = UnifiedSwapDesign.typography(context);
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(text: '$label ', style: type.bodySmall),
          TextSpan(
            text: value,
            style: type.bodySmall.copyWith(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

Future<void> _showOptions(
  BuildContext context, {
  required List<UnifiedSwapQuoteCandidate> candidates,
  required UnifiedSwapAssetIdentity destination,
  required String? selectedId,
  required bool bestClaim,
  required ValueChanged<String> onSelected,
}) async {
  var pendingId = selectedId;
  if (pendingId == null) {
    for (final candidate in candidates) {
      if (isSafeSwapCandidate(candidate)) {
        pendingId = candidate.candidateId;
        break;
      }
    }
  }
  var showRemaining = candidates.length <= 4;
  var rovingId = pendingId;
  var focusRequest = 0;
  var pickerOpen = true;
  StateSetter? refreshSheet;
  final scrollController = ScrollController();
  final focusNodes = {
    for (final candidate in candidates)
      candidate.candidateId: FocusNode(debugLabel: 'Unified Swap route option'),
  };
  final expiryTimer = Timer.periodic(const Duration(seconds: 1), (_) {
    if (pickerOpen) refreshSheet?.call(() {});
  });
  try {
    final selected = await showUnifiedSwapPicker<String>(
      context: context,
      title: unifiedSwapText(context, 'quote.optionsTitle', 'Route options'),
      subtitle: unifiedSwapText(
        context,
        'quote.optionsSubtitle',
        'Compare the current executable outcomes and protections.',
      ),
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) {
          refreshSheet = setSheetState;
          final current = DateTime.now().toUtc();
          final initial = _initialOptionCandidates(candidates, pendingId);
          final visible = showRemaining ? candidates : initial;
          final selectable = visible
              .where(
                (candidate) =>
                    isSafeSwapCandidate(candidate) &&
                    !candidate.isExpiredAt(current),
              )
              .toList(growable: false);

          void moveFocusTo(String nextId) {
            final targetIndex = visible.indexWhere(
              (candidate) => candidate.candidateId == nextId,
            );
            if (targetIndex < 0) return;
            rovingId = nextId;
            final request = ++focusRequest;
            unawaited(() async {
              final node = focusNodes[nextId]!;
              final revealed = await _revealLazyListFocusTarget(
                scrollController: scrollController,
                targetFocusNode: node,
                targetIndex: targetIndex,
                itemCount: visible.length,
                isCurrent: () =>
                    pickerOpen && request == focusRequest && rovingId == nextId,
              );
              if (!revealed ||
                  !pickerOpen ||
                  request != focusRequest ||
                  rovingId != nextId) {
                return;
              }
              setSheetState(() => pendingId = nextId);
              await WidgetsBinding.instance.endOfFrame;
              if (pickerOpen &&
                  request == focusRequest &&
                  rovingId == nextId &&
                  node.canRequestFocus) {
                node.requestFocus();
              }
            }());
          }

          KeyEventResult moveSelection(LogicalKeyboardKey key) {
            if (selectable.isEmpty) return KeyEventResult.ignored;
            var index = selectable.indexWhere(
              (candidate) => candidate.candidateId == rovingId,
            );
            if (key == LogicalKeyboardKey.home) {
              index = 0;
            } else if (key == LogicalKeyboardKey.end) {
              index = selectable.length - 1;
            } else if (key == LogicalKeyboardKey.arrowDown ||
                key == LogicalKeyboardKey.arrowRight) {
              index = (index + 1).clamp(0, selectable.length - 1);
            } else if (key == LogicalKeyboardKey.arrowUp ||
                key == LogicalKeyboardKey.arrowLeft) {
              index = (index <= 0 ? 0 : index - 1);
            } else {
              return KeyEventResult.ignored;
            }
            final nextId = selectable[index].candidateId;
            moveFocusTo(nextId);
            return KeyEventResult.handled;
          }

          return SizedBox(
            height: (MediaQuery.sizeOf(context).height * .68).clamp(
              360.0,
              660.0,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: Focus(
                    onKeyEvent: (_, event) => event is KeyDownEvent
                        ? moveSelection(event.logicalKey)
                        : KeyEventResult.ignored,
                    child: Semantics(
                      container: true,
                      label: unifiedSwapText(
                        context,
                        'quote.optionsGroup',
                        'Swap options',
                      ),
                      child: ListView.separated(
                        controller: scrollController,
                        itemCount: visible.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final candidate = visible[index];
                          return _CandidateCard(
                            candidate: candidate,
                            destination: destination,
                            selected: candidate.candidateId == pendingId,
                            bestNetReturn: bestClaim && candidate.rank == 1,
                            expired: candidate.isExpiredAt(current),
                            rovingFocus: true,
                            focusNode: focusNodes[candidate.candidateId],
                            onSelected: (id) {
                              rovingId = id;
                              focusRequest++;
                              setSheetState(() => pendingId = id);
                              WidgetsBinding.instance.addPostFrameCallback(
                                (_) => focusNodes[id]?.requestFocus(),
                              );
                            },
                          );
                        },
                      ),
                    ),
                  ),
                ),
                if (selectable.isEmpty) ...[
                  const SizedBox(height: 10),
                  UnifiedSwapNotice(
                    title: unifiedSwapText(
                      context,
                      'quote.optionsExpiredTitle',
                      'Route options expired',
                    ),
                    message: unifiedSwapText(
                      context,
                      'quote.optionsExpiredBody',
                      'Close this comparison and check routes again for '
                          'current terms.',
                    ),
                    tone: UnifiedSwapNoticeTone.warning,
                    icon: Icons.timer_off_outlined,
                  ),
                ],
                if (!showRemaining) ...[
                  const SizedBox(height: 10),
                  OutlinedButton(
                    key: const Key('swap-show-remaining-options'),
                    style: UnifiedSwapDesign.secondaryButtonStyle(context),
                    onPressed: () => setSheetState(() => showRemaining = true),
                    child: Text(
                      unifiedSwapText(
                        context,
                        'quote.showRemainingOptions',
                        'Show remaining {count}',
                        namedArgs: {
                          'count': '${candidates.length - initial.length}',
                        },
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                FilledButton(
                  key: const Key('swap-use-option'),
                  style: UnifiedSwapDesign.primaryButtonStyle(context),
                  onPressed:
                      selectable.any(
                        (candidate) => candidate.candidateId == pendingId,
                      )
                      ? () {
                          final selectedNow = _optionCandidateById(
                            candidates,
                            pendingId,
                          );
                          if (selectedNow == null ||
                              !isSafeSwapCandidate(selectedNow) ||
                              selectedNow.isExpiredAt(DateTime.now().toUtc())) {
                            setSheetState(() {});
                            return;
                          }
                          completeUnifiedSwapPicker(
                            sheetContext,
                            selectedNow.candidateId,
                          );
                        }
                      : null,
                  child: Text(
                    unifiedSwapText(
                      context,
                      'quote.useOption',
                      'Use this option',
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
    final selectedCandidate = _optionCandidateById(candidates, selected);
    if (selectedCandidate != null &&
        isSafeSwapCandidate(selectedCandidate) &&
        !selectedCandidate.isExpiredAt(DateTime.now().toUtc())) {
      onSelected(selectedCandidate.candidateId);
    }
  } finally {
    pickerOpen = false;
    expiryTimer.cancel();
    focusRequest++;
    scrollController.dispose();
    for (final node in focusNodes.values) {
      node.dispose();
    }
  }
}

UnifiedSwapQuoteCandidate? _optionCandidateById(
  List<UnifiedSwapQuoteCandidate> candidates,
  String? candidateId,
) {
  if (candidateId == null) return null;
  for (final candidate in candidates) {
    if (candidate.candidateId == candidateId) return candidate;
  }
  return null;
}

List<UnifiedSwapQuoteCandidate> _initialOptionCandidates(
  List<UnifiedSwapQuoteCandidate> candidates,
  String? selectedId,
) {
  if (candidates.length <= 4) return candidates;
  final selected = candidates.indexWhere(
    (candidate) => candidate.candidateId == selectedId,
  );
  if (selected < 0 || selected < 4) return candidates.take(4).toList();
  return [
    candidates[selected],
    ...candidates
        .where((candidate) => candidate.candidateId != selectedId)
        .take(3),
  ];
}

Future<bool> _revealLazyListFocusTarget({
  required ScrollController scrollController,
  required FocusNode targetFocusNode,
  required int targetIndex,
  required int itemCount,
  required bool Function() isCurrent,
}) async {
  if (targetIndex < 0 || targetIndex >= itemCount || !isCurrent()) {
    return false;
  }

  // Lazy lists do not attach focus nodes for offscreen rows. Move close to the
  // indexed target first, then use ensureVisible once the row is mounted. The
  // repeated estimate also handles variable-height rows and a max extent that
  // becomes more accurate as distant children are laid out.
  const maximumMountPasses = 18;
  for (var pass = 0; pass < maximumMountPasses; pass++) {
    await WidgetsBinding.instance.endOfFrame;
    if (!isCurrent()) return false;

    final targetContext = targetFocusNode.context;
    if (targetContext != null && targetContext.mounted) {
      await Scrollable.ensureVisible(
        targetContext,
        alignment: .5,
        duration: Duration.zero,
      );
      return isCurrent();
    }
    if (!scrollController.hasClients) continue;

    final position = scrollController.position;
    if (!position.hasContentDimensions) continue;
    final maximum = position.maxScrollExtent;
    final viewport = position.viewportDimension;
    late final double estimatedOffset;
    if (targetIndex == 0 || maximum <= 0) {
      estimatedOffset = 0;
    } else if (targetIndex == itemCount - 1) {
      estimatedOffset = maximum;
    } else {
      final averageExtent = (maximum + viewport) / itemCount;
      final centered = averageExtent * (targetIndex + .5) - (viewport / 2);
      if (pass == 0) {
        estimatedOffset = centered;
      } else {
        final window = (pass + 1) ~/ 2;
        final direction = pass.isOdd ? -1.0 : 1.0;
        estimatedOffset = centered + direction * viewport * .45 * window;
      }
    }
    final boundedOffset = estimatedOffset.clamp(0.0, maximum).toDouble();
    scrollController.jumpTo(boundedOffset);
  }
  return false;
}

Future<UnifiedSwapAssetIdentity?> _showAssetSelection(
  BuildContext context, {
  required bool source,
  required Future<List<UnifiedSwapAssetOption>> options,
  required UnifiedSwapAssetIdentity selected,
}) {
  UnifiedSwapNetworkIdentity? network;
  var query = '';
  return showUnifiedSwapPicker<UnifiedSwapAssetIdentity>(
    context: context,
    title: unifiedSwapText(context, 'picker.chooseAssetTitle', 'Choose asset'),
    subtitle: unifiedSwapText(
      context,
      source ? 'picker.sourceAssetSubtitle' : 'picker.destinationAssetSubtitle',
      source
          ? 'Only activated software-key sources with an executable route are '
                'shown.'
          : 'Choose an exact supported asset and network identity.',
    ),
    builder: (sheetContext) => FutureBuilder<List<UnifiedSwapAssetOption>>(
      future: options,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return _PickerLoading(
            label: unifiedSwapText(
              context,
              'picker.loadingAssets',
              'Checking eligible assets and balances',
            ),
          );
        }
        if (snapshot.hasError || snapshot.data == null) {
          return _PickerFailure(
            title: unifiedSwapText(
              context,
              'picker.assetsUnavailableTitle',
              'Assets are temporarily unavailable',
            ),
            message: unifiedSwapText(
              context,
              'picker.assetsUnavailableBody',
              'The wallet could not verify current asset eligibility. Your '
                  'swap stayed unchanged.',
            ),
            onClose: () => completeUnifiedSwapPicker(sheetContext),
          );
        }
        final resolvedOptions = snapshot.data!;
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final networks = <UnifiedSwapNetworkIdentity>[];
            for (final option in resolvedOptions) {
              if (!networks.contains(option.network)) {
                networks.add(option.network);
              }
            }
            final normalizedQuery = query.trim().toLowerCase();
            final visible = resolvedOptions
                .where((option) {
                  if (network != null && option.network != network) {
                    return false;
                  }
                  if (normalizedQuery.isEmpty) return true;
                  final identity = option.identity;
                  return identity.ticker.toLowerCase().contains(
                        normalizedQuery,
                      ) ||
                      unifiedSwapNetworkLabel(
                        context,
                        identity,
                      ).toLowerCase().contains(normalizedQuery) ||
                      (identity.contractAddress?.toLowerCase().contains(
                            normalizedQuery,
                          ) ??
                          false);
                })
                .toList(growable: false);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  key: Key(
                    'swap-${source ? 'source' : 'destination'}-asset-search',
                  ),
                  onChanged: (value) => setSheetState(() => query = value),
                  decoration: InputDecoration(
                    hintText: unifiedSwapText(
                      context,
                      'picker.searchAssets',
                      'Search assets or networks',
                    ),
                    prefixIcon: const Icon(Icons.search_rounded),
                  ),
                ),
                const SizedBox(height: 12),
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
                        key: ValueKey<int>(
                          Object.hash(
                            'swap-network-filter',
                            source,
                            item.chainFamily,
                            item.chainId,
                          ),
                        ),
                        label: _networkLabel(context, item, resolvedOptions),
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
                      'The current wallet and route capabilities do not expose '
                          'an exact match.',
                    ),
                    tone: UnifiedSwapNoticeTone.warning,
                    icon: Icons.search_off_rounded,
                  )
                else
                  Expanded(
                    child: _RovingPickerList<UnifiedSwapAssetOption>(
                      items: visible,
                      identity: (option) => _selectionAssetKey(option.identity),
                      preferredIdentity: _selectionAssetKey(selected),
                      itemBuilder: (context, option, focusNode, focusTarget) {
                        final isSelected = option.identity.sameIdentity(
                          selected,
                        );
                        return _AssetSelectionRow(
                          key: ValueKey<int>(
                            Object.hash(
                              'swap-asset-option',
                              source,
                              _selectionAssetKey(option.identity),
                            ),
                          ),
                          option: option,
                          selected: isSelected,
                          focusNode: focusNode,
                          focusTarget: focusTarget,
                          onPressed: isSelected
                              ? () => completeUnifiedSwapPicker(sheetContext)
                              : () => completeUnifiedSwapPicker(
                                  sheetContext,
                                  option.identity,
                                ),
                        );
                      },
                    ),
                  ),
              ],
            );
          },
        );
      },
    ),
  );
}

Future<UnifiedSwapSourceSelection?> _showSourceAddressSelection(
  BuildContext context, {
  required UnifiedSwapAssetIdentity asset,
  required Future<List<UnifiedSwapSourceAddressOption>> options,
  required UnifiedSwapSourceSelection selected,
}) {
  var query = '';
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
    builder: (sheetContext) =>
        FutureBuilder<List<UnifiedSwapSourceAddressOption>>(
          future: options,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return _PickerLoading(
                label: unifiedSwapText(
                  context,
                  'picker.loadingAddresses',
                  'Checking current address balances',
                ),
              );
            }
            if (snapshot.hasError || snapshot.data == null) {
              return _PickerFailure(
                title: unifiedSwapText(
                  context,
                  'picker.addressesUnavailableTitle',
                  'Addresses are temporarily unavailable',
                ),
                message: unifiedSwapText(
                  context,
                  'picker.addressesUnavailableBody',
                  'The wallet could not verify current balances and address '
                      'eligibility. Your swap stayed unchanged.',
                ),
                onClose: () => completeUnifiedSwapPicker(sheetContext),
              );
            }
            final resolvedOptions = snapshot.data!;
            return StatefulBuilder(
              builder: (context, setSheetState) {
                final normalizedQuery = query.trim().toLowerCase();
                final visible = resolvedOptions
                    .where((option) {
                      if (normalizedQuery.isEmpty) return true;
                      return option.address.toLowerCase().contains(
                            normalizedQuery,
                          ) ||
                          (option.label?.toLowerCase().contains(
                                normalizedQuery,
                              ) ??
                              false);
                    })
                    .toList(growable: false);
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      key: const Key('swap-source-address-search'),
                      onChanged: (value) => setSheetState(() => query = value),
                      decoration: InputDecoration(
                        hintText: unifiedSwapText(
                          context,
                          'picker.searchAddresses',
                          'Search owned addresses',
                        ),
                        prefixIcon: const Icon(Icons.search_rounded),
                      ),
                    ),
                    const SizedBox(height: 14),
                    if (visible.isEmpty)
                      UnifiedSwapNotice(
                        title: unifiedSwapText(
                          context,
                          'picker.noAddressesTitle',
                          'No eligible source addresses',
                        ),
                        message: unifiedSwapText(
                          context,
                          'picker.noAddressesBody',
                          'The wallet could not verify a fresh executable '
                              'address and balance.',
                        ),
                        tone: UnifiedSwapNoticeTone.warning,
                        icon: Icons.account_balance_wallet_outlined,
                      )
                    else
                      Expanded(
                        child:
                            _RovingPickerList<UnifiedSwapSourceAddressOption>(
                              items: visible,
                              identity: (option) =>
                                  option.selection.fingerprint,
                              preferredIdentity: selected.fingerprint,
                              itemBuilder:
                                  (context, option, focusNode, focusTarget) {
                                    final isSelected =
                                        option.selection == selected;
                                    return _SourceAddressSelectionRow(
                                      key: ValueKey<int>(
                                        Object.hash(
                                          'swap-source-address-option',
                                          option.selection.fingerprint,
                                        ),
                                      ),
                                      asset: asset,
                                      option: option,
                                      selected: isSelected,
                                      focusNode: focusNode,
                                      focusTarget: focusTarget,
                                      onPressed: isSelected
                                          ? () => completeUnifiedSwapPicker(
                                              sheetContext,
                                            )
                                          : () => completeUnifiedSwapPicker(
                                              sheetContext,
                                              option.selection,
                                            ),
                                    );
                                  },
                            ),
                      ),
                  ],
                );
              },
            );
          },
        ),
  );
}

class _PickerLoading extends StatelessWidget {
  const _PickerLoading({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    label: label,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(label, style: UnifiedSwapDesign.typography(context).labelLarge),
        const SizedBox(height: 16),
        const UnifiedSwapSkeleton(height: 72),
        const SizedBox(height: 8),
        const UnifiedSwapSkeleton(height: 72),
        const SizedBox(height: 8),
        const UnifiedSwapSkeleton(height: 72),
      ],
    ),
  );
}

class _PickerFailure extends StatelessWidget {
  const _PickerFailure({
    required this.title,
    required this.message,
    required this.onClose,
  });

  final String title;
  final String message;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      UnifiedSwapNotice(
        title: title,
        message: message,
        tone: UnifiedSwapNoticeTone.danger,
        icon: Icons.cloud_off_outlined,
        liveRegion: true,
      ),
      const SizedBox(height: 12),
      OutlinedButton(
        style: UnifiedSwapDesign.secondaryButtonStyle(context),
        onPressed: onClose,
        child: Text(unifiedSwapText(context, 'common.goBack', 'Go back')),
      ),
    ],
  );
}

Future<String?> _showRecipientSelection(
  BuildContext context, {
  required UnifiedSwapAssetIdentity asset,
  required TextEditingController controller,
  required FocusNode focusNode,
  required UnifiedSwapRecipientValidator? validator,
}) async {
  final draft = TextEditingController(text: controller.text);
  try {
    return await showUnifiedSwapPicker<String>(
      context: context,
      title: unifiedSwapText(
        context,
        'recipient.chooseTitle',
        'Choose receiving address',
      ),
      subtitle: unifiedSwapText(
        context,
        'recipient.chooseSubtitle',
        '{asset} on {network}',
        namedArgs: {
          'asset': asset.ticker,
          'network': unifiedSwapNetworkLabel(context, asset),
        },
      ),
      builder: (sheetContext) {
        String? error;
        var validating = false;
        return StatefulBuilder(
          builder: (context, setSheetState) => SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  unifiedSwapText(
                    context,
                    'recipient.receivingAddress',
                    'Receiving address',
                  ),
                  style: UnifiedSwapDesign.typography(context).labelLarge,
                ),
                const SizedBox(height: 8),
                TextField(
                  key: const Key('swap-recipient-input'),
                  controller: draft,
                  focusNode: focusNode,
                  autofocus: true,
                  autocorrect: false,
                  enableSuggestions: false,
                  minLines: 1,
                  maxLines: 3,
                  maxLength: _maximumRecipientLength,
                  inputFormatters: [
                    LengthLimitingTextInputFormatter(_maximumRecipientLength),
                  ],
                  textInputAction: TextInputAction.done,
                  onChanged: (_) {
                    if (error != null) setSheetState(() => error = null);
                  },
                  onSubmitted: validating
                      ? null
                      : (_) => unawaited(
                          _completeRecipientDraft(
                            context,
                            sheetContext,
                            asset: asset,
                            controller: draft,
                            validator: validator,
                            onValidating: (value) =>
                                setSheetState(() => validating = value),
                            onError: (message) =>
                                setSheetState(() => error = message),
                          ),
                        ),
                  decoration: InputDecoration(
                    hintText: unifiedSwapText(
                      context,
                      'recipient.addressHint',
                      'Enter {network} address',
                      namedArgs: {
                        'network': unifiedSwapNetworkLabel(context, asset),
                      },
                    ),
                    errorText: error,
                    suffixIcon: IconButton(
                      tooltip: unifiedSwapText(
                        context,
                        'recipient.clear',
                        'Clear address',
                      ),
                      onPressed: () {
                        draft.clear();
                        setSheetState(() => error = null);
                      },
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                UnifiedSwapNotice(
                  title: unifiedSwapText(
                    context,
                    'recipient.checkNetworkTitle',
                    'Check the receiving network',
                  ),
                  message: unifiedSwapText(
                    context,
                    'recipient.checkNetworkBody',
                    'The address must support {asset} on {network}. External '
                        'recipients require a separate confirmation.',
                    namedArgs: {
                      'asset': asset.ticker,
                      'network': unifiedSwapNetworkLabel(context, asset),
                    },
                  ),
                  tone: UnifiedSwapNoticeTone.warning,
                  icon: Icons.location_on_outlined,
                ),
                const SizedBox(height: 16),
                FilledButton(
                  key: const Key('swap-use-recipient'),
                  style: UnifiedSwapDesign.primaryButtonStyle(context),
                  onPressed: validating
                      ? null
                      : () => unawaited(
                          _completeRecipientDraft(
                            context,
                            sheetContext,
                            asset: asset,
                            controller: draft,
                            validator: validator,
                            onValidating: (value) =>
                                setSheetState(() => validating = value),
                            onError: (message) =>
                                setSheetState(() => error = message),
                          ),
                        ),
                  child: validating
                      ? Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              unifiedSwapText(
                                context,
                                'recipient.validating',
                                'Validating address',
                              ),
                            ),
                          ],
                        )
                      : Text(
                          unifiedSwapText(
                            context,
                            'recipient.useAddress',
                            'Use this address',
                          ),
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  } finally {
    draft.dispose();
  }
}

Future<void> _completeRecipientDraft(
  BuildContext context,
  BuildContext sheetContext, {
  required UnifiedSwapAssetIdentity asset,
  required TextEditingController controller,
  required UnifiedSwapRecipientValidator? validator,
  required ValueChanged<bool> onValidating,
  required ValueChanged<String> onError,
}) async {
  final value = controller.text.trim();
  if (value.isEmpty || value.contains(RegExp(r'\s'))) {
    onError(
      unifiedSwapText(
        context,
        'recipient.invalidAddress',
        'Enter one complete address with no spaces.',
      ),
    );
    return;
  }
  if (validator != null) {
    onValidating(true);
    bool valid;
    try {
      valid = await validator(
        asset: asset,
        address: value,
      ).timeout(_walletInteractionDeadline);
    } on Object {
      if (!sheetContext.mounted) return;
      onValidating(false);
      onError(
        unifiedSwapText(
          sheetContext,
          'recipient.validationUnavailable',
          'Address validation is temporarily unavailable. Try again.',
        ),
      );
      return;
    }
    if (!sheetContext.mounted) return;
    onValidating(false);
    if (!valid) {
      onError(
        unifiedSwapText(
          sheetContext,
          'recipient.invalidForNetwork',
          'This address is not valid for {network}. Check the address and '
              'destination network.',
          namedArgs: {'network': unifiedSwapNetworkLabel(sheetContext, asset)},
        ),
      );
      return;
    }
  }
  completeUnifiedSwapPicker(sheetContext, value);
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

class _RovingPickerList<T> extends StatefulWidget {
  const _RovingPickerList({
    required this.items,
    required this.identity,
    required this.preferredIdentity,
    required this.itemBuilder,
  });

  final List<T> items;
  final String Function(T item) identity;
  final String? preferredIdentity;
  final Widget Function(
    BuildContext context,
    T item,
    FocusNode focusNode,
    bool focusTarget,
  )
  itemBuilder;

  @override
  State<_RovingPickerList<T>> createState() => _RovingPickerListState<T>();
}

class _RovingPickerListState<T> extends State<_RovingPickerList<T>> {
  final Map<String, FocusNode> _focusNodes = {};
  final ScrollController _scrollController = ScrollController();
  String? _focusTarget;
  String? _requestedFocusTarget;
  int _focusRequest = 0;

  @override
  void initState() {
    super.initState();
    _syncFocusTarget();
  }

  @override
  void didUpdateWidget(covariant _RovingPickerList<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    _focusRequest++;
    _syncFocusTarget();
  }

  void _syncFocusTarget() {
    final identities = widget.items.map(widget.identity).toList();
    if (identities.isEmpty) {
      _focusTarget = null;
      _requestedFocusTarget = null;
      return;
    }
    if (_focusTarget == null || !identities.contains(_focusTarget)) {
      final preferred = widget.preferredIdentity;
      _focusTarget = preferred != null && identities.contains(preferred)
          ? preferred
          : identities.first;
    }
    if (_requestedFocusTarget == null ||
        !identities.contains(_requestedFocusTarget)) {
      _requestedFocusTarget = _focusTarget;
    }
  }

  FocusNode _nodeFor(String identity) => _focusNodes.putIfAbsent(
    identity,
    () => FocusNode(debugLabel: 'Unified Swap picker option'),
  );

  KeyEventResult _move(LogicalKeyboardKey key) {
    if (widget.items.isEmpty) return KeyEventResult.ignored;
    final identities = widget.items.map(widget.identity).toList();
    final current = _requestedFocusTarget ?? _focusTarget;
    var index = current == null ? -1 : identities.indexOf(current);
    if (index < 0) index = 0;
    if (key == LogicalKeyboardKey.home) {
      index = 0;
    } else if (key == LogicalKeyboardKey.end) {
      index = identities.length - 1;
    } else if (key == LogicalKeyboardKey.arrowDown ||
        key == LogicalKeyboardKey.arrowRight) {
      index = (index + 1).clamp(0, identities.length - 1);
    } else if (key == LogicalKeyboardKey.arrowUp ||
        key == LogicalKeyboardKey.arrowLeft) {
      index = (index - 1).clamp(0, identities.length - 1);
    } else {
      return KeyEventResult.ignored;
    }
    final next = identities[index];
    _requestedFocusTarget = next;
    final request = ++_focusRequest;
    unawaited(_revealAndFocus(next, index, request));
    return KeyEventResult.handled;
  }

  Future<void> _revealAndFocus(
    String identity,
    int targetIndex,
    int request,
  ) async {
    final node = _nodeFor(identity);
    final revealed = await _revealLazyListFocusTarget(
      scrollController: _scrollController,
      targetFocusNode: node,
      targetIndex: targetIndex,
      itemCount: widget.items.length,
      isCurrent: () =>
          mounted &&
          request == _focusRequest &&
          _requestedFocusTarget == identity,
    );
    if (!revealed ||
        !mounted ||
        request != _focusRequest ||
        _requestedFocusTarget != identity) {
      return;
    }
    setState(() => _focusTarget = identity);
    await WidgetsBinding.instance.endOfFrame;
    if (mounted &&
        request == _focusRequest &&
        _requestedFocusTarget == identity &&
        node.canRequestFocus) {
      node.requestFocus();
    }
  }

  @override
  void dispose() {
    _focusRequest++;
    _scrollController.dispose();
    for (final node in _focusNodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      onKeyEvent: (_, event) => event is KeyDownEvent
          ? _move(event.logicalKey)
          : KeyEventResult.ignored,
      child: ListView.separated(
        controller: _scrollController,
        itemCount: widget.items.length,
        separatorBuilder: (_, _) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          final item = widget.items[index];
          final identity = widget.identity(item);
          return widget.itemBuilder(
            context,
            item,
            _nodeFor(identity),
            identity == _focusTarget,
          );
        },
      ),
    );
  }
}

class _AssetSelectionRow extends StatelessWidget {
  const _AssetSelectionRow({
    required this.option,
    required this.selected,
    required this.focusNode,
    required this.focusTarget,
    required this.onPressed,
    super.key,
  });

  final UnifiedSwapAssetOption option;
  final bool selected;
  final FocusNode focusNode;
  final bool focusTarget;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = UnifiedSwapDesign.colors(context);
    final asset = option.identity;
    return Semantics(
      selected: selected,
      button: true,
      inMutuallyExclusiveGroup: true,
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
          canRequestFocus: focusTarget,
          focusNode: focusNode,
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

String _selectionAssetKey(UnifiedSwapAssetIdentity asset) =>
    '${asset.chainFamily.name}:${asset.chainId}:${asset.kind.name}:'
    '${asset.contractIdentity ?? ''}:${asset.decimals}:'
    '${asset.ticker}';

class _SourceAddressSelectionRow extends StatelessWidget {
  const _SourceAddressSelectionRow({
    required this.asset,
    required this.option,
    required this.selected,
    required this.focusNode,
    required this.focusTarget,
    required this.onPressed,
    super.key,
  });

  final UnifiedSwapAssetIdentity asset;
  final UnifiedSwapSourceAddressOption option;
  final bool selected;
  final FocusNode focusNode;
  final bool focusTarget;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = UnifiedSwapDesign.colors(context);
    return Semantics(
      selected: selected,
      button: true,
      inMutuallyExclusiveGroup: true,
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
          canRequestFocus: focusTarget,
          focusNode: focusNode,
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

String _sourceAddressShort(
  BuildContext context,
  UnifiedSwapIntent intent,
  UnifiedSwapSourceAddressOption? option,
) {
  if (option == null) return _sourceSelectionShort(context, intent);
  final address = unifiedSwapShortIdentity(option.address);
  final label = option.label?.trim();
  return label == null || label.isEmpty ? address : '$label · $address';
}

String _valuationSummary(
  BuildContext context,
  UnifiedSwapQuoteCandidate? candidate,
) {
  final valuation = candidate?.valuation;
  if (valuation == null) {
    return unifiedSwapText(
      context,
      'entry.priceEstimateUnavailable',
      'Price estimate unavailable',
    );
  }
  return unifiedSwapText(
    context,
    'entry.netMinimumValue',
    'Net minimum value {currency} {value}',
    namedArgs: {
      'currency': valuation.currency,
      'value': valuation.netMinimumReceive,
    },
  );
}

String _sourceValuationSummary(
  BuildContext context,
  UnifiedSwapQuoteCandidate? candidate,
) {
  final valuation = candidate?.valuation;
  final value = valuation?.sourceValue;
  if (valuation == null || value == null) {
    return unifiedSwapText(
      context,
      'entry.priceEstimateUnavailable',
      'Price estimate unavailable',
    );
  }
  return unifiedSwapText(
    context,
    'entry.sourceValue',
    'Estimated value {currency} {value}',
    namedArgs: {'currency': valuation.currency, 'value': value},
  );
}

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
  final assets = <String, UnifiedSwapAssetIdentity>{};
  final includedByKey = <String, bool>{};
  final totals = <String, BigInt>{};
  for (final fee in candidate.fees) {
    final key = '${fee.included}:${_feeAssetKey(fee.asset)}';
    assets[key] = fee.asset;
    includedByKey[key] = fee.included;
    totals.update(
      key,
      (amount) => amount + BigInt.parse(fee.amount),
      ifAbsent: () => BigInt.parse(fee.amount),
    );
  }
  return totals.entries
      .map((entry) {
        final label = includedByKey[entry.key] == true
            ? unifiedSwapText(
                context,
                'quote.includedInReceive',
                'Included in receive',
              )
            : unifiedSwapText(context, 'quote.additionalFee', 'Additional');
        return '$label: '
            '${swapAmount(entry.value.toString(), assets[entry.key]!)}';
      })
      .join(' + ');
}

String _feeAssetKey(UnifiedSwapAssetIdentity asset) =>
    '${asset.chainFamily.name}:${asset.chainId}:${asset.kind.name}:'
    '${asset.contractIdentity ?? ''}:${asset.decimals}:'
    '${asset.ticker}';

String _candidateDuration(
  BuildContext context,
  UnifiedSwapQuoteCandidate candidate,
) {
  final duration = candidate.estimatedDuration;
  return duration == null
      ? unifiedSwapText(context, 'quote.estimateUnavailable', 'Unavailable')
      : swapDuration(context, duration);
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
  if (input.length > UnifiedSwapModelLimits.amountDigits + 1 ||
      decimals < 0 ||
      decimals > UnifiedSwapModelLimits.amountDigits) {
    return null;
  }
  final value = input.trim();
  if (!RegExp(r'^(?:0|[1-9][0-9]*)(?:\.[0-9]+)?$').hasMatch(value)) {
    return null;
  }
  final parts = value.split('.');
  final fraction = parts.length == 1 ? '' : parts[1];
  if (fraction.length > decimals) return null;
  final padded = fraction.padRight(decimals, '0');
  final combined = '${parts[0]}$padded';
  final firstNonZero = combined.indexOf(RegExp('[1-9]'));
  final canonical = firstNonZero < 0 ? '0' : combined.substring(firstNonZero);
  if (canonical.length > UnifiedSwapModelLimits.amountDigits) return null;
  return BigInt.parse(canonical).toString();
}
