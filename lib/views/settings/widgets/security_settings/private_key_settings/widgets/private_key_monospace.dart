import 'package:flutter/material.dart';

/// Monospace styling for key material.
///
/// Addresses, public keys and private keys are compared character by
/// character; a proportional face makes that hostile, and the app's Manrope
/// body font is proportional.
TextStyle privateKeyMonospaceStyle(BuildContext context) =>
    (Theme.of(context).textTheme.bodyMedium ?? const TextStyle()).copyWith(
      fontFamily: 'monospace',
      fontFamilyFallback: const ['Courier New', 'Courier', 'monospace'],
      height: 1.5,
    );
