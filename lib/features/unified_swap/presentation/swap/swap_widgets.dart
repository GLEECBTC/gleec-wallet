import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/semantics.dart';
import 'package:web_dex/features/unified_swap/domain/route_activity_models.dart';
import 'package:web_dex/features/unified_swap/domain/unified_swap_capability_policy.dart';
import 'package:web_dex/features/unified_swap/domain/unified_swap_quote_models.dart';
import 'package:web_dex/features/unified_swap/presentation/unified_swap_design.dart';

typedef SwapClipboardWriter = Future<void> Function(String value);
typedef SwapAnnouncement =
    Future<void> Function(BuildContext context, String message);

Future<void> defaultSwapClipboardWriter(String value) =>
    Clipboard.setData(ClipboardData(text: value));

Future<void> defaultSwapAnnouncement(BuildContext context, String message) =>
    SemanticsService.sendAnnouncement(
      View.of(context),
      message,
      Directionality.of(context),
    );

class SwapCopyableValue extends StatefulWidget {
  const SwapCopyableValue({
    required this.label,
    required this.value,
    required this.clipboardWriter,
    required this.announcement,
    required this.valueKey,
    this.compact = false,
    super.key,
  });

  final String label;
  final String value;
  final SwapClipboardWriter clipboardWriter;
  final SwapAnnouncement announcement;
  final String valueKey;
  final bool compact;

  @override
  State<SwapCopyableValue> createState() => _SwapCopyableValueState();
}

class _SwapCopyableValueState extends State<SwapCopyableValue> {
  bool _copying = false;

  Future<void> _copy() async {
    if (_copying) return;
    setState(() => _copying = true);
    try {
      await widget.clipboardWriter(widget.value);
    } on Object {
      if (!mounted) return;
      _message(
        unifiedSwapText(
          context,
          'common.copyFailed',
          '{label} could not be copied.',
          namedArgs: {'label': widget.label},
        ),
        error: true,
      );
      return;
    } finally {
      if (mounted) setState(() => _copying = false);
    }
    if (!mounted) return;
    final message = unifiedSwapText(
      context,
      'common.copied',
      '{label} copied.',
      namedArgs: {'label': widget.label},
    );
    _message(message);
    try {
      await widget.announcement(context, message);
    } on Object {
      // Clipboard success remains authoritative when an explicit platform
      // accessibility announcement is unavailable.
    }
  }

  void _message(String message, {bool error = false}) {
    final colors = Theme.of(context).colorScheme;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        content: Semantics(liveRegion: true, child: Text(message)),
        backgroundColor: error ? colors.error : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = UnifiedSwapDesign.colors(context);
    return Semantics(
      container: true,
      label: unifiedSwapText(
        context,
        'common.labelValueSemantics',
        '{label}: {value}',
        namedArgs: {'label': widget.label, 'value': widget.value},
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: ExcludeSemantics(
              child: SelectableText(
                widget.value,
                key: Key(widget.valueKey),
                maxLines: widget.compact ? 1 : null,
                style: widget.compact
                    ? UnifiedSwapDesign.typography(context).bodySmall
                    : UnifiedSwapDesign.typography(context).bodyMedium,
              ),
            ),
          ),
          const SizedBox(width: 4),
          IconButton(
            key: Key('${widget.valueKey}-copy'),
            onPressed: _copying ? null : _copy,
            tooltip: unifiedSwapText(
              context,
              'common.copyFull',
              'Copy full {label}',
              namedArgs: {'label': widget.label.toLowerCase()},
            ),
            icon: _copying
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.copy_rounded),
            color: colors.textSecondary,
          ),
        ],
      ),
    );
  }
}

class SwapSectionCard extends StatelessWidget {
  const SwapSectionCard({
    required this.title,
    required this.child,
    this.icon,
    this.semanticLabel,
    super.key,
  });

  final String title;
  final Widget child;
  final IconData? icon;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final colors = UnifiedSwapDesign.colors(context);
    return Semantics(
      container: true,
      label: semanticLabel ?? title,
      child: UnifiedSwapSurface(
        backgroundColor: colors.surfaceRaised,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (icon case final icon?) ...[
                  Icon(icon, size: 20, color: colors.brandHover),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: Text(
                    title,
                    style: UnifiedSwapDesign.typography(context).cardTitle,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

class SwapUnavailable extends StatelessWidget {
  const SwapUnavailable({
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
    this.liveRegion = false,
    super.key,
  });

  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final bool liveRegion;

  @override
  Widget build(BuildContext context) {
    final colors = UnifiedSwapDesign.colors(context);
    return ColoredBox(
      color: colors.canvas,
      child: Center(
        child: SingleChildScrollView(
          padding: UnifiedSwapDesign.pagePadding(context),
          child: Semantics(
            container: true,
            liveRegion: liveRegion,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: UnifiedSwapSurface(
                elevated: true,
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: colors.selected,
                        borderRadius: BorderRadius.circular(22),
                      ),
                      child: SizedBox.square(
                        dimension: 64,
                        child: Icon(
                          Icons.swap_horiz_rounded,
                          size: 32,
                          color: colors.brandHover,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      title,
                      style: UnifiedSwapDesign.typography(context).sectionTitle,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      message,
                      textAlign: TextAlign.center,
                      style: UnifiedSwapDesign.typography(context).bodyMedium,
                    ),
                    if (actionLabel != null && onAction != null) ...[
                      const SizedBox(height: 20),
                      FilledButton.tonal(
                        style: UnifiedSwapDesign.primaryButtonStyle(context),
                        onPressed: onAction,
                        child: Text(actionLabel!),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

String swapAssetLabel(BuildContext context, UnifiedSwapAssetIdentity asset) {
  final family = switch (asset.chainFamily) {
    UnifiedSwapChainFamily.evm => unifiedSwapText(
      context,
      'asset.family.evm',
      'EVM',
    ),
    UnifiedSwapChainFamily.tron => unifiedSwapText(
      context,
      'asset.family.tron',
      'Tron',
    ),
    UnifiedSwapChainFamily.utxo => unifiedSwapText(
      context,
      'asset.family.utxo',
      'UTXO',
    ),
    UnifiedSwapChainFamily.solana => unifiedSwapText(
      context,
      'asset.family.solana',
      'Solana',
    ),
    UnifiedSwapChainFamily.sui => unifiedSwapText(
      context,
      'asset.family.sui',
      'Sui',
    ),
    UnifiedSwapChainFamily.other => unifiedSwapText(
      context,
      'asset.family.other',
      'Other',
    ),
    UnifiedSwapChainFamily.unknown => unifiedSwapText(
      context,
      'asset.family.unknown',
      'Unknown network family',
    ),
  };
  final kind = swapAssetKind(context, asset.kind);
  return unifiedSwapText(
    context,
    'asset.identity',
    '{ticker} · {family} chain {chainId} · {kind} · {decimals} decimals',
    namedArgs: {
      'ticker': asset.ticker,
      'family': family,
      'chainId': asset.chainId,
      'kind': kind,
      'decimals': '${asset.decimals}',
    },
  );
}

String swapAssetKind(BuildContext context, UnifiedSwapAssetKind kind) =>
    switch (kind) {
      UnifiedSwapAssetKind.native => unifiedSwapText(
        context,
        'asset.kind.native',
        'native',
      ),
      UnifiedSwapAssetKind.token => unifiedSwapText(
        context,
        'asset.kind.token',
        'token',
      ),
      UnifiedSwapAssetKind.unknown => unifiedSwapText(
        context,
        'asset.kind.unknown',
        'unknown asset type',
      ),
    };

String swapAssetContract(
  BuildContext context,
  UnifiedSwapAssetIdentity asset,
) =>
    asset.contractAddress ??
    unifiedSwapText(
      context,
      'asset.nativeContract',
      'Native asset (no token contract)',
    );

String swapAmount(String smallestUnits, UnifiedSwapAssetIdentity asset) {
  final decimals = asset.decimals;
  if (decimals <= 0) return '$smallestUnits ${asset.ticker}';
  final padded = smallestUnits.padLeft(decimals + 1, '0');
  final split = padded.length - decimals;
  final whole = padded.substring(0, split);
  final fraction = padded.substring(split).replaceFirst(RegExp(r'0+$'), '');
  return '${fraction.isEmpty ? whole : '$whole.$fraction'} ${asset.ticker}';
}

String swapFeeKind(BuildContext context, RouteFeeKind kind) => switch (kind) {
  RouteFeeKind.provider => unifiedSwapText(
    context,
    'fees.service',
    'Service fee',
  ),
  RouteFeeKind.bridge => unifiedSwapText(context, 'fees.bridge', 'Bridge fee'),
  RouteFeeKind.exchange => unifiedSwapText(
    context,
    'fees.exchange',
    'Exchange fee',
  ),
  RouteFeeKind.network => unifiedSwapText(
    context,
    'fees.network',
    'Network fee',
  ),
  RouteFeeKind.kdf => unifiedSwapText(context, 'fees.swap', 'Swap fee'),
  RouteFeeKind.unknown => unifiedSwapText(
    context,
    'fees.unknown',
    'Unknown fee type',
  ),
};

String swapDuration(BuildContext context, Duration duration) {
  if (duration.inHours > 0) {
    final minutes = duration.inMinutes.remainder(60);
    return minutes == 0
        ? unifiedSwapText(
            context,
            'duration.hours',
            '{hours} hr',
            namedArgs: {'hours': '${duration.inHours}'},
          )
        : unifiedSwapText(
            context,
            'duration.hoursMinutes',
            '{hours} hr {minutes} min',
            namedArgs: {'hours': '${duration.inHours}', 'minutes': '$minutes'},
          );
  }
  if (duration.inMinutes > 0) {
    return unifiedSwapText(
      context,
      'duration.minutes',
      '{minutes} min',
      namedArgs: {'minutes': '${duration.inMinutes}'},
    );
  }
  return unifiedSwapText(
    context,
    'duration.seconds',
    '{seconds} sec',
    namedArgs: {'seconds': '${duration.inSeconds}'},
  );
}

bool isSafeSwapCandidate(UnifiedSwapQuoteCandidate candidate) =>
    candidate.isExecutable &&
    candidate.topology != UnifiedSwapTopology.unknown &&
    candidate.fees.every(
      (fee) =>
          fee.kind != RouteFeeKind.unknown &&
          fee.asset.chainFamily != UnifiedSwapChainFamily.unknown &&
          fee.asset.kind != UnifiedSwapAssetKind.unknown,
    );
