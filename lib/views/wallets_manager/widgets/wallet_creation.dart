import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:komodo_ui_kit/komodo_ui_kit.dart';
import 'package:web_dex/bloc/auth_bloc/auth_bloc.dart';
import 'package:web_dex/bloc/legal_agreement/legal_agreement_bloc.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/model/wallets_manager_models.dart';
import 'package:web_dex/shared/widgets/disclaimer/terms_consent_text.dart';

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

  @override
  State<WalletCreation> createState() => _WalletCreationState();
}

class _WalletCreationState extends State<WalletCreation> {
  bool _submitted = false;
  bool _waitingForLegal = false;

  @override
  void initState() {
    super.initState();
    if (widget.acceptedOnEntry) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _submit(accepted: true);
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
    widget.onCreate();
  }

  @override
  Widget build(BuildContext context) => BlocConsumer<AuthBloc, AuthBlocState>(
    listener: (context, state) {
      if (!state.isLoading && mounted) setState(() => _submitted = false);
    },
    builder: (context, state) {
      final busy = _submitted || state.isLoading;
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            busy
                ? 'authCreatingWallet'.tr()
                : LocaleKeys.walletCreationTitle.tr(),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 16),
          Text(
            'authInstantCreationDescription'.tr(),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          if (state.isLoading)
            Semantics(
              liveRegion: true,
              label: 'authCreatingWallet'.tr(),
              child: TickerMode(
                enabled: !MediaQuery.disableAnimationsOf(context),
                child: const Center(child: CircularProgressIndicator()),
              ),
            ),
          if (state.isError) ...[
            Semantics(
              liveRegion: true,
              child: Text(
                'authCreationRetryDescription'.tr(),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
            const SizedBox(height: 16),
          ],
          if (!widget.acceptedOnEntry) ...[
            TermsConsentText(actionLabel: LocaleKeys.create.tr()),
            const SizedBox(height: 12),
          ],
          if (!busy)
            LegalConsentAction(
              builder: (allowed) => UiPrimaryButton(
                expandForText: true,
                key: const Key('confirm-password-button'),
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
          UiUnderlineTextButton(
            text: LocaleKeys.cancel.tr(),
            onPressed: busy ? null : widget.onCancel,
          ),
        ],
      );
    },
  );
}
