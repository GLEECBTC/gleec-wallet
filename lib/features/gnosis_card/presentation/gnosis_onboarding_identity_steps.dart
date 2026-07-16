part of 'gnosis_onboarding_steps.dart';

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
              itemHeight: null,
              decoration: InputDecoration(labelText: question.title),
              items: question.answers
                  .map(
                    (answer) => DropdownMenuItem(
                      value: answer,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Text(answer, maxLines: 3),
                      ),
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
    required this.verifiedCallingCode,
    this.verifiedCountry = 'DE',
    this.initialPhone,
    this.error,
    super.key,
  });

  final bool busy;
  final String verifiedCountry;
  final String verifiedCallingCode;
  final String? initialPhone;
  final String? error;
  final ValueChanged<String> onSubmit;

  @override
  State<GnosisPhoneNumberStep> createState() => _GnosisPhoneNumberStepState();
}

class _GnosisPhoneNumberStepState extends State<GnosisPhoneNumberStep> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _controller;
  late String _country;
  bool _confirming = false;

  @override
  void initState() {
    super.initState();
    _country = _countryForPhone(
      widget.initialPhone,
      fallback: widget.verifiedCountry,
    );
    final dialCode = _dialCodeFor(_country);
    final initial = widget.initialPhone ?? '';
    _controller = TextEditingController(
      text: initial.startsWith(dialCode)
          ? initial.substring(dialCode.length)
          : initial,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String get _normalized {
    final raw = _controller.text.replaceAll(RegExp(r'[\s\-()]'), '');
    if (raw.startsWith('+')) return raw;
    final national = raw.replaceFirst(RegExp(r'^0+'), '');
    return '${_dialCodeFor(_country)}$national';
  }

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
                ? '${LocaleKeys.gnosisCard_phone_confirmBody.tr()} '
                      '${_maskedPhone(_normalized)}'
                : LocaleKeys.gnosisCard_phone_body.tr(),
          ),
          const SizedBox(height: 24),
          if (!_confirming)
            LayoutBuilder(
              builder: (context, constraints) {
                final country = DropdownButtonFormField<String>(
                  initialValue: _country,
                  decoration: InputDecoration(
                    labelText: 'gnosisCard.phone.countryCode'.tr(),
                  ),
                  items: [
                    for (final entry in _availableDialCodes.entries)
                      DropdownMenuItem(
                        value: entry.key,
                        child: Text(
                          '${_countryLabel(entry.key)}  '
                          '${entry.value.isEmpty ? '+' : entry.value}',
                        ),
                      ),
                  ],
                  onChanged: widget.busy
                      ? null
                      : (value) {
                          if (value != null) {
                            setState(() => _country = value);
                          }
                        },
                );
                final number = UiTextFormField(
                  key: const Key('gnosis-phone-number'),
                  controller: _controller,
                  labelText: LocaleKeys.gnosisCard_phone_numberLabel.tr(),
                  hintText: LocaleKeys.gnosisCard_phone_numberHint.tr(),
                  keyboardType: TextInputType.phone,
                  textInputAction: TextInputAction.done,
                  autofillHints: const [AutofillHints.telephoneNumberNational],
                  inputFormatters: [
                    _PhoneNumberFormatter(
                      allowInternationalPrefix: _dialCodeFor(_country).isEmpty,
                    ),
                    LengthLimitingTextInputFormatter(20),
                  ],
                  validator: _validatePhone,
                  enabled: !widget.busy,
                  onFieldSubmitted: (_) => _showConfirmation(),
                );
                if (constraints.maxWidth < 520) {
                  return Column(
                    children: [country, const SizedBox(height: 12), number],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(width: 150, child: country),
                    const SizedBox(width: 12),
                    Expanded(child: number),
                  ],
                );
              },
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

  Map<String, String> get _availableDialCodes => {
    ..._phoneDialCodes,
    widget.verifiedCountry.toUpperCase(): widget.verifiedCallingCode,
  };

  String _dialCodeFor(String country) =>
      country == widget.verifiedCountry.toUpperCase()
      ? widget.verifiedCallingCode
      : _phoneDialCodes[country] ?? '';

  String _countryLabel(String country) {
    final key = 'gnosisCard.countries.$country';
    final localized = key.tr();
    return localized == key ? country : localized;
  }

  void _showConfirmation() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _confirming = true);
  }
}

const _phoneDialCodes = <String, String>{
  'DE': '+49',
  'FR': '+33',
  'GB': '+44',
  'NL': '+31',
  'ES': '+34',
  'IT': '+39',
};

String _countryForPhone(String? phone, {required String fallback}) {
  if (phone != null) {
    for (final entry in _phoneDialCodes.entries) {
      if (phone.startsWith(entry.value)) return entry.key;
    }
  }
  return fallback.toUpperCase();
}

String _maskedPhone(String phone) {
  if (phone.length <= 6) return phone;
  return '${phone.substring(0, 3)} •••• ${phone.substring(phone.length - 4)}';
}

class _PhoneNumberFormatter extends TextInputFormatter {
  const _PhoneNumberFormatter({required this.allowInternationalPrefix});

  final bool allowInternationalPrefix;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final hasPlus =
        allowInternationalPrefix && newValue.text.trimLeft().startsWith('+');
    final digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    final groups = <String>[];
    var offset = 0;
    while (offset < digits.length) {
      final remaining = digits.length - offset;
      final groupLength = remaining > 3 ? 3 : remaining;
      groups.add(digits.substring(offset, offset + groupLength));
      offset += groupLength;
    }
    final formatted = '${hasPlus ? '+' : ''}${groups.join(' ')}';
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}
