import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:web_dex/views/common/wallet_access/wallet_access_feedback.dart';
import 'package:web_dex/views/settings/widgets/security_settings/security_section_card.dart';

/// What the camera gave back.
sealed class TransferScan {
  const TransferScan();
}

final class TransferScanned extends TransferScan {
  const TransferScanned(this.code);

  final String code;

  @override
  String toString() => 'TransferScanned(<redacted>)';
}

final class TransferScanCanceled extends TransferScan {
  const TransferScanCanceled();
}

/// Camera access is off for this app.
final class TransferScanDenied extends TransferScan {
  const TransferScanDenied();
}

/// The camera could not be used here.
final class TransferScanUnsupported extends TransferScan {
  const TransferScanUnsupported();
}

/// Opens the camera for one move code. [instruction] says which phone's
/// code to point it at. Injected so screens can be driven without a camera.
typedef QrScanner = Future<TransferScan> Function(
  BuildContext context,
  String instruction,
);

Future<TransferScan> scanTransferCode(
  BuildContext context,
  String instruction,
) async =>
    await Navigator.of(context).push<TransferScan>(
      MaterialPageRoute(
        builder: (_) => TransferScannerPage(instruction: instruction),
      ),
    ) ??
    const TransferScanCanceled();

/// A full-screen camera that reads QR codes only and stops at the first.
class TransferScannerPage extends StatefulWidget {
  const TransferScannerPage({required this.instruction, super.key});

  final String instruction;

  @override
  State<TransferScannerPage> createState() => _TransferScannerPageState();
}

class _TransferScannerPageState extends State<TransferScannerPage> {
  final _camera = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
    detectionSpeed: DetectionSpeed.noDuplicates,
  );
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    _camera.addListener(_onCameraState);
  }

  @override
  void dispose() {
    _camera.removeListener(_onCameraState);
    unawaited(_camera.dispose());
    super.dispose();
  }

  void _onCameraState() {
    final error = _camera.value.error;
    if (error == null) return;
    _finish(
      error.errorCode == MobileScannerErrorCode.permissionDenied
          ? const TransferScanDenied()
          : const TransferScanUnsupported(),
    );
  }

  void _onDetect(BarcodeCapture capture) {
    for (final barcode in capture.barcodes) {
      final code = barcode.rawValue;
      if (code != null && code.isNotEmpty) {
        _finish(TransferScanned(code));
        return;
      }
    }
  }

  void _finish(TransferScan result) {
    if (_finished || !mounted) return;
    _finished = true;
    unawaited(_camera.stop());
    Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text('walletMoveScannerTitle'.tr()),
        titleTextStyle: theme.textTheme.bodyMedium?.copyWith(
          fontWeight: FontWeight.w700,
          fontSize: 16,
        ),
        foregroundColor: theme.textTheme.bodyMedium?.color,
        elevation: 0,
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            controller: _camera,
            onDetect: _onDetect,
            // Errors are reported to the screen that asked, by result.
            errorBuilder: (context, _) => const SizedBox.shrink(),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 24,
            child: SafeArea(
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  widget.instruction,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Why the camera did not scan, and the way back to it where there is one.
class TransferCameraNotice extends StatelessWidget {
  const TransferCameraNotice({
    required this.denied,
    required this.onOpenSettings,
    super.key,
  });

  /// Access is off, as opposed to a camera that cannot be used here.
  final bool denied;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      WalletAccessNotice(
        key: const Key('transfer-camera-notice'),
        text: denied
            ? 'walletMoveCameraDenied'.tr()
            : 'walletMoveCameraUnavailable'.tr(),
        tone: WalletAccessTone.error,
      ),
      if (denied) ...[
        const SizedBox(height: 8),
        SecuritySecondaryButton(
          key: const Key('transfer-open-settings'),
          text: 'walletMoveOpenSettings'.tr(),
          onPressed: onOpenSettings,
        ),
      ],
    ],
  );
}
