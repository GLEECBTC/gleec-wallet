import 'dart:async';

import 'package:flutter/material.dart';
import 'package:web_dex/views/swap/common/swap_palette.dart';
import 'package:web_dex/views/swap/motion/swap_motion.dart';

/// Placeholders for something still loading, with words for it: read out at
/// once to those who cannot see the placeholders shimmer, and shown to
/// everyone once the shimmer stops, when bare grey blocks would read as a
/// screen that failed.
class SwapLoadingStatus extends StatefulWidget {
  const SwapLoadingStatus({
    required this.label,
    required this.skeletons,
    super.key,
  });

  /// What is loading: "Loading this swap…".
  final String label;

  /// The placeholders, top to bottom.
  final List<Widget> skeletons;

  /// How long a `SwapSkeleton` shimmers before it holds still: two passes of
  /// 1.4 seconds.
  static const shimmer = Duration(milliseconds: 2800);

  @override
  State<SwapLoadingStatus> createState() => _SwapLoadingStatusState();
}

class _SwapLoadingStatusState extends State<SwapLoadingStatus> {
  Timer? _shimmering;
  bool _named = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_named) return;
    // With motion off nothing shimmers, so the words are there from the start.
    if (!SwapMotion.enabled(context)) {
      _shimmering?.cancel();
      _named = true;
      return;
    }
    _shimmering ??= Timer(SwapLoadingStatus.shimmer, () {
      if (mounted) setState(() => _named = true);
    });
  }

  @override
  void dispose() {
    _shimmering?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      liveRegion: true,
      label: widget.label,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ...widget.skeletons,
          // Under the placeholders, so its arrival moves none of them.
          if (_named)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: ExcludeSemantics(
                child: Text(
                  widget.label,
                  style: SwapText.small(context),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
