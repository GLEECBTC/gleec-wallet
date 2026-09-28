import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/shared/utils/utils.dart';
import 'package:web_dex/views/swap/common/swap_palette.dart';
import 'package:web_dex/views/swap/common/swap_widgets.dart';

/// Opens [url], or shows a [SwapLinkFailedDialog] if the device cannot.
///
/// A dialog rather than a snack bar: over the evidence sheet, which covers a
/// phone's screen, a snack bar would sit underneath it.
Future<void> openSwapLink(
  BuildContext context,
  String url, {
  String? details,
}) async {
  bool opened;
  try {
    // No `canLaunchUrl` first: Android 11+ answers false for mailto: unless
    // the manifest declares it, while the launch itself works.
    opened = await launchUrl(Uri.parse(url));
  } on Object {
    opened = false;
  }
  if (opened || !context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (_) => SwapLinkFailedDialog(url: url, details: details),
  );
}

/// Says [url] could not be opened, offering it (or a mailto address) to copy,
/// and [details] too when given.
class SwapLinkFailedDialog extends StatefulWidget {
  const SwapLinkFailedDialog({required this.url, this.details, super.key});

  final String url;
  final String? details;

  @override
  State<SwapLinkFailedDialog> createState() => _SwapLinkFailedDialogState();
}

class _SwapLinkFailedDialogState extends State<SwapLinkFailedDialog> {
  /// The value copied last. Confirmed here, because the page's snack bar can
  /// be hidden under the evidence sheet.
  String? _copied;

  Future<void> _copy(String value, String confirmation) async {
    if (!await copyToClipBoard(context, value, confirmation) || !mounted) {
      return;
    }
    setState(() => _copied = value);
    swapAnnounce(context, confirmation);
  }

  @override
  Widget build(BuildContext context) {
    final palette = SwapPalette.of(context);
    final email = _addressOf(widget.url);
    final value = email ?? widget.url;
    final label = email == null
        ? LocaleKeys.swapLinkLabel.tr()
        : LocaleKeys.swapEmailLabel.tr();
    final copiedValue = LocaleKeys.swapCopied.tr(args: [label]);
    final details = widget.details;
    return AlertDialog(
      scrollable: true,
      constraints: const BoxConstraints(minWidth: 280, maxWidth: 560),
      backgroundColor: palette.surfaceRaised,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      title: Text(
        email == null
            ? LocaleKeys.swapLinkFailedTitle.tr()
            : LocaleKeys.swapEmailFailedTitle.tr(),
        style: SwapText.heading(context),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            email == null
                ? LocaleKeys.swapLinkFailedBody.tr()
                : LocaleKeys.swapEmailFailedBody.tr(),
            style: SwapText.body(context),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Semantics(
                  label: '$label: $value',
                  excludeSemantics: true,
                  child: SelectableText(value, style: SwapText.code(context)),
                ),
              ),
              const SizedBox(width: 8),
              SwapLinkButton(
                label: LocaleKeys.swapCopy.tr(),
                onPressed: () => _copy(value, copiedValue),
              ),
            ],
          ),
          if (_copied == value)
            Text(
              copiedValue,
              style: SwapText.small(
                context,
              ).copyWith(color: palette.toneColor(SwapTone.success)),
            ),
        ],
      ),
      actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      actions: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (details != null) ...[
              SwapButton(
                label: _copied == details
                    ? LocaleKeys.swapEvidenceCopiedAll.tr()
                    : LocaleKeys.swapEvidenceCopyAll.tr(),
                variant: SwapButtonVariant.secondary,
                icon: Icons.content_copy_rounded,
                onPressed: () =>
                    _copy(details, LocaleKeys.swapEvidenceCopiedAll.tr()),
              ),
              const SizedBox(height: 10),
            ],
            SwapButton(
              label: LocaleKeys.close.tr(),
              variant: SwapButtonVariant.secondary,
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      ],
    );
  }
}

/// The address a `mailto:` [url] writes to, when it names one.
String? _addressOf(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null || !uri.isScheme('mailto') || uri.path.isEmpty) return null;
  try {
    return Uri.decodeComponent(uri.path);
  } on Object {
    return null;
  }
}
