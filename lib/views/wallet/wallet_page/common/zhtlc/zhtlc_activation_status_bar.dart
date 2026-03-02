import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart' show AssetId;
import 'package:komodo_ui/komodo_ui.dart';
import 'package:komodo_ui_kit/komodo_ui_kit.dart';
import 'package:web_dex/bloc/auth_bloc/auth_bloc.dart';
import 'package:web_dex/generated/codegen_loader.g.dart' show LocaleKeys;
import 'package:web_dex/services/arrr_activation/arrr_activation_service.dart';
import 'package:web_dex/services/arrr_activation/arrr_config.dart';

/// Status bar widget to display ZHTLC activation progress for multiple coins
class ZhtlcActivationStatusBar extends StatefulWidget {
  const ZhtlcActivationStatusBar({super.key, required this.activationService});

  final ArrrActivationService activationService;

  @override
  State<ZhtlcActivationStatusBar> createState() =>
      _ZhtlcActivationStatusBarState();
}

class _ZhtlcActivationStatusBarState extends State<ZhtlcActivationStatusBar> {
  Timer? _refreshTimer;
  Map<AssetId, ArrrActivationStatus> _cachedStatuses = {};
  StreamSubscription<AuthBlocState>? _authSubscription;

  @override
  void initState() {
    super.initState();
    _startPeriodicRefresh();
    _subscribeToAuthChanges();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _authSubscription?.cancel();
    super.dispose();
  }

  void _subscribeToAuthChanges() {
    _authSubscription = context.read<AuthBloc>().stream.listen((state) {
      if (state.currentUser == null) {
        unawaited(_handleSignedOut());
      }
    });
  }

  void _startPeriodicRefresh() {
    unawaited(_refreshStatuses());
    _refreshTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      unawaited(_refreshStatuses());
    });
  }

  Future<void> _refreshStatuses() async {
    final newStatuses = await widget.activationService.activationStatuses;

    if (!mounted) {
      return;
    }

    setState(() {
      _cachedStatuses = newStatuses;
    });
  }

  Future<void> _handleSignedOut() async {
    if (!mounted) {
      _cachedStatuses = {};
      return;
    }

    final assetIds = _cachedStatuses.keys.toList();
    for (final assetId in assetIds) {
      await widget.activationService.clearActivationStatus(assetId);
    }

    if (!mounted) {
      _cachedStatuses = {};
      return;
    }

    setState(() {
      _cachedStatuses = {};
    });
  }

  Future<void> _cancelActivation(AssetId assetId) async {
    await widget.activationService.cancelActivation(assetId);
    await widget.activationService.clearActivationStatus(assetId);
    await _refreshStatuses();
  }

  @override
  Widget build(BuildContext context) {
    // Filter out completed statuses older than 5 seconds
    // Keep error statuses for 60 seconds (these are final errors after all retries)
    final activeStatuses = _cachedStatuses.entries.where((entry) {
      final status = entry.value;
      return status.when(
        inProgress:
            (
              assetId,
              startTime,
              progressPercentage,
              currentStep,
              statusMessage,
            ) => true,
        completed: (coinId, completionTime) =>
            DateTime.now().difference(completionTime).inSeconds < 5,
        error: (coinId, errorMessage, errorTime) =>
            DateTime.now().difference(errorTime).inSeconds < 60,
      );
    }).toList();

    if (activeStatuses.isEmpty) {
      return const SizedBox.shrink();
    }

    final coinCount = activeStatuses.length;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.2),
          ),
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 12.0),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: AutoScrollText(
                      text: LocaleKeys.zhtlcActivating.plural(coinCount),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
              Row(
                children: [
                  const SizedBox(width: 26),
                  Expanded(
                    child: AutoScrollText(
                      text: LocaleKeys.zhtlcActivationWarning.tr(),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Column(
                children: activeStatuses.map((entry) {
                  final status = entry.value;
                  return Padding(
                    padding: const EdgeInsets.only(top: 4.0),
                    child: status.when(
                      completed: (_, __) => const SizedBox.shrink(),
                      error: (assetId, errorMessage, errorTime) => Padding(
                        padding: const EdgeInsets.only(top: 8.0),
                        child: ErrorDisplay(
                          message:
                              '${assetId.id}: ${LocaleKeys.activationFailedMessage.tr()}',
                          detailedMessage: errorMessage,
                          showDetails: false,
                          showIcon: true,
                          narrowBreakpoint: 400,
                        ),
                      ),
                      inProgress:
                          (
                            assetId,
                            startTime,
                            progressPercentage,
                            _,
                            statusMessage,
                          ) {
                            return _ActivationStatusDetails(
                              assetId: assetId,
                              progressPercentage:
                                  progressPercentage?.toDouble() ?? 0,
                              statusMessage:
                                  statusMessage ?? LocaleKeys.inProgress.tr(),
                              onCancel: () {
                                unawaited(_cancelActivation(assetId));
                              },
                            );
                          },
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActivationStatusDetails extends StatelessWidget {
  const _ActivationStatusDetails({
    required this.assetId,
    required this.progressPercentage,
    required this.statusMessage,
    required this.onCancel,
  });

  final AssetId assetId;
  final double progressPercentage;
  final String statusMessage;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final statusDetailsText =
        '${assetId.id}: $statusMessage '
        '(${progressPercentage.toStringAsFixed(0)}%)';

    return Padding(
      padding: const EdgeInsets.only(left: 24.0),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: AutoScrollText(
              text: statusDetailsText,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).textTheme.bodySmall?.color,
              ),
            ),
          ),
          Tooltip(
            message: LocaleKeys.cancel.tr(),
            child: IconButton(
              visualDensity: VisualDensity.compact,
              iconSize: 18,
              onPressed: onCancel,
              icon: const Icon(Icons.close_rounded),
            ),
          ),
        ],
      ),
    );
  }
}
