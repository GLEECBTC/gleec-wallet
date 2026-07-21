part of 'gnosis_onboarding_steps.dart';

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
        : _money(context, product.feeMinor, product.currency);
    return Semantics(
      button: true,
      enabled: enabled,
      label: '$title, $body, $price',
      child: InkWell(
        onTap: enabled ? onSelect : null,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            border: Border.all(color: _gnosisBorderColor(context)),
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
        if (error == null || busy)
          GnosisProgressIndicator(
            label: LocaleKeys.gnosisCard_virtual_title.tr(),
          )
        else
          UiPrimaryButton(
            key: const Key('gnosis-virtual-issue'),
            text: LocaleKeys.gnosisCard_retrySafely.tr(),
            onPressed: onIssue,
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
    this.verifiedAddress,
    this.error,
    super.key,
  });

  final String verifiedCountry;
  final bool busy;
  final PhysicalCardOrder? initialOrder;
  final ShippingAddress? verifiedAddress;
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
    final address = order?.shippingAddress ?? widget.verifiedAddress;
    _name = TextEditingController(
      text: order?.embossedName ?? address?.recipientName,
    );
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
              readOnly: true,
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
