import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class AutoScrollText extends StatefulWidget {
  const AutoScrollText({
    required this.text,
    this.style,
    this.textAlign,
    this.isSelectable = false,
    super.key,
  });

  final String text;
  final TextStyle? style;
  final bool isSelectable;

  final TextAlign? textAlign;

  @override
  State<AutoScrollText> createState() => _AutoScrollTextState();
}

class _AutoScrollTextState extends State<AutoScrollText>
    with SingleTickerProviderStateMixin {
  /// To avoid unnecessary animations, we only animate the text if it's wider
  /// than the parent's constraints by this threshold.
  static const double _kAnimationThresholdWidth = 5;

  static const Duration _kPauseBeforeRepeat = Duration(seconds: 10);

  static const Duration _kInitialPause = Duration(seconds: 2);

  static const Duration _kPauseBeforeReverse = Duration(seconds: 3);

  static const Duration _kMovingDuration = Duration(seconds: 4);

  // TODO: Add a "Debug animations" settings option to the app settings.
  static bool animationDebugMode = false;

  late final AnimationController _controller;

  Size? _lastAvailableSize;

  @override
  void initState() {
    _controller = AnimationController(vsync: this);

    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      // TODO: Possible future refactoring to only run animation if the text
      //  animation is shown (`isTextAnimatable`).
      unawaited(runAnimation());
    });
  }

  /// Updates the animations/calculations based on the available size and
  /// stores the size to recognise when the available size changes.
  void computeAnimation(Size size) {
    if (!mounted) return;
    final textWidth = calculateTextSize().width;
    final parentWidth = size.width;

    final animation = getAnimation(
      textWidth: textWidth,
      parentWidth: parentWidth,
      controller: _controller,
    );

    if (animation == null && _animation == null) {
      return;
    }

    setState(() {
      _animation = animation;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isTextAnimatable = _animation != null;

    // TODO: Initially the text overflow shows as faded, but we have to disable
    // the edge-fade when the text starts animating. There is an initial "jump"
    // from faded to non-faded text when the animation starts. This is not
    // ideal, but it's not a big issue. In the future, see if there is an
    // efficient way to always show the overflow edge as faded. E.g. Container
    // gradient decoration. NB: Don't assume that text is always LTR.
    final overflow = isTextAnimatable
        ? renderedTextStyle.overflow
        : widget.style?.overflow ?? TextOverflow.fade;

    final textWidget = _TextDisplay(
      text: widget.text,
      style: renderedTextStyle,
      textAlign: widget.textAlign,
      isSelectable: widget.isSelectable,
      isTextAnimatable: isTextAnimatable,
      overflow: overflow,
    );

    return LayoutBuilder(
      key: const ValueKey('AutoScrollText-LayoutBuilder'),
      builder: (context, constraints) {
        final availableSize = constraints.biggest;

        final didAvailableSizeChange = _lastAvailableSize != availableSize;

        _lastAvailableSize = availableSize;

        if (didAvailableSizeChange && isTextAnimatable) {
          WidgetsBinding.instance.addPostFrameCallback(
            (_) => computeAnimation(constraints.biggest),
          );
        }

        if (!isTextAnimatable) {
          return ClipRRect(
            key: const ValueKey('AutoScrollText-ClipRRect'),
            child: textWidget,
          );
        }

        return Container(
          key: const ValueKey('AutoScrollText-Container'),
          clipBehavior: Clip.hardEdge,
          decoration: BoxDecoration(
            color: isTextAnimatable && animationDebugMode
                ? Colors.purple.withValues(alpha: 0.5)
                : null,
          ),
          width: double.infinity,
          child: SlideTransition(position: _animation!, child: textWidget),
        );
      },
    );
  }

  /// The predicted size of the text based on the current text style.
  ///
  /// This is far more efficient and cleaner than determining the size of the
  /// text by actually laying it out. There may be minor differences between
  /// the calculated vs actual size, but it's not significant.
  /// [_kAnimationThresholdWidth] is used to account for these differences.
  Size calculateTextSize() {
    if (!mounted || widget.text.isEmpty) {
      return Size.zero;
    }

    // There's a bug in Flutter web where the text painter's width is slightly
    // narrower than the actual text width. Issue may be related to a
    // known bug here: https://github.com/flutter/flutter/issues/125582
    final width = textWidth * (kIsWeb ? 1.04 : 1);

    // We are returning double.infinity for the height because we don't need
    // to calculate the height, but we may want to implement this in the future
    // for vertical scrolling text.
    return Size(width, double.infinity);
  }

  double? _textWidth;

  double get textWidth {
    if (_textWidth != null) return _textWidth!;

    _textWidth = TextPainter.computeWidth(
      text: TextSpan(text: widget.text, style: renderedTextStyle),
      textDirection: TextDirection.ltr,
      textAlign:
          widget.textAlign ??
          // DefaultTextStyle.of(context).textAlign ??
          TextAlign.start,
      maxLines: 1,
      textWidthBasis: TextWidthBasis.longestLine,
    );

    return _textWidth!;
  }

  Future<void> runAnimation() async {
    await Future.delayed(_kInitialPause);
    if (!mounted) return;

    computeAnimation(_lastAvailableSize!);

    while (mounted) {
      try {
        await _controller.animateTo(1, duration: _kMovingDuration);

        await Future.delayed(_kPauseBeforeReverse);

        if (!mounted) break;

        await _controller.animateBack(0, duration: _kMovingDuration);

        await Future.delayed(_kPauseBeforeRepeat);
      } catch (e) {
        // There may be a brief period after the widget is unmounted and/or
        // the conttoller is disposed of, but before the animation is stopped.
        // These errors can be safely ignored.

        assert(
          !mounted,
          'AutoScrollText animation is disposed of while Widget is'
          ' still alive (mounted). This should not happen.',
        );
      }
    }
  }

  Animation<Offset>? _animation;

  static Animation<Offset>? getAnimation({
    required double textWidth,
    required double parentWidth,
    required AnimationController controller,
  }) {
    const begin = Offset.zero;

    // We only want to animate the text if it's longer than the parent widget.
    // The threshold is to avoid unnecessary animations where text is only
    // slightly longer than the parent widget.

    final isTextWiderThanParentByThreshold =
        textWidth > parentWidth + _kAnimationThresholdWidth;

    if (!isTextWiderThanParentByThreshold) return null;

    final overflowAmount = textWidth - parentWidth;
    final overflowFraction = overflowAmount / parentWidth;
    final overflowOffset = Offset(-1 * overflowFraction, 0);

    final animation = Tween<Offset>(
      begin: begin,
      end: overflowOffset,
    ).animate(controller);

    return animation;
  }

  /// The memoized [TextStyle] from [renderedTextStyle] which is the input
  /// text style with certain properties overridden to make sure that the text
  /// is rendered correctly.
  ///
  /// NB: This is not intended to be referenced in the build method because it
  /// is relies on the build method to be called in order to be memoized.
  TextStyle? _renderedTextStyle;

  TextStyle get renderedTextStyle {
    if (_renderedTextStyle != null) return _renderedTextStyle!;

    final mustHighlightBackground = animationDebugMode;

    final widgetStyle = (widget.style ?? DefaultTextStyle.of(context).style);

    // We have to override certain properties of the style to ensure that the
    // overflow text is rendered correctly.
    TextStyle style = widgetStyle.copyWith(overflow: TextOverflow.visible);

    if (mustHighlightBackground) {
      style = style.copyWith(
        backgroundColor: Colors.red.withValues(alpha: 0.3),
      );
    }

    return _renderedTextStyle = style;
  }

  /// Clears all the memoized ("cached") state values. NB: Does not call
  /// setState() to rebuild the widget.
  void _resetMemoizedValues() {
    _animation = null;
    _lastAvailableSize = null;
    _textWidth = null;
    _renderedTextStyle = null;
  }

  @override
  void didUpdateWidget(AutoScrollText oldWidget) {
    super.didUpdateWidget(oldWidget);

    final didWidgetValuesChange =
        oldWidget.text != widget.text ||
        oldWidget.style != widget.style ||
        oldWidget.textAlign != widget.textAlign;

    if (didWidgetValuesChange) {
      _resetMemoizedValues();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}

class _TextDisplay extends StatelessWidget {
  final String text;
  final TextStyle style;
  final TextAlign? textAlign;
  final bool isSelectable;
  final bool isTextAnimatable;
  final TextOverflow? overflow;

  const _TextDisplay({
    required this.text,
    required this.style,
    this.textAlign,
    this.isSelectable = false,
    this.isTextAnimatable = false,
    required this.overflow,
    Key? key,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (isSelectable) {
      return SelectableText(
        text,
        style: style,
        textAlign: textAlign,
        maxLines: 1,
      );
    } else {
      return Text(
        text,
        style: style,
        textAlign: textAlign,
        overflow: overflow,
        softWrap: false,
        maxLines: 1,
        textWidthBasis: TextWidthBasis.longestLine,
      );
    }
  }
}
