import 'package:flutter/widgets.dart';
import 'package:web_dex/features/unified_swap/infrastructure/unified_swap_config.dart';
import 'package:web_dex/features/unified_swap/presentation/unified_swap_shell.dart';
import 'package:web_dex/features/unified_swap/presentation/unified_swap_wallet_scope.dart';

/// The single production entry point for Unified Swap on every form factor.
///
/// Router shells must not assemble wallet-scoped route dependencies
/// independently. This root applies the same compile-time switches and SDK
/// composition to mobile, tablet, desktop, and web.
class UnifiedSwapCompositionRoot extends StatelessWidget {
  const UnifiedSwapCompositionRoot({this.config, super.key});

  final UnifiedSwapConfig? config;

  @override
  Widget build(BuildContext context) {
    final resolved = config ?? UnifiedSwapConfig.fromEnvironment();
    return UnifiedSwapSdkScope(
      config: resolved,
      child: UnifiedSwapShell(config: resolved),
    );
  }
}
