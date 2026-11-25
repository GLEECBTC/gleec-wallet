import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:komodo_ui_kit/komodo_ui_kit.dart';
import 'package:qr_flutter/qr_flutter.dart'
    show QrErrorCorrectLevel, QrImageView;
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/shared/utils/utils.dart';

class TrezorNewAddressConfirmation extends StatelessWidget {
  const TrezorNewAddressConfirmation({
    required this.address,
    this.maxWidth = 300,
    super.key,
  });

  final String address;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final themeData = Theme.of(context);
    return Column(
      children: [
        Text(
          LocaleKeys.confirmOnTrezor.tr(),
          style: themeData.textTheme.titleLarge,
        ),
        const SizedBox(height: 24),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          // Dark modules on white in both themes: scanners need the contrast.
          child: QrImageView(
            data: address,
            backgroundColor: Colors.white,
            size: 200.0,
            errorCorrectionLevel: QrErrorCorrectLevel.H,
          ),
        ),
        const SizedBox(height: 24),
        UiTextFormField(
          readOnly: true,
          initialValue: address,
          inputContentPadding: const EdgeInsets.fromLTRB(12, 22, 0, 22),
          suffixIcon: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 20, maxHeight: 20),
            child: IconButton(
              padding: EdgeInsets.zero,
              hoverColor: Colors.transparent,
              highlightColor: Colors.transparent,
              onPressed: () => copyToClipBoard(context, address),
              icon: const Icon(Icons.copy),
            ),
          ),
        ),
      ],
    );
  }
}
