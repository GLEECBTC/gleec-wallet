import 'package:flutter/material.dart';
import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';
import 'package:komodo_ui_kit/komodo_ui_kit.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';

/// Dialog to display the results of a pubkey unban operation.
///
/// Shows the number of pubkeys that were unbanned, still banned, and those
/// that were not banned in the first place. Provides a clear summary of
/// the operation results.
class UnbanPubkeysResultDialog extends StatelessWidget {
  const UnbanPubkeysResultDialog({super.key, required this.result});

  final UnbanPubkeysResult result;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return AlertDialog(
      title: Text(LocaleKeys.unbanPubkeysResults.tr()),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildResultSection(
              context,
              title: LocaleKeys.unbannedPubkeys.plural(result.unbanned.length),
              count: result.unbanned.length,
              items: result.unbanned.entries.toList(),
              color: palette.success,
            ),
            const SizedBox(height: 16),
            _buildResultSection(
              context,
              title: LocaleKeys.stillBannedPubkeys.tr(),
              count: result.stillBanned.length,
              items: result.stillBanned.entries.toList(),
              color: palette.warning,
            ),
            if (result.wereNotBanned.isNotEmpty) ...[
              const SizedBox(height: 16),
              _buildResultSection(
                context,
                title: LocaleKeys.wereNotBannedPubkeys.tr(),
                count: result.wereNotBanned.length,
                items: result.wereNotBanned
                    .map((address) => MapEntry(address, null))
                    .toList(),
                color: palette.textTertiary,
              ),
            ],
          ],
        ),
      ),
      actions: [
        UiPrimaryButton(
          onPressed: () => Navigator.of(context).pop(),
          text: LocaleKeys.close.tr(),
        ),
      ],
    );
  }

  Widget _buildResultSection(
    BuildContext context, {
    required String title,
    required int count,
    required List<MapEntry<String, BannedPubkeyInfo?>> items,
    required Color color,
  }) {
    final palette = AppPalette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(6),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '$title ($count)',
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ],
        ),
        if (items.isNotEmpty) ...[
          const SizedBox(height: 8),
          Container(
            constraints: const BoxConstraints(maxHeight: 200),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: items.length,
              itemBuilder: (context, index) {
                final item = items[index];
                final address = item.key;
                final info = item.value;

                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        address,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      if (info != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          '${LocaleKeys.pubkeyType.tr()}: ${info.type}',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: palette.textTertiary),
                        ),
                        Text(
                          '${LocaleKeys.reason.tr()}: ${info.reason}',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: palette.textTertiary),
                        ),
                      ],
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ],
    );
  }
}
