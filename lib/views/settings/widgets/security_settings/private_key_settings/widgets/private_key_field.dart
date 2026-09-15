import 'package:flutter/material.dart';

import 'private_key_monospace.dart';

/// A labelled, selectable piece of key material.
///
/// Label and value are merged into one semantics node so a screen reader
/// announces "Address, bc1q..." rather than two unrelated fragments.
class PrivateKeyField extends StatelessWidget {
  const PrivateKeyField({
    required this.label,
    required this.value,
    this.monospace = true,
    super.key,
  });

  final String label;
  final String value;
  final bool monospace;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return MergeSemantics(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 2),
            SelectableText(
              value,
              style: monospace
                  ? privateKeyMonospaceStyle(context)
                  : theme.textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}
