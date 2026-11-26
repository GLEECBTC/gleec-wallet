part of 'wallet_move_send.dart';

/// What a move does and the one warning that matters, before the camera.
class _SendExplain extends StatelessWidget {
  const _SendExplain({
    required this.notice,
    required this.busy,
    required this.cameraDenied,
    required this.onScan,
    required this.onOpenSettings,
    required this.onCancel,
  });

  final _Notice? notice;
  final bool busy;
  final bool? cameraDenied;
  final VoidCallback onScan;
  final VoidCallback onOpenSettings;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final cameraDenied = this.cameraDenied;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TransferTitle('walletMoveSendTitle'.tr()),
        const SizedBox(height: 12),
        TransferText('walletMoveSendIntro'.tr()),
        const SizedBox(height: 12),
        TransferStep(number: 1, text: 'walletMoveSendStepNew'.tr()),
        TransferStep(number: 2, text: 'walletMoveSendStepConfirm'.tr()),
        TransferStep(number: 3, text: 'walletMoveSendStepReply'.tr()),
        const SizedBox(height: 16),
        WalletAccessNotice(
          key: const Key('wallet-move-send-warning'),
          text: 'walletMoveSendWarning'.tr(),
          tone: WalletAccessTone.warning,
          announce: false,
        ),
        const SizedBox(height: 12),
        WalletAccessNotice(text: 'walletMoveSendStays'.tr(), announce: false),
        const SizedBox(height: 16),
        if (notice case final notice?) ...[
          WalletAccessNotice(
            key: const Key('wallet-move-send-notice'),
            text: notice.text,
            tone: notice.tone,
          ),
          const SizedBox(height: 12),
        ],
        if (cameraDenied != null) ...[
          TransferCameraNotice(
            denied: cameraDenied,
            onOpenSettings: onOpenSettings,
          ),
          const SizedBox(height: 12),
        ],
        if (busy) ...[
          WalletAccessProgress(label: LocaleKeys.pleaseWait.tr()),
          const SizedBox(height: 12),
        ],
        UiPrimaryButton(
          key: const Key('wallet-move-send-scan'),
          text: cameraDenied == null
              ? 'walletMoveSendScan'.tr()
              : LocaleKeys.tryAgain.tr(),
          prefix: const Padding(
            padding: EdgeInsets.only(right: 8),
            child: Icon(Icons.qr_code_scanner, size: 20),
          ),
          expandForText: true,
          height: 50,
          // Stays pressable while busy so it keeps focus; repeats are ignored.
          onPressed: onScan,
        ),
        const SizedBox(height: 12),
        UiUnderlineTextButton(
          text: LocaleKeys.cancel.tr(),
          expandForText: true,
          onPressed: onCancel,
        ),
      ],
    );
  }
}

/// The sealed wallet for the new phone, its check code and its time left.
/// The code comes before the instructions so it stays in view at large text.
class _SendReply extends StatelessWidget {
  const _SendReply({
    required this.reply,
    required this.checkCode,
    required this.left,
    required this.onDone,
  });

  /// Null while covered; the check code is not secret and stays.
  final String? reply;
  final String? checkCode;
  final Duration left;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final reply = this.reply;
    final seconds = left.inSeconds.clamp(0, 3599);
    final clock =
        '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TransferTitle('walletMoveSendReplyTitle'.tr()),
        const SizedBox(height: 12),
        if (reply != null)
          TransferQrCode(
            key: const Key('wallet-move-reply-code'),
            data: reply,
            semanticLabel: 'walletMoveSendReplyCodeLabel'.tr(),
          )
        else
          SizedBox(
            height: 160,
            child: Center(
              child: TransferText('walletMoveSendReplyHidden'.tr()),
            ),
          ),
        const SizedBox(height: 12),
        TransferCheckCode(code: checkCode),
        const SizedBox(height: 8),
        Text(
          'walletMoveSendReplyCountdown'.tr(args: [clock]),
          key: const Key('wallet-move-reply-countdown'),
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurface,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(height: 12),
        TransferText('walletMoveSendReplyHint'.tr()),
        const SizedBox(height: 20),
        SecuritySecondaryButton(
          key: const Key('wallet-move-send-done'),
          text: LocaleKeys.done.tr(),
          onPressed: onDone,
        ),
      ],
    );
  }
}

/// After the reply went: the digits it had, and a fresh seal on request.
class _SendCleared extends StatelessWidget {
  const _SendCleared({
    required this.text,
    required this.checkCode,
    required this.busy,
    required this.onShowAgain,
    required this.onDone,
  });

  final String text;
  final String? checkCode;
  final bool busy;
  final VoidCallback onShowAgain;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      TransferTitle('walletMoveSendClearedTitle'.tr()),
      const SizedBox(height: 12),
      // Read out by the step change already.
      WalletAccessNotice(
        key: const Key('wallet-move-send-cleared'),
        text: text,
        announce: false,
      ),
      const SizedBox(height: 12),
      TransferCheckCode(code: checkCode),
      const SizedBox(height: 20),
      if (busy) ...[
        WalletAccessProgress(label: LocaleKeys.pleaseWait.tr()),
        const SizedBox(height: 12),
      ],
      UiPrimaryButton(
        key: const Key('wallet-move-send-show-again'),
        text: 'walletMoveSendShowAgain'.tr(),
        expandForText: true,
        height: 50,
        onPressed: onShowAgain,
      ),
      const SizedBox(height: 12),
      SecuritySecondaryButton(
        key: const Key('wallet-move-send-cleared-done'),
        text: LocaleKeys.done.tr(),
        onPressed: onDone,
      ),
    ],
  );
}
