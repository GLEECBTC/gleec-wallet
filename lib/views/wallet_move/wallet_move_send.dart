import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:komodo_ui_kit/komodo_ui_kit.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/services/device/device_controls.dart';
import 'package:web_dex/services/wallet_access/wallet_access_service.dart';
import 'package:web_dex/services/wallet_access/wallet_lock_policy.dart';
import 'package:web_dex/services/wallet_move/wallet_move_types.dart';
import 'package:web_dex/shared/screenshot/screenshot_sensitivity.dart';
import 'package:web_dex/views/common/wallet_access/wallet_access_feedback.dart';
import 'package:web_dex/views/settings/widgets/security_settings/security_section_card.dart';
import 'package:web_dex/views/wallet_move/read_wallet_transfer_secret.dart';
import 'package:web_dex/views/wallet_move/transfer_check_code.dart';
import 'package:web_dex/views/wallet_move/transfer_qr_code.dart';
import 'package:web_dex/views/wallet_move/transfer_scanner.dart';
import 'package:web_dex/views/wallet_move/transfer_widgets.dart';
import 'package:web_dex/views/wallet_move/wallet_move_failure_text.dart';

part 'wallet_move_send_steps.dart';

typedef _Notice = ({String text, WalletAccessTone tone});

/// Opens the old phone's half of a move from Security settings.
Future<void> openWalletMoveSend(BuildContext context) => openTransferFlow(
  context,
  title: 'walletMoveSettingsTitle'.tr(),
  builder: (context) =>
      WalletMoveSend(onClose: () => closeTransferFlow(context)),
);

/// The old phone's half of a move: scan the new phone's code, confirm it is
/// the owner, then show the wallet sealed to that phone for [replyLifetime].
///
/// The seed exists only between the confirmation and the seal, never while
/// the camera is open. The reply goes when the app is left or locks, when it
/// times out and when this screen closes; its check code is not secret and
/// stays for comparing.
class WalletMoveSend extends StatefulWidget {
  const WalletMoveSend({
    required this.onClose,
    this.readSecret = readWalletTransferSecretResult,
    this.scan = scanTransferCode,
    this.now = DateTime.now,
    this.replyLifetime = const Duration(minutes: 2),
    super.key,
  });

  final VoidCallback onClose;
  final WalletSecretReader readSecret;
  final QrScanner scan;
  final DateTime Function() now;
  final Duration replyLifetime;

  @override
  State<WalletMoveSend> createState() => _WalletMoveSendState();
}

enum _SendStep { explain, reply, cleared }

class _WalletMoveSendState extends State<WalletMoveSend>
    with WidgetsBindingObserver {
  late final WalletMoveProtocol _protocol;
  late final DeviceControls _device;
  StreamSubscription<void>? _sensitiveViews;
  _SendStep _step = _SendStep.explain;

  /// The new phone's code, kept to seal again. It holds a public key only.
  String? _offer;
  String? _reply;
  String? _checkCode;
  int _replyGeneration = 0;
  DateTime? _replyDeadline;
  Timer? _countdown;
  Duration _left = Duration.zero;

  /// The reply is covered while the app is only inactive, as the phrase is.
  bool _masked = false;
  bool _busy = false;
  bool _screenOn = false;

  /// Why the camera did not scan: access off (true) or no camera (false).
  bool? _cameraDenied;
  _Notice? _notice;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _protocol = context.read<WalletMoveProtocol>();
    _device =
        context.read<DeviceControls?>() ?? const MethodChannelDeviceControls();
    final coordinator = context.read<WalletAccessService?>()?.unlockCoordinator;
    _sensitiveViews = coordinator?.sensitiveViewsMustClose.listen((_) {
      if (WidgetsBinding.instance.lifecycleState ==
              AppLifecycleState.inactive &&
          !coordinator.state.isLocked) {
        return;
      }
      _clear();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_sensitiveViews?.cancel());
    _countdown?.cancel();
    _keepScreenOn(false);
    _reply = null;
    _offer = null;
    super.dispose();
  }

  void _keepScreenOn(bool on) {
    if (_screenOn == on) return;
    _screenOn = on;
    unawaited(_device.keepScreenOn(on));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        if (_masked) setState(() => _masked = false);
      case AppLifecycleState.inactive:
        if (focusLossLeavesApp && _reply != null && !_masked) {
          setState(() => _masked = true);
        }
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        _clear();
    }
  }

  /// Drops the reply. Its check code stays: the new phone may have read it.
  void _clear() {
    if (!mounted || _reply == null) return;
    _countdown?.cancel();
    _keepScreenOn(false);
    setState(() {
      _reply = null;
      _masked = false;
      _step = _SendStep.cleared;
    });
  }

  Future<void> _scan() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _notice = null;
      _cameraDenied = null;
    });
    try {
      final result = await widget.scan(
        context,
        'walletMoveScannerNewPhone'.tr(),
      );
      if (!mounted) return;
      switch (result) {
        case TransferScanned(:final code):
          final refused = _offerRefusal(code);
          if (refused != null) {
            setState(() => _notice = _moveFailure(refused));
            return;
          }
          _offer = code;
          await _authorizeAndSeal();
        case TransferScanCanceled():
          break;
        case TransferScanDenied():
          setState(() => _cameraDenied = true);
        case TransferScanUnsupported():
          setState(() => _cameraDenied = false);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Refuses a code before the owner confirms anything for it.
  WalletMoveFailure? _offerRefusal(String code) {
    try {
      _protocol.checkOffer(code);
      return null;
    } on WalletMoveException catch (error) {
      return error.failure;
    }
  }

  Future<void> _showAgain() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await _authorizeAndSeal();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Confirms the owner, then seals at once: the seed is never kept.
  Future<void> _authorizeAndSeal() async {
    final offer = _offer;
    if (offer == null) return;
    final read = await widget.readSecret(context);
    if (!mounted) return;
    switch (read) {
      case WalletSecretReady(:final secret):
        try {
          _showReply(_protocol.seal(offerCode: offer, secret: secret));
        } on WalletMoveException catch (error) {
          _backToStart(_moveFailure(error.failure));
        } on FormatException {
          _backToStart((
            text: 'walletMoveSendTooLarge'.tr(),
            tone: WalletAccessTone.error,
          ));
        }
      case WalletSecretNotRead(:final reason):
        // A closed confirmation leaves the user where they were.
        if (_unreadNotice(reason) case final notice?) _backToStart(notice);
    }
  }

  void _backToStart(_Notice notice) => setState(() {
    _step = _SendStep.explain;
    _notice = notice;
  });

  static _Notice _moveFailure(WalletMoveFailure failure) => (
    text: walletMoveFailureText(failure, onNewPhone: false),
    tone: WalletAccessTone.error,
  );

  static _Notice? _unreadNotice(WalletSecretUnread reason) => switch (reason) {
    WalletSecretUnread.canceled => null,
    WalletSecretUnread.interrupted => (
      text: 'walletMoveSendInterrupted'.tr(),
      tone: WalletAccessTone.warning,
    ),
    WalletSecretUnread.unsupported => (
      text: 'walletMoveSendUnsupported'.tr(),
      tone: WalletAccessTone.error,
    ),
    WalletSecretUnread.failed => (
      text: 'walletMoveSendReadFailed'.tr(),
      tone: WalletAccessTone.error,
    ),
  };

  void _showReply(String reply) {
    final generation = ++_replyGeneration;
    _countdown?.cancel();
    _countdown = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    _keepScreenOn(true);
    setState(() {
      _reply = reply;
      _checkCode = null;
      _replyDeadline = widget.now().add(widget.replyLifetime);
      _left = widget.replyLifetime;
      _notice = null;
      _masked = false;
      _step = _SendStep.reply;
    });
    unawaited(_workOutCheckCode(reply, generation));
  }

  Future<void> _workOutCheckCode(String reply, int generation) async {
    String? code;
    try {
      code = await _protocol.checkCode(reply);
    } on Object {
      // Anything, including an isolate that died: there is no code to show.
      code = null;
    }
    if (!mounted || generation != _replyGeneration) return;
    if (code != null) {
      setState(() => _checkCode = code);
      return;
    }
    // Without the digits nobody can tell whose reply the new phone read.
    _countdown?.cancel();
    _keepScreenOn(false);
    setState(() {
      _reply = null;
      _step = _SendStep.explain;
      _notice = (
        text: 'walletMoveCheckCodeFailed'.tr(),
        tone: WalletAccessTone.error,
      );
    });
  }

  void _tick() {
    final deadline = _replyDeadline;
    if (!mounted || deadline == null || _reply == null) return;
    final left = deadline.difference(widget.now());
    if (left <= Duration.zero) {
      _clear();
      return;
    }
    setState(() => _left = left);
  }

  Future<void> _openSettings() => _device.openAppSettings();

  String get _clearedText {
    final code = _checkCode;
    return code == null
        ? 'walletMoveSendCleared'.tr()
        : 'walletMoveSendClearedWithCode'.tr(
            args: [TransferCheckCode.grouped(code)],
          );
  }

  @override
  Widget build(BuildContext context) => TransferStepFocus(
    key: ValueKey(_step),
    announce: switch (_step) {
      _SendStep.explain => null,
      _SendStep.reply => 'walletMoveSendReplyTitle'.tr(),
      _SendStep.cleared => _clearedText,
    },
    child: switch (_step) {
      _SendStep.explain => _SendExplain(
        notice: _notice,
        busy: _busy,
        cameraDenied: _cameraDenied,
        onScan: _scan,
        onOpenSettings: _openSettings,
        onCancel: widget.onClose,
      ),
      _SendStep.reply => ScreenshotSensitive(
        child: _SendReply(
          reply: _masked ? null : _reply,
          checkCode: _checkCode,
          left: _left,
          onDone: widget.onClose,
        ),
      ),
      _SendStep.cleared => _SendCleared(
        text: _clearedText,
        checkCode: _checkCode,
        busy: _busy,
        onShowAgain: _showAgain,
        onDone: widget.onClose,
      ),
    },
  );
}
