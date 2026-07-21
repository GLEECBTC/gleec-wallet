import 'dart:async';

import 'package:app_theme/app_theme.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:web_dex/features/unified_swap/domain/unified_swap_capability_policy.dart';

/// Shared presentation primitives for the approved Unified Swap prototype.
///
/// The feature deliberately consumes Calm Core semantic tokens. The static
/// fallback keeps isolated widget tests and previews usable when a host has not
/// installed the global theme extensions yet; production always receives the
/// extensions from the wallet theme.
abstract final class UnifiedSwapDesign {
  static const double desktopBreakpoint = 900;
  static const double compactBreakpoint = 520;
  static const double contentWidth = 576;
  static const double detailWidth = 1040;

  static GleecColorTokens colors(BuildContext context) {
    return Theme.of(context).extension<GleecColorTokens>() ??
        (Theme.of(context).brightness == Brightness.dark
            ? GleecColorTokens.dark
            : GleecColorTokens.light);
  }

  static GleecGeometry geometry(BuildContext context) {
    return Theme.of(context).extension<GleecGeometry>() ??
        GleecGeometry.standard;
  }

  static GleecMotion motion(BuildContext context) {
    return Theme.of(context).extension<GleecMotion>() ??
        GleecMotion.standardTokens;
  }

  static GleecTypography typography(BuildContext context) {
    return Theme.of(context).extension<GleecTypography>() ??
        GleecTypography.fromColors(colors(context));
  }

  static EdgeInsets pagePadding(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    if (width >= desktopBreakpoint) {
      return const EdgeInsets.fromLTRB(24, 40, 24, 56);
    }
    if (width >= 700) return const EdgeInsets.fromLTRB(16, 24, 16, 40);
    return const EdgeInsets.fromLTRB(16, 24, 16, 32);
  }

  static ButtonStyle primaryButtonStyle(BuildContext context) {
    final colors = UnifiedSwapDesign.colors(context);
    final geometry = UnifiedSwapDesign.geometry(context);
    return FilledButton.styleFrom(
      minimumSize: Size.fromHeight(geometry.inputHeight),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      foregroundColor: Colors.white,
      backgroundColor: colors.brand,
      disabledBackgroundColor: colors.surfaceHighest,
      disabledForegroundColor: colors.textTertiary,
      shape: RoundedRectangleBorder(
        borderRadius: geometry.borderRadius16,
        side: BorderSide(color: colors.brand),
      ),
      textStyle: typography(
        context,
      ).labelLarge.copyWith(color: Colors.white, fontWeight: FontWeight.w800),
    );
  }

  static ButtonStyle secondaryButtonStyle(BuildContext context) {
    final colors = UnifiedSwapDesign.colors(context);
    final geometry = UnifiedSwapDesign.geometry(context);
    return OutlinedButton.styleFrom(
      minimumSize: Size.fromHeight(geometry.inputHeight),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      foregroundColor: colors.textPrimary,
      backgroundColor: colors.surfaceHigh,
      side: BorderSide(color: colors.controlBorder),
      shape: RoundedRectangleBorder(borderRadius: geometry.borderRadius16),
      textStyle: typography(
        context,
      ).labelLarge.copyWith(fontWeight: FontWeight.w800),
    );
  }
}

class UnifiedSwapPageTitle extends StatelessWidget {
  const UnifiedSwapPageTitle({
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    super.key,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final type = UnifiedSwapDesign.typography(context);
    final colors = UnifiedSwapDesign.colors(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (leading case final leading?) ...[
          leading,
          const SizedBox(width: 12),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(
                header: true,
                child: Text(title, style: type.pageTitle),
              ),
              if (subtitle case final subtitle?) ...[
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: type.bodyMedium.copyWith(color: colors.textTertiary),
                ),
              ],
            ],
          ),
        ),
        if (trailing case final trailing?) ...[
          const SizedBox(width: 12),
          trailing,
        ],
      ],
    );
  }
}

class UnifiedSwapSurface extends StatelessWidget {
  const UnifiedSwapSurface({
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.borderColor,
    this.backgroundColor,
    this.radius,
    this.semanticLabel,
    this.elevated = false,
    super.key,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? borderColor;
  final Color? backgroundColor;
  final double? radius;
  final String? semanticLabel;
  final bool elevated;

  @override
  Widget build(BuildContext context) {
    final colors = UnifiedSwapDesign.colors(context);
    final geometry = UnifiedSwapDesign.geometry(context);
    final content = DecoratedBox(
      decoration: BoxDecoration(
        color: backgroundColor ?? colors.surfaceRaised,
        border: Border.all(color: borderColor ?? colors.border),
        borderRadius: BorderRadius.circular(radius ?? geometry.radius18),
        boxShadow: elevated ? geometry.surfaceShadow(colors) : null,
      ),
      child: Padding(padding: padding, child: child),
    );
    if (semanticLabel == null) return content;
    return Semantics(container: true, label: semanticLabel, child: content);
  }
}

extension on GleecGeometry {
  double get radius18 => (radius16 + radius20) / 2;
  BorderRadius get borderRadius14 =>
      BorderRadius.circular((radius12 + radius16) / 2);
}

enum UnifiedSwapNoticeTone { brand, success, warning, danger, info, neutral }

class UnifiedSwapNotice extends StatelessWidget {
  const UnifiedSwapNotice({
    required this.title,
    this.message,
    this.icon,
    this.tone = UnifiedSwapNoticeTone.info,
    this.liveRegion = false,
    this.action,
    super.key,
  });

  final String title;
  final String? message;
  final IconData? icon;
  final UnifiedSwapNoticeTone tone;
  final bool liveRegion;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final colors = UnifiedSwapDesign.colors(context);
    final geometry = UnifiedSwapDesign.geometry(context);
    final (foreground, background, border) = switch (tone) {
      UnifiedSwapNoticeTone.brand => (
        colors.brandHover,
        colors.selected,
        colors.brand,
      ),
      UnifiedSwapNoticeTone.success => (
        colors.success,
        colors.successContainer,
        colors.success,
      ),
      UnifiedSwapNoticeTone.warning => (
        colors.warning,
        colors.warningContainer,
        colors.warning,
      ),
      UnifiedSwapNoticeTone.danger => (
        colors.danger,
        colors.dangerContainer,
        colors.danger,
      ),
      UnifiedSwapNoticeTone.info => (
        colors.info,
        colors.infoContainer,
        colors.info,
      ),
      UnifiedSwapNoticeTone.neutral => (
        colors.textSecondary,
        colors.surfaceHigh,
        colors.borderStrong,
      ),
    };
    return Semantics(
      container: true,
      liveRegion: liveRegion,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: background,
          border: Border.all(color: border),
          borderRadius: geometry.borderRadius14,
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon ?? Icons.info_outline_rounded, color: foreground),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: UnifiedSwapDesign.typography(context).labelLarge,
                    ),
                    if (message case final message?) ...[
                      const SizedBox(height: 3),
                      Text(
                        message,
                        style: UnifiedSwapDesign.typography(context).bodyMedium,
                      ),
                    ],
                  ],
                ),
              ),
              if (action case final action?) ...[
                const SizedBox(width: 8),
                action,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class UnifiedSwapBadge extends StatelessWidget {
  const UnifiedSwapBadge({
    required this.label,
    this.icon,
    this.tone = UnifiedSwapNoticeTone.neutral,
    super.key,
  });

  final String label;
  final IconData? icon;
  final UnifiedSwapNoticeTone tone;

  @override
  Widget build(BuildContext context) {
    final colors = UnifiedSwapDesign.colors(context);
    final (foreground, background, border) = switch (tone) {
      UnifiedSwapNoticeTone.brand => (
        colors.textPrimary,
        colors.selected,
        colors.brand,
      ),
      UnifiedSwapNoticeTone.success => (
        colors.success,
        colors.successContainer,
        colors.success,
      ),
      UnifiedSwapNoticeTone.warning => (
        colors.warning,
        colors.warningContainer,
        colors.warning,
      ),
      UnifiedSwapNoticeTone.danger => (
        colors.danger,
        colors.dangerContainer,
        colors.danger,
      ),
      UnifiedSwapNoticeTone.info => (
        colors.info,
        colors.infoContainer,
        colors.info,
      ),
      UnifiedSwapNoticeTone.neutral => (
        colors.textSecondary,
        colors.surfaceHigh,
        colors.border,
      ),
    };
    return DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        border: Border.all(color: border),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon case final icon?) ...[
              Icon(icon, color: foreground, size: 16),
              const SizedBox(width: 6),
            ],
            Flexible(
              child: Text(
                label,
                style: UnifiedSwapDesign.typography(
                  context,
                ).labelMedium.copyWith(color: foreground),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class UnifiedSwapAssetAvatar extends StatelessWidget {
  const UnifiedSwapAssetAvatar({
    required this.asset,
    this.size = 36,
    this.showChainBadge = true,
    super.key,
  });

  final UnifiedSwapAssetIdentity asset;
  final double size;
  final bool showChainBadge;

  @override
  Widget build(BuildContext context) {
    final colors = UnifiedSwapDesign.colors(context);
    final ticker = asset.ticker.trim().toLowerCase();
    final hasPrototypeArtwork = const {
      'btc',
      'eth',
      'usdc',
      'usdt',
      'wbtc',
    }.contains(ticker);
    final fallback = DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceHighest,
        shape: BoxShape.circle,
      ),
      child: Center(
        child: Text(
          _initials(asset.ticker),
          style: UnifiedSwapDesign.typography(context).labelMedium.copyWith(
            color: colors.textPrimary,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
    return SizedBox.square(
      dimension: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: hasPrototypeArtwork
                ? ClipOval(
                    child: Image.asset(
                      'prototypes/gleec-unified-swap/'
                      'gleec-unified-swap-assets/tokens/$ticker.png',
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => fallback,
                    ),
                  )
                : fallback,
          ),
          if (showChainBadge)
            PositionedDirectional(
              end: -5,
              bottom: -5,
              child: _ChainBadge(asset: asset, size: size * .5),
            ),
        ],
      ),
    );
  }
}

class _ChainBadge extends StatelessWidget {
  const _ChainBadge({required this.asset, required this.size});

  final UnifiedSwapAssetIdentity asset;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = UnifiedSwapDesign.colors(context);
    final assetPath = switch ((asset.chainFamily, asset.chainId)) {
      (UnifiedSwapChainFamily.evm, '1') =>
        'prototypes/gleec-unified-swap/'
            'gleec-unified-swap-assets/chains/ethereum.svg',
      (UnifiedSwapChainFamily.evm, '137') =>
        'prototypes/gleec-unified-swap/'
            'gleec-unified-swap-assets/chains/polygon.svg',
      (UnifiedSwapChainFamily.evm, '42161') =>
        'prototypes/gleec-unified-swap/'
            'gleec-unified-swap-assets/chains/arbitrum.png',
      (UnifiedSwapChainFamily.evm, '56') =>
        'assets/blockchain_icons/svg/32px/bsc.svg',
      (UnifiedSwapChainFamily.tron, _) =>
        'prototypes/gleec-unified-swap/'
            'gleec-unified-swap-assets/chains/tron.png',
      (UnifiedSwapChainFamily.utxo, _)
          when asset.ticker.toUpperCase() == 'BTC' =>
        'prototypes/gleec-unified-swap/'
            'gleec-unified-swap-assets/chains/bitcoin.png',
      _ => null,
    };
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border.all(color: colors.borderStrong),
        shape: BoxShape.circle,
      ),
      child: SizedBox.square(
        dimension: size,
        child: Padding(
          padding: const EdgeInsets.all(2),
          child: assetPath == null
              ? Center(
                  child: Text(
                    _chainInitial(asset),
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontSize: size * .42,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                )
              : assetPath.endsWith('.svg')
              ? SvgPicture.asset(assetPath)
              : Image.asset(assetPath, fit: BoxFit.contain),
        ),
      ),
    );
  }
}

class UnifiedSwapAssetButton extends StatelessWidget {
  const UnifiedSwapAssetButton({
    required this.asset,
    required this.networkLabel,
    this.onPressed,
    this.semanticLabel,
    super.key,
  });

  final UnifiedSwapAssetIdentity asset;
  final String networkLabel;
  final VoidCallback? onPressed;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final colors = UnifiedSwapDesign.colors(context);
    final geometry = UnifiedSwapDesign.geometry(context);
    return Semantics(
      button: true,
      enabled: onPressed != null,
      label:
          semanticLabel ??
          unifiedSwapText(
            context,
            'common.assetOnNetwork',
            '{asset} on {network}',
            namedArgs: {'asset': asset.ticker, 'network': networkLabel},
          ),
      child: Material(
        color: colors.surfaceHigh,
        borderRadius: geometry.borderRadius14,
        child: InkWell(
          onTap: onPressed,
          borderRadius: geometry.borderRadius14,
          child: Container(
            constraints: const BoxConstraints(minHeight: 60),
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
            decoration: BoxDecoration(
              border: Border.all(color: colors.controlBorder),
              borderRadius: geometry.borderRadius14,
            ),
            child: Row(
              children: [
                UnifiedSwapAssetAvatar(asset: asset, size: 36),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        asset.ticker,
                        style: UnifiedSwapDesign.typography(context).labelLarge,
                      ),
                      Text(
                        networkLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: UnifiedSwapDesign.typography(context).bodySmall,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                Icon(
                  Icons.keyboard_arrow_down_rounded,
                  color: colors.textSecondary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class UnifiedSwapStatusHero extends StatelessWidget {
  const UnifiedSwapStatusHero({
    required this.title,
    required this.icon,
    this.message,
    this.tone = UnifiedSwapNoticeTone.brand,
    super.key,
  });

  final String title;
  final String? message;
  final IconData icon;
  final UnifiedSwapNoticeTone tone;

  @override
  Widget build(BuildContext context) {
    final colors = UnifiedSwapDesign.colors(context);
    final (foreground, background) = switch (tone) {
      UnifiedSwapNoticeTone.success => (
        colors.success,
        colors.successContainer,
      ),
      UnifiedSwapNoticeTone.warning => (
        colors.warning,
        colors.warningContainer,
      ),
      UnifiedSwapNoticeTone.danger => (colors.danger, colors.dangerContainer),
      UnifiedSwapNoticeTone.info => (colors.info, colors.infoContainer),
      UnifiedSwapNoticeTone.brand => (colors.brandHover, colors.selected),
      UnifiedSwapNoticeTone.neutral => (
        colors.textSecondary,
        colors.surfaceHigh,
      ),
    };
    return Semantics(
      container: true,
      liveRegion: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 8),
        child: Column(
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: background,
                borderRadius: BorderRadius.circular(22),
              ),
              child: SizedBox.square(
                dimension: 64,
                child: Icon(icon, color: foreground, size: 30),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: UnifiedSwapDesign.typography(context).sectionTitle,
            ),
            if (message case final message?) ...[
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: UnifiedSwapDesign.typography(context).bodyMedium,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class UnifiedSwapQuestion extends StatelessWidget {
  const UnifiedSwapQuestion({
    required this.question,
    required this.answer,
    this.details,
    this.child,
    this.first = false,
    super.key,
  });

  final String question;
  final String answer;
  final String? details;
  final Widget? child;
  final bool first;

  @override
  Widget build(BuildContext context) {
    final colors = UnifiedSwapDesign.colors(context);
    final type = UnifiedSwapDesign.typography(context);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        border: first ? null : Border(top: BorderSide(color: colors.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            question.toUpperCase(),
            style: type.labelSmall.copyWith(letterSpacing: .7),
          ),
          const SizedBox(height: 7),
          Text(answer, style: type.labelLarge),
          if (details case final details?) ...[
            const SizedBox(height: 5),
            Text(details, style: type.bodyLarge.copyWith(fontSize: 15)),
          ],
          if (child case final child?) ...[const SizedBox(height: 8), child],
        ],
      ),
    );
  }
}

class UnifiedSwapSkeleton extends StatefulWidget {
  const UnifiedSwapSkeleton({
    this.height = 18,
    this.width,
    this.radius = 10,
    super.key,
  });

  final double height;
  final double? width;
  final double radius;

  @override
  State<UnifiedSwapSkeleton> createState() => _UnifiedSwapSkeletonState();
}

class _UnifiedSwapSkeletonState extends State<UnifiedSwapSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = UnifiedSwapDesign.colors(context);
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.radius),
            gradient: LinearGradient(
              begin: Alignment(-1.5 + _controller.value * 3, 0),
              end: Alignment(-.5 + _controller.value * 3, 0),
              colors: [
                colors.surfaceHigh,
                colors.surfaceHighest,
                colors.surfaceHigh,
              ],
            ),
          ),
        );
      },
    );
  }
}

class UnifiedSwapDisclosure extends StatelessWidget {
  const UnifiedSwapDisclosure({
    required this.title,
    required this.child,
    this.initiallyExpanded = false,
    super.key,
  });

  final String title;
  final Widget child;
  final bool initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    final colors = UnifiedSwapDesign.colors(context);
    final geometry = UnifiedSwapDesign.geometry(context);
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: Material(
        color: colors.surface,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: colors.controlBorder),
          borderRadius: geometry.borderRadius14,
        ),
        clipBehavior: Clip.antiAlias,
        child: ExpansionTile(
          initiallyExpanded: initiallyExpanded,
          tilePadding: const EdgeInsets.symmetric(horizontal: 14),
          childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
          title: Text(
            title,
            style: UnifiedSwapDesign.typography(context).labelLarge,
          ),
          children: [child],
        ),
      ),
    );
  }
}

class UnifiedSwapPickerSheet extends StatelessWidget {
  const UnifiedSwapPickerSheet({
    required this.title,
    required this.child,
    this.subtitle,
    this.showDragHandle = true,
    this.fillAvailable = false,
    super.key,
  });

  final String title;
  final String? subtitle;
  final Widget child;
  final bool showDragHandle;
  final bool fillAvailable;

  @override
  Widget build(BuildContext context) {
    final colors = UnifiedSwapDesign.colors(context);
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
    return SafeArea(
      child: Material(
        color: colors.surfaceRaised,
        child: Padding(
          padding: EdgeInsets.fromLTRB(18, 12, 18, 24 + keyboardInset),
          child: Column(
            mainAxisSize: fillAvailable ? MainAxisSize.max : MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (showDragHandle) ...[
                Center(
                  child: Container(
                    width: 44,
                    height: 4,
                    decoration: BoxDecoration(
                      color: colors.borderStrong,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Focus(
                          autofocus: true,
                          child: Semantics(
                            header: true,
                            child: Text(
                              title,
                              style: UnifiedSwapDesign.typography(
                                context,
                              ).sectionTitle,
                            ),
                          ),
                        ),
                        if (subtitle case final subtitle?) ...[
                          const SizedBox(height: 3),
                          Text(
                            subtitle,
                            style: UnifiedSwapDesign.typography(
                              context,
                            ).bodyMedium,
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  IconButton(
                    onPressed: () => completeUnifiedSwapPicker(context),
                    tooltip: MaterialLocalizations.of(
                      context,
                    ).closeButtonTooltip,
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Flexible(child: child),
            ],
          ),
        ),
      ),
    );
  }
}

/// Hosts prototype pickers as an in-flow surface. Narrow viewports replace the
/// form with a full content sheet; desktop keeps the form visible beside a
/// non-modal panel. Confirmation dialogs remain regular modal routes.
class UnifiedSwapPickerHost extends StatefulWidget {
  const UnifiedSwapPickerHost({
    required this.child,
    this.onPresentationChanged,
    super.key,
  });

  final Widget child;
  final ValueChanged<bool>? onPresentationChanged;

  static _UnifiedSwapPickerHostState? _stateOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<_UnifiedSwapPickerHostScope>()
      ?.state;

  static void dismiss(BuildContext context) =>
      _stateOf(context)?._complete(null);

  @override
  State<UnifiedSwapPickerHost> createState() => _UnifiedSwapPickerHostState();
}

class _UnifiedSwapPickerHostState extends State<UnifiedSwapPickerHost> {
  _UnifiedSwapPickerRequest? _request;

  Future<T?> present<T>({
    required String title,
    String? subtitle,
    required WidgetBuilder builder,
  }) {
    final replacingRequest = _request != null;
    _complete(null, notifyPresentation: false);
    final completer = Completer<Object?>();
    final previousFocus = FocusManager.instance.primaryFocus;
    setState(() {
      _request = _UnifiedSwapPickerRequest(
        title: title,
        subtitle: subtitle,
        builder: builder,
        completer: completer,
        previousFocus: previousFocus,
      );
    });
    if (!replacingRequest) widget.onPresentationChanged?.call(true);
    return completer.future.then((value) => value as T?);
  }

  void _complete(Object? value, {bool notifyPresentation = true}) {
    final request = _request;
    if (request == null) return;
    _request = null;
    if (mounted) setState(() {});
    if (notifyPresentation) widget.onPresentationChanged?.call(false);
    if (!request.completer.isCompleted) request.completer.complete(value);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final focus = request.previousFocus;
      if (focus != null && focus.canRequestFocus) focus.requestFocus();
    });
  }

  @override
  void dispose() {
    final request = _request;
    if (request != null && !request.completer.isCompleted) {
      request.completer.complete(null);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scope = _UnifiedSwapPickerHostScope(state: this, child: widget.child);
    final request = _request;
    if (request == null) return scope;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _complete(null);
      },
      child: _UnifiedSwapPickerHostScope(
        state: this,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final desktop =
                constraints.maxWidth >= UnifiedSwapDesign.desktopBreakpoint;
            final sheet = CallbackShortcuts(
              bindings: {
                const SingleActivator(LogicalKeyboardKey.escape): () =>
                    _complete(null),
              },
              child: _UnifiedSwapPickerCompletionScope(
                onComplete: _complete,
                child: UnifiedSwapPickerSheet(
                  title: request.title,
                  subtitle: request.subtitle,
                  showDragHandle: !desktop,
                  fillAvailable: true,
                  child: request.builder(context),
                ),
              ),
            );
            if (!desktop) return sheet;
            final panelWidth = (constraints.maxWidth * .42).clamp(360.0, 520.0);
            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: UnifiedSwapDesign.detailWidth + 80,
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(child: widget.child),
                      const SizedBox(width: 24),
                      SizedBox(
                        width: panelWidth,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(20),
                          child: sheet,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _UnifiedSwapPickerRequest {
  const _UnifiedSwapPickerRequest({
    required this.title,
    required this.builder,
    required this.completer,
    required this.previousFocus,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final WidgetBuilder builder;
  final Completer<Object?> completer;
  final FocusNode? previousFocus;
}

class _UnifiedSwapPickerHostScope extends InheritedWidget {
  const _UnifiedSwapPickerHostScope({
    required this.state,
    required super.child,
  });

  final _UnifiedSwapPickerHostState state;

  @override
  bool updateShouldNotify(_UnifiedSwapPickerHostScope oldWidget) =>
      oldWidget.state != state;
}

class _UnifiedSwapPickerCompletionScope extends InheritedWidget {
  const _UnifiedSwapPickerCompletionScope({
    required this.onComplete,
    required super.child,
  });

  final ValueChanged<Object?> onComplete;

  @override
  bool updateShouldNotify(_UnifiedSwapPickerCompletionScope oldWidget) =>
      oldWidget.onComplete != onComplete;
}

void completeUnifiedSwapPicker<T>(BuildContext context, [T? value]) {
  final scope = context
      .dependOnInheritedWidgetOfExactType<_UnifiedSwapPickerCompletionScope>();
  if (scope != null) {
    scope.onComplete(value);
    return;
  }
  Navigator.maybePop<T>(context, value);
}

Future<T?> showUnifiedSwapPicker<T>({
  required BuildContext context,
  required String title,
  String? subtitle,
  required WidgetBuilder builder,
}) {
  final host = UnifiedSwapPickerHost._stateOf(context);
  if (host != null) {
    return host.present<T>(title: title, subtitle: subtitle, builder: builder);
  }
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: false,
    backgroundColor: Colors.transparent,
    constraints: const BoxConstraints(maxWidth: 640),
    builder: (sheetContext) => UnifiedSwapPickerSheet(
      title: title,
      subtitle: subtitle,
      child: builder(sheetContext),
    ),
  );
}

String unifiedSwapNetworkLabel(
  BuildContext context,
  UnifiedSwapAssetIdentity asset,
) {
  return switch ((asset.chainFamily, asset.chainId)) {
    (UnifiedSwapChainFamily.evm, '1') => 'Ethereum',
    (UnifiedSwapChainFamily.evm, '137') => 'Polygon',
    (UnifiedSwapChainFamily.evm, '42161') => 'Arbitrum One',
    (UnifiedSwapChainFamily.evm, '10') => 'Optimism',
    (UnifiedSwapChainFamily.evm, '56') => 'BNB Smart Chain',
    (UnifiedSwapChainFamily.tron, _) => 'Tron',
    (UnifiedSwapChainFamily.utxo, _) when asset.ticker.toUpperCase() == 'BTC' =>
      'Bitcoin',
    (_, final chainId) => unifiedSwapText(
      context,
      'network.unknown',
      'Network {chainId}',
      namedArgs: {'chainId': chainId},
    ),
  };
}

String unifiedSwapShortIdentity(String value, {int leading = 6, int tail = 4}) {
  final trimmed = value.trim();
  if (trimmed.length <= leading + tail + 1) return trimmed;
  return '${trimmed.substring(0, leading)}…${trimmed.substring(trimmed.length - tail)}';
}

/// Uses the wallet's normal Easy Localization catalog while retaining a
/// readable fallback in isolated previews and widget tests.
String unifiedSwapText(
  BuildContext context,
  String key,
  String fallback, {
  Map<String, String>? namedArgs,
}) {
  if (EasyLocalization.of(context) == null) {
    if (namedArgs == null) return fallback;
    var resolved = fallback;
    for (final entry in namedArgs.entries) {
      resolved = resolved.replaceAll('{${entry.key}}', entry.value);
    }
    return resolved;
  }
  return 'unifiedSwap.$key'.tr(context: context, namedArgs: namedArgs);
}

String _initials(String value) {
  final cleaned = value.trim().toUpperCase();
  if (cleaned.isEmpty) return '?';
  return cleaned.substring(0, cleaned.length > 3 ? 3 : cleaned.length);
}

String _chainInitial(UnifiedSwapAssetIdentity asset) {
  return switch (asset.chainFamily) {
    UnifiedSwapChainFamily.evm => 'E',
    UnifiedSwapChainFamily.tron => 'T',
    UnifiedSwapChainFamily.utxo => '₿',
    UnifiedSwapChainFamily.solana => 'S',
    UnifiedSwapChainFamily.sui => 'S',
    UnifiedSwapChainFamily.other || UnifiedSwapChainFamily.unknown => '?',
  };
}
