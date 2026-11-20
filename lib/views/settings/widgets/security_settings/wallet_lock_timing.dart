import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:web_dex/services/wallet_access/wallet_lock_policy.dart';
import 'package:web_dex/views/settings/widgets/security_settings/security_section_card.dart';

/// How long the app may be away before the wallet locks: one choice out of
/// [walletLockGraceOptions], announced as a radio group.
class WalletLockTimingChoice extends StatelessWidget {
  const WalletLockTimingChoice({
    required this.selectedSeconds,
    required this.onSelected,
    super.key,
  });

  final int selectedSeconds;
  final ValueChanged<int> onSelected;

  static String? _labelKey(Duration option) => switch (option.inSeconds) {
    0 => 'authLockImmediately',
    30 => 'authLockThirtySeconds',
    300 => 'authLockFiveMinutes',
    900 => 'authLockFifteenMinutes',
    _ => null,
  };

  @override
  Widget build(BuildContext context) {
    final options = [
      for (final option in walletLockGraceOptions)
        if (_labelKey(option) case final key?) (option.inSeconds, key.tr()),
    ];
    assert(options.length == walletLockGraceOptions.length);
    return RadioGroup<int>(
      groupValue: selectedSeconds,
      onChanged: (seconds) {
        if (seconds != null) onSelected(seconds);
      },
      // The section paints its own surface, so hover and focus highlights
      // need a material of their own to show on.
      child: Material(
        type: MaterialType.transparency,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final largeText = MediaQuery.textScalerOf(context).scale(1) > 1.5;
            final columns = largeText || constraints.maxWidth < 330
                ? 1
                : constraints.maxWidth < 720
                ? 2
                : 4;
            const gap = 8.0;
            // Rounded down so a rounding error never wraps the last column.
            final width =
                ((constraints.maxWidth - gap * (columns - 1)) / columns)
                    .floorToDouble();
            return Wrap(
              spacing: gap,
              children: [
                for (final (seconds, label) in options)
                  SizedBox(
                    width: width,
                    child: RadioListTile<int>(
                      value: seconds,
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      horizontalTitleGap: 4,
                      activeColor: Theme.of(context).colorScheme.primary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      title: Text(
                        label,
                        style: SecuritySectionText.body(context),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}
