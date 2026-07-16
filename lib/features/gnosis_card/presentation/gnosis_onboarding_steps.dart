import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:komodo_ui_kit/komodo_ui_kit.dart';
import 'package:web_dex/features/gnosis_card/domain/gnosis_card_models.dart';
import 'package:web_dex/features/gnosis_card/presentation/gnosis_onboarding_widgets.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';

class GnosisDiscoveryStep extends StatelessWidget {
  const GnosisDiscoveryStep({
    required this.busy,
    required this.onSignIn,
    this.error,
    super.key,
  });

  final bool busy;
  final String? error;
  final VoidCallback onSignIn;

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
          title: LocaleKeys.gnosisCard_discovery_kdfTitle.tr(),
          message: LocaleKeys.gnosisCard_discovery_kdfBody.tr(),
          icon: Icons.key_outlined,
        ),
        if (error != null) ...[
          const SizedBox(height: 16),
          GnosisServerErrorBanner(message: error!),
        ],
        const SizedBox(height: 24),
        UiPrimaryButton(
          key: const Key('gnosis-sign-in'),
          text: LocaleKeys.gnosisCard_discovery_signIn.tr(),
          prefix: busy
              ? const SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.account_balance_wallet_outlined),
          onPressed: busy ? null : onSignIn,
        ),
      ],
    ),
  );
}

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
  late final TextEditingController _emailController;
  late Set<String> _acceptedIds;

  @override
  void initState() {
    super.initState();
    _emailController = TextEditingController(text: widget.initialEmail);
    _acceptedIds = widget.terms
        .where((term) => term.isAccepted)
        .map((term) => term.id)
        .toSet();
  }

  @override
  void didUpdateWidget(covariant GnosisSignupAndTermsStep oldWidget) {
    super.didUpdateWidget(oldWidget);
    for (final term in widget.terms.where((term) => term.isAccepted)) {
      _acceptedIds.add(term.id);
    }
  }

  @override
  void dispose() {
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
    final accepted = _acceptedIds.contains(term.id);
    void toggleAccepted() => setState(() {
      accepted ? _acceptedIds.remove(term.id) : _acceptedIds.add(term.id);
    });

    return Semantics(
      checked: accepted,
      label: '${term.title}, ${LocaleKeys.gnosisCard_account_required.tr()}',
      child: InkWell(
        onTap: widget.busy ? null : toggleAccepted,
        borderRadius: BorderRadius.circular(12),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final stack =
                    constraints.maxWidth < 480 ||
                    MediaQuery.textScalerOf(context).scale(1) >= 1.4;
                final agreement = Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    ExcludeSemantics(
                      child: UiCheckbox(
                        value: accepted,
                        onChanged: widget.busy ? null : (_) => toggleAccepted(),
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
                      const SizedBox(height: 8),
                      Align(
                        alignment: AlignmentDirectional.centerEnd,
                        child: open,
                      ),
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
          ),
        ),
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
    if (widget.terms.any((term) => !_acceptedIds.contains(term.id))) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(LocaleKeys.gnosisCard_account_acceptanceRequired.tr()),
        ),
      );
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
          const SizedBox(height: 16),
          GnosisExternalHandoffCard(
            title: LocaleKeys.gnosisCard_kyc_title.tr(),
            body: LocaleKeys.gnosisCard_externalNotice.tr(),
            actionLabel: status == GnosisKycStatus.notStarted
                ? LocaleKeys.gnosisCard_kyc_launch.tr()
                : LocaleKeys.gnosisCard_kyc_relaunch.tr(),
            onOpen: busy || !canOpen ? null : onOpen,
          ),
          if (error != null) ...[
            const SizedBox(height: 16),
            GnosisServerErrorBanner(message: error!),
          ],
          const SizedBox(height: 24),
          GnosisResponsiveActions(
            primary: UiPrimaryButton(
              key: const Key('gnosis-kyc-refresh'),
              text: LocaleKeys.gnosisCard_checkStatus.tr(),
              onPressed: busy ? null : onRefresh,
            ),
            secondary: terminal
                ? UiSecondaryButton(
                    key: const Key('gnosis-kyc-support'),
                    text: LocaleKeys.gnosisCard_openSupport.tr(),
                    onPressed: busy ? null : onSupport,
                  )
                : canOpen
                ? UiSecondaryButton(
                    key: const Key('gnosis-kyc-open'),
                    text: LocaleKeys.gnosisCard_kyc_relaunch.tr(),
                    onPressed: busy ? null : onOpen,
                  )
                : null,
          ),
        ],
      ),
    );
  }
}

class GnosisSourceOfFundsStep extends StatefulWidget {
  const GnosisSourceOfFundsStep({
    required this.questions,
    required this.busy,
    required this.onSubmit,
    this.error,
    super.key,
  });

  final List<SourceOfFundsQuestion> questions;
  final bool busy;
  final String? error;
  final ValueChanged<List<SourceOfFundsAnswer>> onSubmit;

  @override
  State<GnosisSourceOfFundsStep> createState() =>
      _GnosisSourceOfFundsStepState();
}

class _GnosisSourceOfFundsStepState extends State<GnosisSourceOfFundsStep> {
  final _formKey = GlobalKey<FormState>();
  final Map<String, String> _answers = {};

  @override
  Widget build(BuildContext context) => GnosisStepCard(
    child: Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GnosisStepHeader(
            icon: Icons.account_balance_outlined,
            title: LocaleKeys.gnosisCard_source_title.tr(),
            body: LocaleKeys.gnosisCard_source_body.tr(),
          ),
          const SizedBox(height: 24),
          for (final question in widget.questions) ...[
            DropdownButtonFormField<String>(
              key: ValueKey('gnosis-source-${question.id}'),
              initialValue: _answers[question.id],
              isExpanded: true,
              decoration: InputDecoration(labelText: question.title),
              items: question.answers
                  .map(
                    (answer) => DropdownMenuItem(
                      value: answer,
                      child: Text(answer, overflow: TextOverflow.ellipsis),
                    ),
                  )
                  .toList(growable: false),
              onChanged: widget.busy
                  ? null
                  : (value) => setState(() {
                      if (value != null) _answers[question.id] = value;
                    }),
              validator: (value) => value == null
                  ? LocaleKeys.gnosisCard_source_required.tr()
                  : null,
            ),
            const SizedBox(height: 16),
          ],
          if (widget.error != null) ...[
            GnosisServerErrorBanner(message: widget.error!),
            const SizedBox(height: 16),
          ],
          UiPrimaryButton(
            key: const Key('gnosis-source-submit'),
            text: LocaleKeys.gnosisCard_source_submit.tr(),
            onPressed: widget.busy ? null : _submit,
          ),
        ],
      ),
    ),
  );

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    widget.onSubmit(
      widget.questions
          .map(
            (question) => SourceOfFundsAnswer(
              questionId: question.id,
              question: question.title,
              answer: _answers[question.id]!,
            ),
          )
          .toList(growable: false),
    );
  }
}

class GnosisPhoneNumberStep extends StatefulWidget {
  const GnosisPhoneNumberStep({
    required this.busy,
    required this.onSubmit,
    this.initialPhone,
    this.error,
    super.key,
  });

  final bool busy;
  final String? initialPhone;
  final String? error;
  final ValueChanged<String> onSubmit;

  @override
  State<GnosisPhoneNumberStep> createState() => _GnosisPhoneNumberStepState();
}

class _GnosisPhoneNumberStepState extends State<GnosisPhoneNumberStep> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _controller;
  bool _confirming = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialPhone);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String get _normalized =>
      _controller.text.replaceAll(RegExp(r'[\s\-()]'), '');

  @override
  Widget build(BuildContext context) => GnosisStepCard(
    child: Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GnosisStepHeader(
            icon: Icons.phone_android_outlined,
            title: _confirming
                ? LocaleKeys.gnosisCard_phone_confirmTitle.tr()
                : LocaleKeys.gnosisCard_phone_title.tr(),
            body: _confirming
                ? '${LocaleKeys.gnosisCard_phone_confirmBody.tr()} $_normalized'
                : LocaleKeys.gnosisCard_phone_body.tr(),
          ),
          const SizedBox(height: 24),
          if (!_confirming)
            UiTextFormField(
              key: const Key('gnosis-phone-number'),
              controller: _controller,
              labelText: LocaleKeys.gnosisCard_phone_numberLabel.tr(),
              hintText: LocaleKeys.gnosisCard_phone_numberHint.tr(),
              keyboardType: TextInputType.phone,
              textInputAction: TextInputAction.done,
              autofillHints: const [AutofillHints.telephoneNumber],
              inputFormatters: [LengthLimitingTextInputFormatter(24)],
              validator: _validatePhone,
              enabled: !widget.busy,
              onFieldSubmitted: (_) => _showConfirmation(),
            ),
          if (widget.error != null) ...[
            const SizedBox(height: 16),
            GnosisServerErrorBanner(message: widget.error!),
          ],
          const SizedBox(height: 24),
          GnosisResponsiveActions(
            primary: UiPrimaryButton(
              key: const Key('gnosis-phone-submit'),
              text: _confirming
                  ? LocaleKeys.gnosisCard_phone_sendCode.tr()
                  : LocaleKeys.gnosisCard_continue.tr(),
              onPressed: widget.busy
                  ? null
                  : _confirming
                  ? () => widget.onSubmit(_normalized)
                  : _showConfirmation,
            ),
            secondary: _confirming
                ? UiSecondaryButton(
                    text: LocaleKeys.gnosisCard_phone_editNumber.tr(),
                    onPressed: widget.busy
                        ? null
                        : () => setState(() => _confirming = false),
                  )
                : null,
          ),
        ],
      ),
    ),
  );

  String? _validatePhone(String? value) {
    if ((value ?? '').trim().isEmpty) {
      return LocaleKeys.gnosisCard_phone_numberRequired.tr();
    }
    if (!RegExp(r'^\+[1-9]\d{7,14}$').hasMatch(_normalized)) {
      return LocaleKeys.gnosisCard_phone_numberInvalid.tr();
    }
    return null;
  }

  void _showConfirmation() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _confirming = true);
  }
}

class GnosisPhoneOtpStep extends StatefulWidget {
  const GnosisPhoneOtpStep({
    required this.challenge,
    required this.busy,
    required this.onVerify,
    required this.onResend,
    required this.onEdit,
    this.error,
    super.key,
  });

  final PhoneOtpChallenge challenge;
  final bool busy;
  final String? error;
  final ValueChanged<String> onVerify;
  final VoidCallback onResend;
  final VoidCallback onEdit;

  @override
  State<GnosisPhoneOtpStep> createState() => _GnosisPhoneOtpStepState();
}

class _GnosisPhoneOtpStepState extends State<GnosisPhoneOtpStep> {
  final _formKey = GlobalKey<FormState>();
  final _controller = TextEditingController();
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  @override
  void didUpdateWidget(covariant GnosisPhoneOtpStep oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.challenge.resendAvailableAt !=
        widget.challenge.resendAvailableAt) {
      _startTimer();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  int get _secondsRemaining {
    final difference = widget.challenge.resendAvailableAt.difference(
      DateTime.now(),
    );
    return difference.isNegative ? 0 : difference.inSeconds + 1;
  }

  @override
  Widget build(BuildContext context) => GnosisStepCard(
    child: Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GnosisStepHeader(
            icon: Icons.sms_outlined,
            title: LocaleKeys.gnosisCard_phone_codeTitle.tr(),
            body:
                '${LocaleKeys.gnosisCard_phone_confirmBody.tr()} '
                '${widget.challenge.phoneNumber}',
          ),
          if (widget.challenge.demoCode != null) ...[
            const SizedBox(height: 20),
            GnosisStatusBanner(
              title: LocaleKeys.gnosisCard_phone_demoCode.tr(),
              message: LocaleKeys.gnosisCard_phone_demoCodeHint.tr(),
              icon: Icons.science_outlined,
            ),
          ],
          const SizedBox(height: 24),
          UiTextFormField(
            key: const Key('gnosis-phone-otp'),
            controller: _controller,
            labelText: LocaleKeys.gnosisCard_phone_codeLabel.tr(),
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.done,
            autofillHints: const [AutofillHints.oneTimeCode],
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(6),
            ],
            validator: (value) => (value?.length ?? 0) == 6
                ? null
                : LocaleKeys.gnosisCard_phone_codeRequired.tr(),
            enabled: !widget.busy,
            onFieldSubmitted: (_) => _verify(),
          ),
          if (widget.error != null) ...[
            const SizedBox(height: 16),
            GnosisServerErrorBanner(message: widget.error!),
          ],
          const SizedBox(height: 24),
          UiPrimaryButton(
            key: const Key('gnosis-phone-verify'),
            text: LocaleKeys.gnosisCard_phone_verify.tr(),
            onPressed: widget.busy ? null : _verify,
          ),
          const SizedBox(height: 12),
          GnosisResponsiveActions(
            primary: UiSecondaryButton(
              key: const Key('gnosis-phone-resend'),
              text: _secondsRemaining == 0
                  ? LocaleKeys.gnosisCard_phone_resend.tr()
                  : LocaleKeys.gnosisCard_phone_resendIn.tr(
                      args: ['$_secondsRemaining'],
                    ),
              onPressed: widget.busy || _secondsRemaining > 0
                  ? null
                  : widget.onResend,
            ),
            secondary: TextButton(
              onPressed: widget.busy ? null : widget.onEdit,
              child: Text(LocaleKeys.gnosisCard_phone_editNumber.tr()),
            ),
          ),
        ],
      ),
    ),
  );

  void _verify() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    widget.onVerify(_controller.text);
  }

  void _startTimer() {
    _timer?.cancel();
    if (_secondsRemaining == 0) return;
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted || _secondsRemaining == 0) timer.cancel();
      if (mounted) setState(() {});
    });
  }
}

String _kycStatusLabel(GnosisKycStatus status) => switch (status) {
  GnosisKycStatus.notStarted => LocaleKeys.gnosisCard_kyc_notStarted.tr(),
  GnosisKycStatus.documentsRequested =>
    LocaleKeys.gnosisCard_kyc_documentsRequested.tr(),
  GnosisKycStatus.pending => LocaleKeys.gnosisCard_kyc_pending.tr(),
  GnosisKycStatus.processing => LocaleKeys.gnosisCard_kyc_processing.tr(),
  GnosisKycStatus.approved => LocaleKeys.gnosisCard_kyc_approved.tr(),
  GnosisKycStatus.resubmissionRequested =>
    LocaleKeys.gnosisCard_kyc_resubmissionRequested.tr(),
  GnosisKycStatus.rejected => LocaleKeys.gnosisCard_kyc_rejected.tr(),
  GnosisKycStatus.requiresAction =>
    LocaleKeys.gnosisCard_kyc_requiresAction.tr(),
};

String _kycStatusBody(GnosisKycStatus status) => switch (status) {
  GnosisKycStatus.notStarted => LocaleKeys.gnosisCard_kyc_notStartedBody.tr(),
  GnosisKycStatus.documentsRequested =>
    LocaleKeys.gnosisCard_kyc_documentsRequestedBody.tr(),
  GnosisKycStatus.pending => LocaleKeys.gnosisCard_kyc_pendingBody.tr(),
  GnosisKycStatus.processing => LocaleKeys.gnosisCard_kyc_processingBody.tr(),
  GnosisKycStatus.approved => LocaleKeys.gnosisCard_kyc_approvedBody.tr(),
  GnosisKycStatus.resubmissionRequested =>
    LocaleKeys.gnosisCard_kyc_resubmissionRequestedBody.tr(),
  GnosisKycStatus.rejected => LocaleKeys.gnosisCard_kyc_rejectedBody.tr(),
  GnosisKycStatus.requiresAction =>
    LocaleKeys.gnosisCard_kyc_requiresActionBody.tr(),
};

class GnosisSafeSetupStep extends StatelessWidget {
  const GnosisSafeSetupStep({
    required this.progress,
    required this.busy,
    required this.onStart,
    required this.onPoll,
    required this.onReset,
    this.error,
    super.key,
  });

  final GnosisOnboardingProgress progress;
  final bool busy;
  final String? error;
  final VoidCallback onStart;
  final VoidCallback onPoll;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final deployment = progress.safeDeployment;
    final configuration = progress.safeConfiguration;
    final failure =
        deployment?.status == SafeDeploymentStatus.failed ||
        deployment?.status == SafeDeploymentStatus.timedOut ||
        (configuration != null && !configuration.isValid);
    return GnosisStepCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GnosisStepHeader(
            icon: Icons.account_balance_wallet_outlined,
            title: LocaleKeys.gnosisCard_safe_title.tr(),
            body: LocaleKeys.gnosisCard_safe_body.tr(),
          ),
          const SizedBox(height: 24),
          if (deployment == null)
            GnosisStatusBanner(
              title: LocaleKeys.gnosisCard_safe_title.tr(),
              message: LocaleKeys.gnosisCard_safe_validStatuses.tr(),
              icon: Icons.security_outlined,
            )
          else
            GnosisStatusBanner(
              title: _safeStatusLabel(deployment.status),
              message: failure
                  ? deployment.failureReason ??
                        (configuration != null && !configuration.isValid
                            ? LocaleKeys.gnosisCard_safe_invalidIntegrity.tr()
                            : _safeStatusLabel(deployment.status))
                  : _safeStatusBody(deployment.status),
              icon: failure
                  ? Icons.error_outline
                  : deployment.status == SafeDeploymentStatus.ok
                  ? Icons.verified_outlined
                  : Icons.sync,
              isError: failure,
              isLiveRegion: true,
            ),
          if (configuration != null) ...[
            const SizedBox(height: 16),
            _SafeConfigurationSummary(configuration: configuration),
          ],
          if (error != null) ...[
            const SizedBox(height: 16),
            GnosisServerErrorBanner(message: error!),
          ],
          const SizedBox(height: 24),
          GnosisResponsiveActions(
            primary: UiPrimaryButton(
              key: const Key('gnosis-safe-primary'),
              text: deployment == null
                  ? LocaleKeys.gnosisCard_safe_start.tr()
                  : failure
                  ? LocaleKeys.gnosisCard_safe_reset.tr()
                  : LocaleKeys.gnosisCard_safe_poll.tr(),
              onPressed: busy
                  ? null
                  : deployment == null
                  ? onStart
                  : failure
                  ? onReset
                  : onPoll,
            ),
            secondary: deployment != null && !failure
                ? UiSecondaryButton(
                    key: const Key('gnosis-safe-reset'),
                    text: LocaleKeys.gnosisCard_safe_reset.tr(),
                    onPressed: busy ? null : onReset,
                  )
                : null,
          ),
        ],
      ),
    );
  }
}

class _SafeConfigurationSummary extends StatelessWidget {
  const _SafeConfigurationSummary({required this.configuration});

  final SafeConfiguration configuration;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      borderRadius: BorderRadius.circular(16),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SummaryRow(
          label: LocaleKeys.gnosisCard_safe_safeAddress.tr(),
          value: _shortAddress(configuration.safeAddress),
        ),
        const SizedBox(height: 8),
        _SummaryRow(
          label: LocaleKeys.gnosisCard_safe_delayModule.tr(),
          value: _shortAddress(configuration.delayModule),
        ),
        const SizedBox(height: 8),
        _SummaryRow(
          label: LocaleKeys.gnosisCard_safe_integrity.tr(),
          value:
              '${configuration.integrity.name} '
              '(${configuration.integrity.code})',
        ),
      ],
    ),
  );
}

class GnosisCardSelectionStep extends StatelessWidget {
  const GnosisCardSelectionStep({
    required this.products,
    required this.busy,
    required this.onSelect,
    this.error,
    super.key,
  });

  final List<GnosisCardProduct> products;
  final bool busy;
  final String? error;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) => GnosisStepCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GnosisStepHeader(
          icon: Icons.style_outlined,
          title: LocaleKeys.gnosisCard_product_title.tr(),
          body: LocaleKeys.gnosisCard_product_body.tr(),
        ),
        const SizedBox(height: 24),
        for (final product in products) ...[
          _ProductCard(
            product: product,
            enabled: !busy,
            onSelect: () => onSelect(product.id),
          ),
          const SizedBox(height: 16),
        ],
        if (error != null) GnosisServerErrorBanner(message: error!),
      ],
    ),
  );
}

class _ProductCard extends StatelessWidget {
  const _ProductCard({
    required this.product,
    required this.enabled,
    required this.onSelect,
  });

  final GnosisCardProduct product;
  final bool enabled;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    final title = product.kind == GnosisCardKind.virtual
        ? LocaleKeys.gnosisCard_product_virtualTitle.tr()
        : LocaleKeys.gnosisCard_product_physicalTitle.tr();
    final body = product.kind == GnosisCardKind.virtual
        ? LocaleKeys.gnosisCard_product_virtualBody.tr()
        : LocaleKeys.gnosisCard_product_physicalBody.tr();
    final price = product.feeMinor == 0
        ? LocaleKeys.gnosisCard_product_included.tr()
        : _money(product.feeMinor, product.currency);
    return Semantics(
      button: true,
      label: '$title, $body, $price',
      child: InkWell(
        onTap: enabled ? onSelect : null,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            border: Border.all(
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                child: Icon(
                  product.kind == GnosisCardKind.virtual
                      ? Icons.language
                      : Icons.contactless_outlined,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 4),
                    Text(body),
                    const SizedBox(height: 8),
                    Text(price, style: Theme.of(context).textTheme.titleSmall),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}

class GnosisVirtualIssuanceStep extends StatelessWidget {
  const GnosisVirtualIssuanceStep({
    required this.busy,
    required this.onIssue,
    this.error,
    super.key,
  });

  final bool busy;
  final String? error;
  final VoidCallback onIssue;

  @override
  Widget build(BuildContext context) => GnosisStepCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GnosisStepHeader(
          icon: Icons.language,
          title: LocaleKeys.gnosisCard_virtual_title.tr(),
          body: LocaleKeys.gnosisCard_virtual_body.tr(),
        ),
        if (error != null) ...[
          const SizedBox(height: 20),
          GnosisServerErrorBanner(message: error!),
        ],
        const SizedBox(height: 24),
        UiPrimaryButton(
          key: const Key('gnosis-virtual-issue'),
          text: LocaleKeys.gnosisCard_virtual_issue.tr(),
          onPressed: busy ? null : onIssue,
        ),
      ],
    ),
  );
}

class GnosisPhysicalShippingStep extends StatefulWidget {
  const GnosisPhysicalShippingStep({
    required this.verifiedCountry,
    required this.busy,
    required this.onSubmit,
    this.initialOrder,
    this.error,
    super.key,
  });

  final String verifiedCountry;
  final bool busy;
  final PhysicalCardOrder? initialOrder;
  final String? error;
  final void Function(String embossedName, ShippingAddress address) onSubmit;

  @override
  State<GnosisPhysicalShippingStep> createState() =>
      _GnosisPhysicalShippingStepState();
}

class _GnosisPhysicalShippingStepState
    extends State<GnosisPhysicalShippingStep> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _address1;
  late final TextEditingController _address2;
  late final TextEditingController _city;
  late final TextEditingController _state;
  late final TextEditingController _postalCode;
  late final TextEditingController _country;

  @override
  void initState() {
    super.initState();
    final order = widget.initialOrder;
    final address = order?.shippingAddress;
    _name = TextEditingController(text: order?.embossedName);
    _address1 = TextEditingController(text: address?.address1);
    _address2 = TextEditingController(text: address?.address2);
    _city = TextEditingController(text: address?.city);
    _state = TextEditingController(text: address?.state);
    _postalCode = TextEditingController(text: address?.postalCode);
    _country = TextEditingController(
      text: address?.country ?? widget.verifiedCountry,
    );
  }

  @override
  void dispose() {
    _name.dispose();
    _address1.dispose();
    _address2.dispose();
    _city.dispose();
    _state.dispose();
    _postalCode.dispose();
    _country.dispose();
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
              icon: Icons.local_shipping_outlined,
              title: LocaleKeys.gnosisCard_shipping_title.tr(),
              body: LocaleKeys.gnosisCard_shipping_body.tr(),
            ),
            const SizedBox(height: 24),
            UiTextFormField(
              key: const Key('gnosis-shipping-name'),
              controller: _name,
              labelText: LocaleKeys.gnosisCard_shipping_name.tr(),
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.name],
              validator: _required,
              enabled: !widget.busy,
            ),
            const SizedBox(height: 12),
            UiTextFormField(
              key: const Key('gnosis-shipping-address1'),
              controller: _address1,
              labelText: LocaleKeys.gnosisCard_shipping_line1.tr(),
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.streetAddressLine1],
              validator: _required,
              enabled: !widget.busy,
            ),
            const SizedBox(height: 12),
            UiTextFormField(
              controller: _address2,
              labelText: LocaleKeys.gnosisCard_shipping_line2.tr(),
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.streetAddressLine2],
              enabled: !widget.busy,
            ),
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, constraints) {
                final city = UiTextFormField(
                  controller: _city,
                  labelText: LocaleKeys.gnosisCard_shipping_city.tr(),
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.addressCity],
                  validator: _required,
                  enabled: !widget.busy,
                );
                final postal = UiTextFormField(
                  controller: _postalCode,
                  labelText: LocaleKeys.gnosisCard_shipping_postalCode.tr(),
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.postalCode],
                  validator: _required,
                  enabled: !widget.busy,
                );
                if (constraints.maxWidth < 520) {
                  return Column(
                    children: [city, const SizedBox(height: 12), postal],
                  );
                }
                return Row(
                  children: [
                    Expanded(child: city),
                    const SizedBox(width: 12),
                    Expanded(child: postal),
                  ],
                );
              },
            ),
            const SizedBox(height: 12),
            UiTextFormField(
              controller: _state,
              labelText: LocaleKeys.gnosisCard_shipping_state.tr(),
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.addressState],
              enabled: !widget.busy,
            ),
            const SizedBox(height: 12),
            UiTextFormField(
              key: const Key('gnosis-shipping-country'),
              controller: _country,
              labelText: LocaleKeys.gnosisCard_shipping_country.tr(),
              textInputAction: TextInputAction.done,
              autofillHints: const [AutofillHints.countryCode],
              validator: _validateCountry,
              enabled: !widget.busy,
              onFieldSubmitted: (_) => _submit(),
            ),
            if (widget.error != null) ...[
              const SizedBox(height: 16),
              GnosisServerErrorBanner(message: widget.error!),
            ],
            const SizedBox(height: 24),
            UiPrimaryButton(
              key: const Key('gnosis-shipping-submit'),
              text: LocaleKeys.gnosisCard_shipping_review.tr(),
              onPressed: widget.busy ? null : _submit,
            ),
          ],
        ),
      ),
    ),
  );

  String? _required(String? value) => (value ?? '').trim().isEmpty
      ? LocaleKeys.gnosisCard_shipping_required.tr()
      : null;

  String? _validateCountry(String? value) {
    final requiredError = _required(value);
    if (requiredError != null) return requiredError;
    if (value!.trim().toUpperCase() != widget.verifiedCountry.toUpperCase()) {
      return LocaleKeys.gnosisCard_shipping_countryMismatch.tr();
    }
    return null;
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    TextInput.finishAutofillContext();
    widget.onSubmit(
      _name.text.trim(),
      ShippingAddress(
        recipientName: _name.text.trim(),
        address1: _address1.text.trim(),
        address2: _emptyAsNull(_address2.text),
        city: _city.text.trim(),
        state: _emptyAsNull(_state.text),
        postalCode: _postalCode.text.trim(),
        country: _country.text.trim().toUpperCase(),
      ),
    );
  }
}

class GnosisPhysicalReviewStep extends StatelessWidget {
  const GnosisPhysicalReviewStep({
    required this.order,
    required this.busy,
    required this.onConfirm,
    required this.onEdit,
    required this.onCancel,
    this.error,
    super.key,
  });

  final PhysicalCardOrder order;
  final bool busy;
  final String? error;
  final VoidCallback onConfirm;
  final VoidCallback onEdit;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) => GnosisStepCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GnosisStepHeader(
          icon: Icons.receipt_long_outlined,
          title: LocaleKeys.gnosisCard_order_reviewTitle.tr(),
          body: LocaleKeys.gnosisCard_order_reviewBody.tr(),
        ),
        const SizedBox(height: 24),
        _OrderSummary(order: order),
        if (error != null) ...[
          const SizedBox(height: 16),
          GnosisServerErrorBanner(message: error!),
        ],
        const SizedBox(height: 24),
        UiPrimaryButton(
          key: const Key('gnosis-order-review-confirm'),
          text: LocaleKeys.gnosisCard_order_placeOrder.tr(),
          onPressed: busy ? null : onConfirm,
        ),
        const SizedBox(height: 12),
        GnosisResponsiveActions(
          primary: UiSecondaryButton(
            text: LocaleKeys.gnosisCard_edit.tr(),
            onPressed: busy ? null : onEdit,
          ),
          secondary: TextButton(
            onPressed: busy || !order.isCancellable ? null : onCancel,
            child: Text(LocaleKeys.gnosisCard_order_cancel.tr()),
          ),
        ),
      ],
    ),
  );
}

class GnosisPhysicalPaymentStep extends StatelessWidget {
  const GnosisPhysicalPaymentStep({
    required this.order,
    required this.quote,
    required this.busy,
    required this.onPay,
    required this.onConfirm,
    required this.onCancel,
    this.receipt,
    this.error,
    super.key,
  });

  final PhysicalCardOrder order;
  final CardOrderPaymentQuote? quote;
  final CardOrderPaymentReceipt? receipt;
  final bool busy;
  final String? error;
  final VoidCallback onPay;
  final VoidCallback onConfirm;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final hasAttachedPayment =
        order.status != PhysicalCardOrderStatus.failedTransaction &&
        (receipt != null ||
            order.transactionHash != null ||
            order.status == PhysicalCardOrderStatus.transactionComplete ||
            order.status == PhysicalCardOrderStatus.confirmationRequired);
    return GnosisStepCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GnosisStepHeader(
            icon: Icons.science_outlined,
            title: LocaleKeys.gnosisCard_payment_title.tr(),
            body: LocaleKeys.gnosisCard_payment_warningBody.tr(),
          ),
          const SizedBox(height: 20),
          GnosisStatusBanner(
            title: LocaleKeys.gnosisCard_payment_warningTitle.tr(),
            message: LocaleKeys.gnosisCard_payment_warningBody.tr(),
            icon: Icons.warning_amber_outlined,
          ),
          const SizedBox(height: 16),
          _SummaryRow(
            label: LocaleKeys.gnosisCard_payment_amount.tr(),
            value: quote == null
                ? _money(order.feeMinor, order.currency)
                : _money(quote!.amountMinor, quote!.currency),
          ),
          if (receipt != null || order.transactionHash != null) ...[
            const SizedBox(height: 12),
            _SummaryRow(
              label: LocaleKeys.gnosisCard_payment_receipt.tr(),
              value: _shortHash(
                receipt?.transactionHash ?? order.transactionHash!,
              ),
            ),
          ],
          if (error != null) ...[
            const SizedBox(height: 16),
            GnosisServerErrorBanner(message: error!),
          ],
          const SizedBox(height: 24),
          UiPrimaryButton(
            key: const Key('gnosis-payment-submit'),
            text: hasAttachedPayment
                ? LocaleKeys.gnosisCard_payment_confirm.tr()
                : error == null
                ? LocaleKeys.gnosisCard_payment_pay.tr()
                : LocaleKeys.gnosisCard_payment_retry.tr(),
            onPressed: busy
                ? null
                : hasAttachedPayment
                ? onConfirm
                : onPay,
          ),
          if (order.isCancellable) ...[
            const SizedBox(height: 12),
            TextButton(
              onPressed: busy ? null : onCancel,
              child: Text(LocaleKeys.gnosisCard_order_cancel.tr()),
            ),
          ],
        ],
      ),
    );
  }
}

class GnosisPhysicalCreationStep extends StatelessWidget {
  const GnosisPhysicalCreationStep({
    required this.busy,
    required this.onCreate,
    this.error,
    super.key,
  });

  final bool busy;
  final String? error;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) => GnosisStepCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GnosisStepHeader(
          icon: Icons.credit_card_outlined,
          title: LocaleKeys.gnosisCard_product_physicalTitle.tr(),
          body: LocaleKeys.gnosisCard_product_physicalBody.tr(),
        ),
        if (error != null) ...[
          const SizedBox(height: 20),
          GnosisServerErrorBanner(message: error!),
        ],
        const SizedBox(height: 24),
        UiPrimaryButton(
          key: const Key('gnosis-physical-create'),
          text: LocaleKeys.create.tr(),
          onPressed: busy ? null : onCreate,
        ),
      ],
    ),
  );
}

class GnosisPhysicalPinStep extends StatelessWidget {
  const GnosisPhysicalPinStep({
    required this.busy,
    required this.onOpen,
    this.wasHandoffCancelled = false,
    this.error,
    super.key,
  });

  final bool busy;
  final bool wasHandoffCancelled;
  final String? error;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) => GnosisStepCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GnosisStepHeader(
          icon: Icons.pin_outlined,
          title: LocaleKeys.gnosisCard_pin_title.tr(),
          body: LocaleKeys.gnosisCard_pin_body.tr(),
        ),
        if (wasHandoffCancelled) ...[
          const SizedBox(height: 20),
          GnosisStatusBanner(
            title: LocaleKeys.gnosisCard_order_resumePin.tr(),
            message: LocaleKeys.gnosisCard_pin_cancelled.tr(),
            icon: Icons.restore,
          ),
        ],
        if (error != null) ...[
          const SizedBox(height: 20),
          GnosisServerErrorBanner(message: error!),
        ],
        const SizedBox(height: 24),
        UiPrimaryButton(
          key: const Key('gnosis-pin-open'),
          text: LocaleKeys.gnosisCard_pin_open.tr(),
          onPressed: busy ? null : onOpen,
        ),
      ],
    ),
  );
}

class _OrderSummary extends StatelessWidget {
  const _OrderSummary({required this.order});

  final PhysicalCardOrder order;

  @override
  Widget build(BuildContext context) {
    final address = order.shippingAddress;
    final addressLines = [
      address.address1,
      if ((address.address2 ?? '').isNotEmpty) address.address2!,
      '${address.postalCode} ${address.city}',
      address.country,
    ];
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SummaryRow(
            label: LocaleKeys.gnosisCard_order_shippingTo.tr(),
            value: '${order.embossedName}\n${addressLines.join('\n')}',
          ),
          const SizedBox(height: 12),
          _SummaryRow(
            label: LocaleKeys.gnosisCard_order_cardFee.tr(),
            value: _money(order.feeMinor, order.currency),
          ),
        ],
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final stack =
          constraints.maxWidth < 480 ||
          MediaQuery.textScalerOf(context).scale(1) >= 1.4;
      final valueText = Text(
        value,
        textAlign: stack ? TextAlign.start : TextAlign.end,
        style: Theme.of(
          context,
        ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
      );
      if (stack) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [Text(label), const SizedBox(height: 4), valueText],
        );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: Text(label)),
          const SizedBox(width: 16),
          Expanded(child: valueText),
        ],
      );
    },
  );
}

String _safeStatusLabel(SafeDeploymentStatus status) => switch (status) {
  SafeDeploymentStatus.accepted => LocaleKeys.gnosisCard_safe_accepted.tr(),
  SafeDeploymentStatus.processing => LocaleKeys.gnosisCard_safe_processing.tr(),
  SafeDeploymentStatus.ok => LocaleKeys.gnosisCard_safe_ready.tr(),
  SafeDeploymentStatus.failed => LocaleKeys.gnosisCard_safe_failed.tr(),
  SafeDeploymentStatus.timedOut => LocaleKeys.gnosisCard_safe_timeout.tr(),
};

String _safeStatusBody(SafeDeploymentStatus status) => switch (status) {
  SafeDeploymentStatus.accepted => LocaleKeys.gnosisCard_safe_accepted.tr(),
  SafeDeploymentStatus.processing => LocaleKeys.gnosisCard_safe_processing.tr(),
  SafeDeploymentStatus.ok => LocaleKeys.gnosisCard_safe_configuration.tr(),
  SafeDeploymentStatus.failed => LocaleKeys.gnosisCard_safe_failed.tr(),
  SafeDeploymentStatus.timedOut => LocaleKeys.gnosisCard_safe_timeout.tr(),
};

String _shortAddress(String? value) {
  if (value == null || value.length < 14) return value ?? '—';
  return '${value.substring(0, 8)}…${value.substring(value.length - 6)}';
}

String _shortHash(String value) {
  if (value.length < 18) return value;
  return '${value.substring(0, 10)}…${value.substring(value.length - 8)}';
}

String _money(int minor, String currency) =>
    '$currency ${(minor / 100).toStringAsFixed(2)}';

String? _emptyAsNull(String value) {
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}
