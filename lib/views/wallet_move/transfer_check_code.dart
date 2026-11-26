import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

/// The eight digits both phones show for one reply. Anyone who saw the new
/// phone's code can seal a wallet of their own to it; the same digits on both
/// screens prove the reply came from the user's old phone.
///
/// Working them out takes a moment, so [code] is null at first; the box keeps
/// its size meanwhile, and the digits are read out when they arrive. Digits
/// already there when it first shows are left to the screen's own message.
class TransferCheckCode extends StatefulWidget {
  const TransferCheckCode({required this.code, super.key});

  final String? code;

  /// `1234 5678`: two groups are easier to compare across two screens.
  static String grouped(String code) =>
      code.length == 8 ? '${code.substring(0, 4)} ${code.substring(4)}' : code;

  /// Digit by digit, not as two large numbers.
  static String spoken(String code) =>
      'walletMoveCheckCodeSpoken'.tr(args: [code.split('').join(' ')]);

  @override
  State<TransferCheckCode> createState() => _TransferCheckCodeState();
}

class _TransferCheckCodeState extends State<TransferCheckCode> {
  @override
  void didUpdateWidget(TransferCheckCode oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.code == null && widget.code != null) _announceSoon();
  }

  void _announceSoon() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final code = widget.code;
      if (!mounted || code == null) return;
      SemanticsService.sendAnnouncement(
        View.of(context),
        TransferCheckCode.spoken(code),
        Directionality.of(context),
      ).ignore();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final code = widget.code;
    return Semantics(
      container: true,
      label: code == null
          ? 'walletMoveCheckCodeWorking'.tr()
          : TransferCheckCode.spoken(code),
      child: ExcludeSemantics(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: scheme.primary, width: 2),
          ),
          child: Column(
            children: [
              Text(
                'walletMoveCheckCodeLabel'.tr(),
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: scheme.onSurface,
                ),
              ),
              const SizedBox(height: 4),
              // The same height either way, so nothing below it jumps.
              SizedBox(
                height: MediaQuery.textScalerOf(context).scale(44),
                child: Center(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: code == null
                        ? Text(
                            'walletMoveCheckCodeWorking'.tr(),
                            key: const Key('transfer-check-code-working'),
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: scheme.onSurface,
                            ),
                          )
                        : Text(
                            TransferCheckCode.grouped(code),
                            key: const Key('transfer-check-code'),
                            style: theme.textTheme.headlineMedium?.copyWith(
                              fontSize: 32,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 2,
                              color: scheme.onSurface,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
