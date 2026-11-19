import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

/// Moving needs a camera on both phones, so it is offered on phones only.
bool get walletMoveSupportedHere =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS);

/// A code for another phone's camera: dark on white whatever the theme, with
/// a quiet zone, as large as the space allows.
class TransferQrCode extends StatelessWidget {
  const TransferQrCode({
    required this.data,
    required this.semanticLabel,
    this.maxSize = 360,
    super.key,
  });

  final String data;

  /// What the code is for. Its content is never read out.
  final String semanticLabel;
  final double maxSize;

  static const _quietZone = 16.0;

  /// Still readable from a hand's length; smaller only at very large text.
  static const _minSize = 160.0;

  /// Room the step's heading and check code need above the fold, at 1×
  /// text. Their height grows with the text, the code's does not.
  static const _chrome = 120.0;
  static const _textAtOneX = 240.0;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final textScale = MediaQuery.textScalerOf(context).scale(1);
      final byHeight =
          MediaQuery.sizeOf(context).height - _chrome - _textAtOneX * textScale;
      final side = [
        constraints.maxWidth,
        maxSize,
        math.max(byHeight, _minSize),
      ].reduce(math.min);
      return Center(
        child: Semantics(
          container: true,
          image: true,
          label: semanticLabel,
          child: ExcludeSemantics(
            child: Container(
              width: side,
              height: side,
              padding: const EdgeInsets.all(_quietZone),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
              child: QrImageView(
                data: data,
                size: side - 2 * _quietZone,
                padding: EdgeInsets.zero,
                backgroundColor: Colors.white,
                // M survives a glare spot and still fits the longest reply.
                errorCorrectionLevel: QrErrorCorrectLevel.M,
                semanticsLabel: semanticLabel,
              ),
            ),
          ),
        ),
      );
    },
  );
}
