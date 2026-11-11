import 'dart:io';

import 'package:flutter/foundation.dart';

/// Explicit local development input. Contents never enter the asset bundle.
/// Release builds cannot use this path, including with benchmark defines set.
Future<String?> loadDebugWalletSource() async {
  const path = String.fromEnvironment('DEBUG_WALLET_FILE');
  if (kReleaseMode || path.isEmpty) return null;
  try {
    return await File(path).readAsString();
  } on Object {
    return null;
  }
}
