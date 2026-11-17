import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:komodo_ui_kit/komodo_ui_kit.dart';
import 'package:web_dex/bloc/auth_bloc/auth_bloc.dart';
import 'package:web_dex/bloc/legal_agreement/legal_agreement_bloc.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/model/wallets_manager_models.dart';
import 'package:web_dex/shared/widgets/disclaimer/terms_consent_text.dart';
import 'package:web_dex/views/common/wallet_access/wallet_access_feedback.dart';

/// Creation has no credential form. The service owns naming, generation and
/// crash-safe persistence; this view only presents progress and retry.
class WalletCreation extends StatefulWidget {
  const WalletCreation({
    super.key,
    required this.action,
    required this.onCreate,
    required this.onCancel,
    this.acceptedOnEntry = false,
  });

  final WalletsManagerAction action;
  final VoidCallback onCreate;
  final VoidCallback onCancel;
  final bool acceptedOnEntry;

  /// How long creation may run before the view says it is slow.
  static const slowAfter = Duration(seconds: 15);

  @override
  State<WalletCreation> createState() => _WalletCreationState();
}

class _WalletCreationState extends State<WalletCreation> {
  final FocusNode _createFocus = FocusNode(debugLabel: 'create wallet');
  bool _submitted = false;
  bool _waitingForLegal = false;
  bool _slow = false;
  Timer? _slowTimer;

  @override
  void initState() {
    super.initState();
    if (context.read<AuthBloc>().state.isLoading) _watchForSlowCreation();
    if (widget.acceptedOnEntry) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _submit(accepted: true);
      });
    }
  }

  @override
  void dispose() {
    _slowTimer?.cancel();
    _createFocus.dispose();
    super.dispose();
  }

  void _watchForSlowCreation() {
    _slowTimer ??= Timer(WalletCreation.slowAfter, () {
      if (mounted) setState(() => _slow = true);
    });
  }

  void _creationSettled({required bool failed}) {
    _slowTimer?.cancel();
    _slowTimer = null;
    setState(() {
      _submitted = false;
      _slow = false;
    });
    // The action was unmounted while busy; hand focus back to the retry.
    if (failed) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _createFocus.requestFocus();
      });
    }
  }

  Future<void> _submit({bool accepted = false}) async {
    if (_submitted || _waitingForLegal) return;
    if (!accepted) {
      _waitingForLegal = true;
      final agreement = await awaitLegalAgreement(context);
      _waitingForLegal = false;
      if (!mounted || agreement == null) return;
      context.read<LegalAgreementBloc>().add(
        LegalAgreementSubmitted(
          'wallet-creation',
          snapshot: agreement.snapshot,
        ),
      );
    }
    if (!mounted) return;
    setState(() => _submitted = true);
    _watchForSlowCreation();
    widget.onCreate();
  }

  @override
  Widget build(BuildContext context) => BlocConsumer<AuthBloc, AuthBlocState>(
    listener: (context, state) {
      if (!mounted) return;
      if (state.isLoading) {
        _watchForSlowCreation();
      } else {
        _creationSettled(failed: state.isError);
      }
    },
    builder: (context, state) {
      final busy = _submitted || state.isLoading;
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: Text(
              LocaleKeys.walletCreationTitle.tr(),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'authInstantCreationDescription'.tr(),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          if (busy) ...[
            // The one progress indicator for creation; the manager draws no
            // overlay over this view. It follows the engine's own state, so
            // nothing spins before creation has really started.
            if (state.isLoading)
              Center(
                child: WalletAccessProgress(
                  key: const Key('wallet-creation-progress'),
                  label: 'authCreatingWallet'.tr(),
                  showLabel: true,
                ),
              ),
            if (_slow) ...[
              const SizedBox(height: 16),
              WalletAccessNotice(
                key: const Key('wallet-creation-slow'),
                text: 'authCreationTakingLonger'.tr(),
              ),
            ],
          ] else ...[
            if (state.isError) ...[
              WalletAccessNotice(
                text: 'authCreationRetryDescription'.tr(),
                tone: WalletAccessTone.error,
              ),
              const SizedBox(height: 16),
            ],
            if (!widget.acceptedOnEntry) ...[
              TermsConsentText(actionLabel: LocaleKeys.create.tr()),
              const SizedBox(height: 12),
            ],
            LegalConsentAction(
              builder: (allowed) => UiPrimaryButton(
                expandForText: true,
                key: const Key('confirm-password-button'),
                focusNode: _createFocus,
                height: 50,
                text: state.isError
                    ? LocaleKeys.tryAgain.tr()
                    : LocaleKeys.create.tr(),
                onPressed: allowed
                    ? () => _submit(accepted: widget.acceptedOnEntry)
                    : null,
              ),
            ),
            const SizedBox(height: 16),
            // Offered only while nothing is in flight: an interrupted creation
            // cannot be stopped in the engine, only resumed.
            UiUnderlineTextButton(
              text: LocaleKeys.cancel.tr(),
              onPressed: widget.onCancel,
            ),
          ],
        ],
      );
    },
  );
}
