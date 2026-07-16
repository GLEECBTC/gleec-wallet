part of 'gnosis_onboarding_steps.dart';

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
  String? _lastSubmittedCode;

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  @override
  void didUpdateWidget(covariant GnosisPhoneOtpStep oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.challenge.resendAvailableAt !=
            widget.challenge.resendAvailableAt ||
        oldWidget.challenge.expiresAt != widget.challenge.expiresAt) {
      _lastSubmittedCode = null;
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

  int get _secondsUntilExpiry {
    final difference = widget.challenge.expiresAt.difference(DateTime.now());
    return difference.isNegative ? 0 : difference.inSeconds + 1;
  }

  bool get _isExpired => _secondsUntilExpiry == 0;
  bool get _isLocked => widget.challenge.attemptsRemaining <= 0;
  bool get _isTerminal => _isExpired || _isLocked;

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
                '${_maskedPhone(widget.challenge.phoneNumber)}',
          ),
          if (widget.challenge.demoCode != null) ...[
            const SizedBox(height: 20),
            GnosisStatusBanner(
              title: LocaleKeys.gnosisCard_phone_demoCode.tr(
                args: [widget.challenge.demoCode!],
              ),
              message: LocaleKeys.gnosisCard_phone_demoCodeHint.tr(),
              icon: Icons.science_outlined,
            ),
          ],
          const SizedBox(height: 24),
          GnosisStatusBanner(
            title: _isLocked
                ? 'gnosisCard.phone.attemptsExhausted'.tr()
                : _isExpired
                ? 'gnosisCard.phone.expired'.tr()
                : _secondsUntilExpiry == 1
                ? 'gnosisCard.phone.expiresInOne'.tr()
                : 'gnosisCard.phone.expiresIn'.tr(
                    args: ['$_secondsUntilExpiry'],
                  ),
            message: _isLocked
                ? 'gnosisCard.phone.requestNewCode'.tr()
                : widget.challenge.attemptsRemaining == 1
                ? 'gnosisCard.phone.attemptRemainingOne'.tr()
                : 'gnosisCard.phone.attemptsRemaining'.tr(
                    args: ['${widget.challenge.attemptsRemaining}'],
                  ),
            icon: _isTerminal ? Icons.timer_off_outlined : Icons.timer_outlined,
            isError: _isTerminal,
            isLiveRegion: _isTerminal,
          ),
          const SizedBox(height: 16),
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
            enabled: !widget.busy && !_isTerminal,
            onChanged: (value) {
              if (value != _lastSubmittedCode) _lastSubmittedCode = null;
              if (!widget.busy && (value?.length ?? 0) == 6) {
                scheduleMicrotask(_verify);
              }
            },
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
            onPressed: widget.busy || _isTerminal ? null : _verify,
          ),
          const SizedBox(height: 12),
          GnosisResponsiveActions(
            primary: UiSecondaryButton(
              key: const Key('gnosis-phone-resend'),
              text: _secondsRemaining == 0
                  ? LocaleKeys.gnosisCard_phone_resend.tr()
                  : _secondsRemaining == 1
                  ? 'gnosisCard.phone.resendInOne'.tr()
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
    if (_isTerminal || widget.busy) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final code = _controller.text;
    if (_lastSubmittedCode == code) return;
    _lastSubmittedCode = code;
    widget.onVerify(code);
  }

  void _startTimer() {
    _timer?.cancel();
    if (_secondsRemaining == 0 && _secondsUntilExpiry == 0) return;
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted || (_secondsRemaining == 0 && _secondsUntilExpiry == 0)) {
        timer.cancel();
      }
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
    required this.onRetry,
    required this.onSupport,
    this.requiresSupport = false,
    this.error,
    super.key,
  });

  final GnosisOnboardingProgress progress;
  final bool busy;
  final String? error;
  final VoidCallback onRetry;
  final VoidCallback onSupport;
  final bool requiresSupport;

  @override
  Widget build(BuildContext context) {
    final deployment = progress.safeDeployment;
    final configuration = progress.safeConfiguration;
    final failure =
        error != null ||
        deployment?.status == SafeDeploymentStatus.failed ||
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
                  ? error ??
                        (configuration != null && !configuration.isValid
                            ? LocaleKeys.gnosisCard_safe_invalidIntegrity.tr()
                            : LocaleKeys.gnosisCard_safe_failed.tr())
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
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: Text('gnosisCard.dashboard.accountDetails'.tr()),
              children: [
                _SafeConfigurationSummary(configuration: configuration),
              ],
            ),
          ],
          if (error != null) ...[
            const SizedBox(height: 16),
            GnosisServerErrorBanner(message: error!),
          ],
          const SizedBox(height: 24),
          if (busy || !failure)
            GnosisProgressIndicator(
              label: LocaleKeys.gnosisCard_safe_title.tr(),
            )
          else
            UiPrimaryButton(
              key: const Key('gnosis-safe-primary'),
              text: requiresSupport
                  ? LocaleKeys.gnosisCard_openSupport.tr()
                  : LocaleKeys.gnosisCard_retrySafely.tr(),
              onPressed: requiresSupport ? onSupport : onRetry,
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
      border: Border.all(color: _gnosisBorderColor(context)),
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
          value: configuration.isValid
              ? LocaleKeys.gnosisCard_safe_validIntegrity.tr()
              : LocaleKeys.gnosisCard_safe_invalidIntegrity.tr(),
        ),
      ],
    ),
  );
}
