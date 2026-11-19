part of 'wallet_move_receive.dart';

enum _NoticeKind { renewed, discarded, cleared, refused }

/// What the offer step says about the last attempt, and what to do now.
final class _CodeNotice {
  const _CodeNotice(this.kind, this.text, this.tone);

  _CodeNotice.renewed()
    : this(
        _NoticeKind.renewed,
        'walletMoveReceiveRenewed'.tr(),
        WalletAccessTone.info,
      );

  /// Another phone answered this phone's code.
  _CodeNotice.discarded()
    : this(
        _NoticeKind.discarded,
        'walletMoveReceiveDiscarded'.tr(),
        WalletAccessTone.warning,
      );

  /// The app was left, or the offer's time ran out, during the review.
  _CodeNotice.cleared()
    : this(
        _NoticeKind.cleared,
        'walletMoveReceiveCleared'.tr(),
        WalletAccessTone.warning,
      );

  _CodeNotice.noCheckCode()
    : this(
        _NoticeKind.refused,
        'walletMoveCheckCodeFailed'.tr(),
        WalletAccessTone.error,
      );

  _CodeNotice.refused(String text)
    : this(_NoticeKind.refused, text, WalletAccessTone.error);

  final _NoticeKind kind;
  final String text;
  final WalletAccessTone tone;
}

/// The code the old phone scans, with how to finish.
class _OfferStep extends StatelessWidget {
  const _OfferStep({
    required this.offer,
    required this.lifetimeMinutes,
    required this.notice,
    required this.cameraDenied,
    required this.onScan,
    required this.onOpenSettings,
    required this.onCancel,
  });

  final WalletMoveOffer offer;
  final int lifetimeMinutes;
  final _CodeNotice? notice;
  final bool? cameraDenied;
  final VoidCallback onScan;
  final VoidCallback onOpenSettings;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final notice = this.notice;
    final cameraDenied = this.cameraDenied;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TransferTitle('walletMoveReceiveTitle'.tr()),
        const SizedBox(height: 16),
        TransferStep(number: 1, text: 'walletMoveReceiveStepOld'.tr()),
        const SizedBox(height: 12),
        TransferQrCode(
          key: ValueKey(offer.code),
          data: offer.code,
          semanticLabel: 'walletMoveReceiveCodeLabel'.tr(),
        ),
        const SizedBox(height: 8),
        Text(
          'walletMoveReceiveExpiry'.tr(args: ['$lifetimeMinutes']),
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(color: Theme.of(context).colorScheme.onSurface),
        ),
        const SizedBox(height: 12),
        TransferStep(number: 2, text: 'walletMoveReceiveStepScan'.tr()),
        const SizedBox(height: 16),
        if (notice != null) ...[
          WalletAccessNotice(
            key: ValueKey('wallet-move-notice-${notice.kind.name}'),
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
        UiPrimaryButton(
          key: const Key('wallet-move-scan-reply'),
          text: cameraDenied == null
              ? 'walletMoveReceiveScan'.tr()
              : LocaleKeys.tryAgain.tr(),
          prefix: const Padding(
            padding: EdgeInsets.only(right: 8),
            child: Icon(Icons.qr_code_scanner, size: 20),
          ),
          expandForText: true,
          height: 50,
          onPressed: onScan,
        ),
        const SizedBox(height: 12),
        UiUnderlineTextButton(
          key: const Key('wallet-move-receive-cancel'),
          text: LocaleKeys.cancel.tr(),
          expandForText: true,
          onPressed: onCancel,
        ),
      ],
    );
  }
}
