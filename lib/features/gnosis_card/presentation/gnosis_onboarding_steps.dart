import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:komodo_ui_kit/komodo_ui_kit.dart';
import 'package:web_dex/features/gnosis_card/domain/gnosis_card_models.dart';
import 'package:web_dex/features/gnosis_card/presentation/gnosis_card_locale_keys.dart';
import 'package:web_dex/features/gnosis_card/presentation/gnosis_onboarding_widgets.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';

part 'gnosis_onboarding_card_choice_steps.dart';
part 'gnosis_onboarding_identity_steps.dart';
part 'gnosis_onboarding_order_steps.dart';
part 'gnosis_onboarding_verification_steps.dart';

class GnosisDiscoveryStep extends StatelessWidget {
  const GnosisDiscoveryStep({
    required this.busy,
    required this.phase,
    required this.onRetry,
    this.error,
    super.key,
  });

  final bool busy;
  final GnosisCardAutomationPhase phase;
  final String? error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => GnosisStepCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GnosisStepHeader(
          icon: Icons.credit_card,
          title: LocaleKeys.gnosisCard_discovery_title.tr(),
          body: LocaleKeys.gnosisCard_discovery_body.tr(),
        ),
        const SizedBox(height: 24),
        GnosisStatusBanner(
          title: _preparationStatus(phase),
          message: LocaleKeys.gnosisCard_discovery_kdfBody.tr(),
          icon: Icons.shield_outlined,
          isLiveRegion: true,
        ),
        if (error != null) ...[
          const SizedBox(height: 16),
          GnosisServerErrorBanner(message: error!),
        ],
        if (busy) ...[
          const SizedBox(height: 24),
          GnosisProgressIndicator(label: _preparationStatus(phase)),
        ] else if (error != null ||
            phase == GnosisCardAutomationPhase.paused) ...[
          const SizedBox(height: 24),
          UiPrimaryButton(
            key: const Key('gnosis-preparation-retry'),
            text: phase == GnosisCardAutomationPhase.paused && error == null
                ? LocaleKeys.gnosisCard_discovery_reauthenticate.tr()
                : LocaleKeys.gnosisCard_retry.tr(),
            onPressed: onRetry,
          ),
        ],
      ],
    ),
  );
}

String _preparationStatus(GnosisCardAutomationPhase phase) => switch (phase) {
  GnosisCardAutomationPhase.preparingWallet =>
    GnosisCardLocaleKeys.preparingWallet.tr(),
  GnosisCardAutomationPhase.awaitingSignature =>
    GnosisCardLocaleKeys.awaitingSignature.tr(),
  GnosisCardAutomationPhase.authenticating =>
    GnosisCardLocaleKeys.authenticating.tr(),
  GnosisCardAutomationPhase.preparingCardAccount =>
    GnosisCardLocaleKeys.preparingCardAccount.tr(),
  _ => GnosisCardLocaleKeys.checkingAccount.tr(),
};

class GnosisSignupAndTermsStep extends StatefulWidget {
  const GnosisSignupAndTermsStep({
    required this.terms,
    required this.busy,
    required this.onOpenTerm,
    required this.onSubmit,
    this.initialEmail,
    this.error,
    super.key,
  });

  final List<GnosisTerm> terms;
  final bool busy;
  final String? initialEmail;
  final String? error;
  final ValueChanged<GnosisTerm> onOpenTerm;
  final void Function(String email, List<GnosisTermAcceptance> acceptances)
  onSubmit;

  @override
  State<GnosisSignupAndTermsStep> createState() =>
      _GnosisSignupAndTermsStepState();
}

class _GnosisSignupAndTermsStepState extends State<GnosisSignupAndTermsStep> {
  final _formKey = GlobalKey<FormState>();
  final _termsErrorFocusNode = FocusNode();
  late final TextEditingController _emailController;
  late Set<String> _acceptedTerms;
  bool _showTermsError = false;

  @override
  void initState() {
    super.initState();
    _emailController = TextEditingController(text: widget.initialEmail);
    _acceptedTerms = widget.terms
        .where((term) => term.isAccepted)
        .map(_termKey)
        .toSet();
  }

  @override
  void didUpdateWidget(covariant GnosisSignupAndTermsStep oldWidget) {
    super.didUpdateWidget(oldWidget);
    final currentTerms = widget.terms.map(_termKey).toSet();
    _acceptedTerms.removeWhere((term) => !currentTerms.contains(term));
    for (final term in widget.terms.where((term) => term.isAccepted)) {
      _acceptedTerms.add(_termKey(term));
    }
  }

  @override
  void dispose() {
    _termsErrorFocusNode.dispose();
    _emailController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => GnosisStepCard(
    child: AutofillGroup(
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            GnosisStepHeader(
              icon: Icons.person_add_alt_1_outlined,
              title: LocaleKeys.gnosisCard_account_title.tr(),
              body: LocaleKeys.gnosisCard_account_body.tr(),
            ),
            const SizedBox(height: 24),
            UiTextFormField(
              key: const Key('gnosis-signup-email'),
              controller: _emailController,
              labelText: LocaleKeys.gnosisCard_account_emailLabel.tr(),
              hintText: LocaleKeys.gnosisCard_account_emailHint.tr(),
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.done,
              autocorrect: false,
              autofillHints: const [AutofillHints.email],
              validator: _validateEmail,
              enabled: !widget.busy,
            ),
            const SizedBox(height: 24),
            Semantics(
              header: true,
              child: Text(
                LocaleKeys.gnosisCard_account_termsTitle.tr(),
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            const SizedBox(height: 6),
            Text(LocaleKeys.gnosisCard_account_termsBody.tr()),
            const SizedBox(height: 12),
            for (final term in widget.terms) _termTile(context, term),
            if (_showTermsError) ...[
              const SizedBox(height: 8),
              Semantics(
                liveRegion: true,
                child: Focus(
                  focusNode: _termsErrorFocusNode,
                  child: Text(
                    LocaleKeys.gnosisCard_account_acceptanceRequired.tr(),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).brightness == Brightness.dark
                          ? const Color(0xFFFFB4C8)
                          : const Color(0xFFA00038),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
            if (widget.error != null) ...[
              const SizedBox(height: 16),
              GnosisServerErrorBanner(message: widget.error!),
            ],
            const SizedBox(height: 24),
            UiPrimaryButton(
              key: const Key('gnosis-signup-submit'),
              text: LocaleKeys.gnosisCard_account_submit.tr(),
              onPressed: widget.busy ? null : _submit,
            ),
          ],
        ),
      ),
    ),
  );

  Widget _termTile(BuildContext context, GnosisTerm term) {
    final termKey = _termKey(term);
    final accepted = _acceptedTerms.contains(termKey);
    void toggleAccepted() => setState(() {
      accepted ? _acceptedTerms.remove(termKey) : _acceptedTerms.add(termKey);
      _showTermsError = widget.terms.any(
        (candidate) => !_acceptedTerms.contains(_termKey(candidate)),
      );
    });

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final stack =
              constraints.maxWidth < 480 ||
              MediaQuery.textScalerOf(context).scale(1) >= 1.4;
          final agreement = Semantics(
            checked: accepted,
            enabled: !widget.busy,
            label:
                '${term.title}, ${LocaleKeys.gnosisCard_account_required.tr()}',
            child: InkWell(
              onTap: widget.busy ? null : toggleAccepted,
              borderRadius: BorderRadius.circular(12),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 56),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 10,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      ExcludeSemantics(
                        child: Icon(
                          accepted
                              ? Icons.check_box
                              : Icons.check_box_outline_blank,
                          size: 28,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(term.title),
                            Text(
                              'v${term.version} · ${LocaleKeys.gnosisCard_account_required.tr()}',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
          final open = TextButton.icon(
            onPressed: widget.busy ? null : () => widget.onOpenTerm(term),
            icon: const Icon(Icons.open_in_new, size: 18),
            label: Text(LocaleKeys.gnosisCard_account_viewDocument.tr()),
          );
          if (stack) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                agreement,
                Align(alignment: AlignmentDirectional.centerEnd, child: open),
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(child: agreement),
              open,
            ],
          );
        },
      ),
    );
  }

  String? _validateEmail(String? value) {
    final email = value?.trim() ?? '';
    if (email.isEmpty) return LocaleKeys.gnosisCard_account_emailRequired.tr();
    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)) {
      return LocaleKeys.gnosisCard_account_emailInvalid.tr();
    }
    return null;
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (widget.terms.any((term) => !_acceptedTerms.contains(_termKey(term)))) {
      setState(() => _showTermsError = true);
      _termsErrorFocusNode.requestFocus();
      return;
    }
    TextInput.finishAutofillContext();
    widget.onSubmit(
      _emailController.text.trim(),
      widget.terms
          .map(
            (term) => GnosisTermAcceptance(id: term.id, version: term.version),
          )
          .toList(growable: false),
    );
  }
}

String _termKey(GnosisTerm term) => '${term.id}\u0000${term.version}';

class GnosisKycStep extends StatelessWidget {
  const GnosisKycStep({
    required this.status,
    required this.busy,
    required this.onOpen,
    required this.onRefresh,
    required this.onSupport,
    this.error,
    super.key,
  });

  final GnosisKycStatus status;
  final bool busy;
  final String? error;
  final VoidCallback onOpen;
  final VoidCallback onRefresh;
  final VoidCallback onSupport;

  @override
  Widget build(BuildContext context) {
    final terminal =
        status == GnosisKycStatus.rejected ||
        status == GnosisKycStatus.requiresAction;
    final canOpen = switch (status) {
      GnosisKycStatus.notStarted ||
      GnosisKycStatus.documentsRequested ||
      GnosisKycStatus.resubmissionRequested => true,
      _ => false,
    };
    return GnosisStepCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GnosisStepHeader(
            icon: Icons.verified_user_outlined,
            title: LocaleKeys.gnosisCard_kyc_title.tr(),
            body: LocaleKeys.gnosisCard_kyc_body.tr(),
          ),
          const SizedBox(height: 24),
          GnosisStatusBanner(
            title: _kycStatusLabel(status),
            message: _kycStatusBody(status),
            icon: terminal
                ? Icons.support_agent
                : status == GnosisKycStatus.approved
                ? Icons.check_circle_outline
                : Icons.hourglass_top,
            isError: terminal,
            isLiveRegion: true,
          ),
          if (canOpen) ...[
            const SizedBox(height: 16),
            GnosisExternalHandoffCard(
              title: LocaleKeys.gnosisCard_kyc_title.tr(),
              body: LocaleKeys.gnosisCard_externalNotice.tr(),
              actionLabel: status == GnosisKycStatus.notStarted
                  ? LocaleKeys.gnosisCard_kyc_launch.tr()
                  : LocaleKeys.gnosisCard_kyc_relaunch.tr(),
              onOpen: busy ? null : onOpen,
            ),
          ] else if (!terminal && status != GnosisKycStatus.approved) ...[
            const SizedBox(height: 24),
            GnosisProgressIndicator(label: _kycStatusLabel(status)),
          ],
          if (error != null) ...[
            const SizedBox(height: 16),
            GnosisServerErrorBanner(message: error!),
          ],
          if (terminal || (error != null && !canOpen)) ...[
            const SizedBox(height: 24),
            UiPrimaryButton(
              key: Key(terminal ? 'gnosis-kyc-support' : 'gnosis-kyc-refresh'),
              text: terminal
                  ? LocaleKeys.gnosisCard_openSupport.tr()
                  : LocaleKeys.gnosisCard_retry.tr(),
              onPressed: busy
                  ? null
                  : terminal
                  ? onSupport
                  : onRefresh,
            ),
          ],
        ],
      ),
    );
  }
}
