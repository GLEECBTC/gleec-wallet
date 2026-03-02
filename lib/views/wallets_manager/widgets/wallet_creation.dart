import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:web_dex/bloc/auth_bloc/auth_bloc.dart';
import 'package:web_dex/blocs/wallets_repository.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/model/wallet.dart';
import 'package:web_dex/model/wallets_manager_models.dart';
import 'package:komodo_ui_kit/komodo_ui_kit.dart';

import 'package:web_dex/shared/widgets/disclaimer/eula_tos_checkboxes.dart';
import 'package:web_dex/shared/widgets/quick_login_switch.dart';
import 'package:web_dex/views/wallets_manager/widgets/creation_password_fields.dart';
import 'package:web_dex/shared/screenshot/screenshot_sensitivity.dart';

class WalletCreation extends StatefulWidget {
  const WalletCreation({
    super.key,
    required this.action,
    required this.onCreate,
    required this.onCancel,
  });

  final WalletsManagerAction action;
  final void Function({
    required String name,
    required String password,
    WalletType? walletType,
    required bool rememberMe,
  })
  onCreate;
  final void Function() onCancel;

  @override
  State<WalletCreation> createState() => _WalletCreationState();
}

class _WalletCreationState extends State<WalletCreation> {
  final TextEditingController _nameController = TextEditingController(text: '');
  final TextEditingController _passwordController = TextEditingController(
    text: '',
  );
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  bool _eulaAndTosChecked = false;
  bool _inProgress = false;
  bool _rememberMe = false;
  bool _arePasswordsValid = false;

  late final WalletsRepository _walletsRepository;

  @override
  void initState() {
    super.initState();

    _nameController.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _walletsRepository = context.read<WalletsRepository>();
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<AuthBloc, AuthBlocState>(
      listener: (context, state) {
        if (!state.isLoading) {
          setState(() => _inProgress = false);
        }

        if (state.isError) {
          final theme = Theme.of(context);
          final message =
              state.authError?.message ?? LocaleKeys.somethingWrong.tr();

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                message,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.colorScheme.onErrorContainer,
                ),
              ),
              backgroundColor: theme.colorScheme.errorContainer,
            ),
          );
        }
      },
      child: AutofillGroup(
        child: ScreenshotSensitive(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.action == WalletsManagerAction.create
                      ? LocaleKeys.walletCreationTitle.tr()
                      : LocaleKeys.walletImportTitle.tr(),
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontSize: 18),
                ),
                const SizedBox(height: 24),
                _buildFields(),
                const SizedBox(height: 22),
                EulaTosCheckboxes(
                  key: const Key('create-wallet-eula-checks'),
                  isChecked: _eulaAndTosChecked,
                  onCheck: (isChecked) {
                    setState(() {
                      _eulaAndTosChecked = isChecked;
                    });
                  },
                ),
                const SizedBox(height: 32),
                UiPrimaryButton(
                  key: const Key('confirm-password-button'),
                  height: 50,
                  text: _inProgress
                      ? '${LocaleKeys.pleaseWait.tr()}...'
                      : LocaleKeys.create.tr(),
                  textStyle: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                  onPressed: _isCreateButtonEnabled ? _onCreate : null,
                ),
                const SizedBox(height: 20),
                UiUnderlineTextButton(
                  onPressed: widget.onCancel,
                  text: LocaleKeys.cancel.tr(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Widget _buildFields() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildNameField(),
        const SizedBox(height: 20),
        const UiDivider(),
        const SizedBox(height: 20),
        CreationPasswordFields(
          passwordController: _passwordController,
          onValidityChanged: (isValid) {
            if (mounted) setState(() => _arePasswordsValid = isValid);
          },
          onFieldSubmitted: (_) {
            if (_isCreateButtonEnabled) _onCreate();
          },
        ),
        const SizedBox(height: 20),
        QuickLoginSwitch(
          key: const Key('checkbox-one-click-login-signup'),
          value: _rememberMe,
          onChanged: (value) {
            setState(() => _rememberMe = value);
          },
        ),
      ],
    );
  }

  Widget _buildNameField() {
    final walletsRepository = _walletsRepository;
    return UiTextFormField(
      key: const Key('name-wallet-field'),
      controller: _nameController,
      autofocus: true,
      autocorrect: false,
      textInputAction: TextInputAction.next,
      enableInteractiveSelection: true,
      autofillHints: const [AutofillHints.username],
      validator: (String? name) =>
          _inProgress ? null : walletsRepository.validateWalletName(name ?? ''),
      inputFormatters: [LengthLimitingTextInputFormatter(40)],
      hintText: LocaleKeys.walletCreationNameHint.tr(),
    );
  }

  void _onCreate() async {
    if (!_eulaAndTosChecked) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _inProgress = true);
    // Async uniqueness check before proceeding
    final uniquenessError = await _walletsRepository
        .validateWalletNameUniqueness(_nameController.text);
    if (uniquenessError != null) {
      if (mounted) {
        setState(() => _inProgress = false);
        final theme = Theme.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              uniquenessError,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.onErrorContainer,
              ),
            ),
            backgroundColor: theme.colorScheme.errorContainer,
          ),
        );
      }
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((timeStamp) {
      // Complete autofill session so password managers can save new credentials
      TextInput.finishAutofillContext(shouldSave: true);
      widget.onCreate(
        name: _nameController.text.trim(),
        password: _passwordController.text,
        walletType: WalletType.hdwallet,
        rememberMe: _rememberMe,
      );
    });
  }

  bool get _isCreateButtonEnabled {
    final nameError = _walletsRepository.validateWalletName(
      _nameController.text,
    );
    final isNameValid = nameError == null;
    return _eulaAndTosChecked &&
        !_inProgress &&
        isNameValid &&
        _arePasswordsValid;
  }
}
