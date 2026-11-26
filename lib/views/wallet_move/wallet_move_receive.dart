import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:komodo_ui_kit/komodo_ui_kit.dart';
import 'package:web_dex/bloc/auth_bloc/auth_bloc.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/services/device/device_controls.dart';
import 'package:web_dex/services/wallet_move/wallet_move_types.dart';
import 'package:web_dex/services/wallet_transfer/wallet_transfer_secret.dart';
import 'package:web_dex/views/common/wallet_access/wallet_access_feedback.dart';
import 'package:web_dex/views/wallet_move/transfer_import_review.dart';
import 'package:web_dex/views/wallet_move/transfer_qr_code.dart';
import 'package:web_dex/views/wallet_move/transfer_scanner.dart';
import 'package:web_dex/views/wallet_move/transfer_widgets.dart';
import 'package:web_dex/views/wallet_move/wallet_move_failure_text.dart';

part 'wallet_move_receive_code.dart';

/// Why an opened wallet was let go before it was imported.
enum _Drop { codesDiffer, forSafety, noCheckCode }

/// The new phone's half of a move, opened from the import options: a code for
/// the old phone to scan, then the old phone's reply, then the review.
///
/// The offer's key lives only in this screen: renewed when it runs out and
/// forgotten when the screen closes. An opened wallet is kept only for the
/// review, and dropped if the app is left or the offer's time runs out first.
class WalletMoveReceive extends StatefulWidget {
  const WalletMoveReceive({
    required this.onCancel,
    this.scan = scanTransferCode,
    this.now = DateTime.now,
    super.key,
  });

  final VoidCallback onCancel;
  final QrScanner scan;
  final DateTime Function() now;

  @override
  State<WalletMoveReceive> createState() => _WalletMoveReceiveState();
}

class _WalletMoveReceiveState extends State<WalletMoveReceive>
    with WidgetsBindingObserver {
  late final WalletMoveProtocol _protocol;
  late final DeviceControls _device;
  WalletMoveOffer? _offer;
  Timer? _expiry;
  WalletTransferSecret? _secret;
  String? _checkCode;
  int _checkGeneration = 0;
  DateTime? _reviewDeadline;
  Timer? _reviewExpiry;

  /// An import is running: the bloc holds the wallet, so nothing is dropped.
  bool _importing = false;
  bool _scanning = false;
  bool _screenOn = false;

  /// How long each code lasts, for the note under it.
  int _lifetimeMinutes = 1;
  _CodeNotice? _notice;
  bool? _cameraDenied;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _protocol = context.read<WalletMoveProtocol>();
    _device =
        context.read<DeviceControls?>() ?? const MethodChannelDeviceControls();
    _replaceOffer();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _expiry?.cancel();
    _reviewExpiry?.cancel();
    _offer?.dispose();
    _offer = null;
    _secret = null;
    _keepScreenOn(false);
    super.dispose();
  }

  void _keepScreenOn(bool on) {
    if (_screenOn == on) return;
    _screenOn = on;
    unawaited(_device.keepScreenOn(on));
  }

  void _replaceOffer() {
    _expiry?.cancel();
    _offer?.dispose();
    final offer = _protocol.createOffer();
    _offer = offer;
    final left = offer.expiresAt.difference(widget.now());
    _lifetimeMinutes = (left.inSeconds / 60).ceil().clamp(1, 60);
    _expiry = Timer(left.isNegative ? Duration.zero : left, _onExpired);
    // The code waits on screen for the old phone's camera.
    _keepScreenOn(true);
  }

  bool get _offerExpired {
    final offer = _offer;
    return offer != null && !widget.now().isBefore(offer.expiresAt);
  }

  void _onExpired() {
    // A scan in progress reports the expiry itself when it returns.
    if (!mounted || _secret != null || _scanning) return;
    setState(() {
      _replaceOffer();
      _notice = _CodeNotice.renewed();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        // Timers stall in the background; a code that ran out is renewed.
        if (_offerExpired) _onExpired();
        _dropIfStale();
      case AppLifecycleState.inactive:
        break;
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        if (_secret != null && !_importing) _drop(_Drop.forSafety);
    }
  }

  /// The wallet is kept no longer than the offer it answered was valid.
  void _dropIfStale() {
    final deadline = _reviewDeadline;
    if (_secret == null || _importing || deadline == null) return;
    if (!widget.now().isBefore(deadline)) _drop(_Drop.forSafety);
  }

  void _drop(_Drop why) {
    if (!mounted) return;
    _reviewExpiry?.cancel();
    _checkGeneration++;
    setState(() {
      _secret = null;
      _checkCode = null;
      _reviewDeadline = null;
      _cameraDenied = null;
      _notice = switch (why) {
        _Drop.codesDiffer => _CodeNotice.discarded(),
        _Drop.forSafety => _CodeNotice.cleared(),
        _Drop.noCheckCode => _CodeNotice.noCheckCode(),
      };
      _replaceOffer();
    });
  }

  void _onImporting(bool importing) {
    _importing = importing;
    if (!importing) _dropIfStale();
  }

  Future<void> _scanReply() async {
    if (_scanning) return;
    _scanning = true;
    setState(() => _cameraDenied = null);
    final TransferScan result;
    try {
      result = await widget.scan(context, 'walletMoveScannerOldPhone'.tr());
    } finally {
      _scanning = false;
    }
    if (!mounted || _offer == null) return;
    switch (result) {
      case TransferScanned(:final code):
        _openReply(code);
      case TransferScanCanceled():
        if (_offerExpired) _onExpired();
      case TransferScanDenied():
        setState(() => _cameraDenied = true);
      case TransferScanUnsupported():
        setState(() => _cameraDenied = false);
    }
  }

  void _openReply(String reply) {
    final offer = _offer!;
    final Future<String> pending;
    final WalletTransferSecret secret;
    try {
      // Refuses a malformed reply before any work, and before the offer is
      // spent on it.
      pending = _protocol.checkCode(reply);
    } on WalletMoveException catch (error) {
      return _refuse(error.failure);
    }
    try {
      secret = offer.open(reply);
    } on WalletMoveException catch (error) {
      pending.ignore();
      return _refuse(error.failure);
    }
    _expiry?.cancel();
    offer.dispose();
    _offer = null;
    _keepScreenOn(false);
    final generation = ++_checkGeneration;
    final deadline = offer.expiresAt;
    final left = deadline.difference(widget.now());
    _reviewExpiry = Timer(left.isNegative ? Duration.zero : left, () {
      if (mounted) _dropIfStale();
    });
    setState(() {
      _secret = secret;
      _checkCode = null;
      _reviewDeadline = deadline;
      _notice = null;
    });
    pending.then(
      (code) {
        if (!mounted || generation != _checkGeneration) return;
        setState(() => _checkCode = code);
      },
      onError: (Object _) {
        if (!mounted || generation != _checkGeneration) return;
        // Without the digits nothing proves whose wallet this is.
        if (!_importing) _drop(_Drop.noCheckCode);
      },
    );
  }

  void _refuse(WalletMoveFailure failure) => setState(() {
    _notice = _CodeNotice.refused(
      walletMoveFailureText(failure, onNewPhone: true),
    );
    if (failure == WalletMoveFailure.expired) _replaceOffer();
  });

  @override
  Widget build(BuildContext context) {
    final secret = _secret;
    if (secret != null) {
      return TransferStepFocus(
        key: const ValueKey('review'),
        announce: 'walletTransferReviewTitle'.tr(),
        child: TransferImportReview(
          secret: secret,
          source: ManagedImportSource.movedFromDevice,
          checkCode: _checkCode,
          onCodesDiffer: () => _drop(_Drop.codesDiffer),
          onImporting: _onImporting,
          onCancel: widget.onCancel,
        ),
      );
    }
    final offer = _offer;
    if (offer == null) return const SizedBox.shrink();
    return TransferStepFocus(
      key: const ValueKey('code'),
      child: _OfferStep(
        offer: offer,
        lifetimeMinutes: _lifetimeMinutes,
        notice: _notice,
        cameraDenied: _cameraDenied,
        onScan: _scanReply,
        onOpenSettings: _device.openAppSettings,
        onCancel: widget.onCancel,
      ),
    );
  }
}
