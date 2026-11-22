import 'dart:ui' show AppLifecycleState;

import 'package:flutter/foundation.dart';

/// How long the app may be away before the wallet asks to be unlocked again.
/// Sensitive screens close at once whatever the choice.
const walletLockGraceOptions = <Duration>[
  Duration.zero,
  Duration(seconds: 30),
  Duration(minutes: 5),
  Duration(minutes: 15),
];

/// The choice applied until the user picks one.
const walletLockGraceDefault = Duration(seconds: 30);

/// The offered choice stored as [seconds], or the default for anything else.
Duration walletLockGraceFromSeconds(Object? seconds) =>
    walletLockGraceOptions.firstWhere(
      (option) => option.inSeconds == seconds,
      orElse: () => walletLockGraceDefault,
    );

/// Whether losing input focus alone means the user is leaving the app.
///
/// On a phone or tablet the app goes inactive just before the system takes
/// its app-switcher snapshot, so wallet content is covered then. On desktop
/// and web it only means another window was clicked: the wallet stays
/// readable beside it, and is covered once its window or tab is hidden.
bool get focusLossLeavesApp =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS);

/// Whether [state] means the user has left the app, by the rule above.
bool lifecycleLeavesApp(AppLifecycleState state) => switch (state) {
  AppLifecycleState.resumed => false,
  AppLifecycleState.inactive => focusLossLeavesApp,
  AppLifecycleState.hidden ||
  AppLifecycleState.paused ||
  AppLifecycleState.detached => true,
};
