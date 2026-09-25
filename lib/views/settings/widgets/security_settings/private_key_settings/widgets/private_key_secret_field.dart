import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';

import 'private_key_monospace.dart';

/// A secret on this screen that must never be shown by accident.
///
/// Used for the private key itself, and for a shielded asset's viewing key -
/// which cannot spend, but decrypts the whole incoming and outgoing note
/// history of the account, so revealing it destroys exactly the confidentiality
/// the user holds a shielded asset for.
///
/// While hidden it renders a fixed-length run of bullets as plain [Text]. The
/// masking is at the *content* level rather than the style level, so the key
/// is genuinely absent from the widget tree - a style-level mask would leave
/// it readable to anything walking the tree, and would quietly satisfy the
/// test that asserts no key is on screen before reveal. The run is a fixed
/// length so it leaks nothing about the real key, and it is not selectable,
/// because copying eight bullet characters helps nobody.
class PrivateKeySecretField extends StatelessWidget {
  const PrivateKeySecretField({
    required this.privateKey,
    required this.revealed,
    this.label,
    super.key,
  });

  final String privateKey;
  final bool revealed;

  /// Defaults to the private-key label when omitted.
  final String? label;

  static const _maskLength = 44;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                label ?? LocaleKeys.privateKeyExportPrivateKeyLabel.tr(),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              if (!revealed) ...[
                const SizedBox(width: 6),
                Icon(
                  Icons.lock_outline,
                  size: 14,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ],
            ],
          ),
          const SizedBox(height: 6),
          AnimatedSize(
            duration: const Duration(milliseconds: 150),
            alignment: Alignment.topLeft,
            child: revealed
                ? SelectableText(
                    privateKey,
                    style: privateKeyMonospaceStyle(context),
                  )
                : Semantics(
                    label: LocaleKeys.privateKeyExportKeyHidden.tr(),
                    child: ExcludeSemantics(
                      child: Text(
                        '•' * _maskLength,
                        maxLines: 2,
                        style: privateKeyMonospaceStyle(context),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
