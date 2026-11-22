import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:komodo_ui_kit/komodo_ui_kit.dart';
import 'package:web_dex/bloc/auth_bloc/auth_bloc.dart';
import 'package:web_dex/bloc/security_settings/security_settings_bloc.dart';
import 'package:web_dex/bloc/security_settings/security_settings_event.dart';
import 'package:web_dex/common/screen.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/model/wallet.dart';
import 'package:web_dex/services/wallet_access/wallet_access_service.dart';
import 'package:web_dex/services/wallet_access/wallet_lock_policy.dart';
import 'package:web_dex/shared/constants.dart';
import 'package:web_dex/shared/utils/validators.dart';
import 'package:web_dex/shared/widgets/password_visibility_control.dart';
import 'package:web_dex/views/common/page_header/page_header.dart';
import 'package:web_dex/views/common/wallet_access/wallet_access_feedback.dart';

part 'password_update_fields.dart';

class PasswordUpdatePage extends StatefulWidget {
  const PasswordUpdatePage({super.key});

  @override
  State<PasswordUpdatePage> createState() => _PasswordUpdatePageState();
}

class _PasswordUpdatePageState extends State<PasswordUpdatePage> {
  /// Set once the engine uses the new password.
  PasswordChangeOutcome? _outcome;
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bloc = context.read<SecuritySettingsBloc>();
    const event = ResetEvent();
    gotoSecurityMain() => bloc.add(event);

    final outcome = _outcome;
    final Widget pageContent = outcome != null
        ? _SuccessView(outcome: outcome, back: gotoSecurityMain)
        : _FormView(onSuccess: (outcome) => setState(() => _outcome = outcome));
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface.withValues(alpha: .3),
        borderRadius: BorderRadius.circular(18.0),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isNotMobile)
            PageHeader(
              onBackButtonPressed: gotoSecurityMain,
              backText: LocaleKeys.back.tr(),
              title: LocaleKeys.changingWalletPassword.tr(),
            ),
          const SizedBox(height: 28),
          Flexible(
            child: DexScrollbar(
              isMobile: isMobile,
              scrollController: _scrollController,
              child: SingleChildScrollView(
                controller: _scrollController,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      if (isMobile) ...{
                        Text(
                          '${LocaleKeys.changingWalletPassword.tr()} ',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 15),
                      },
                      Text(
                        LocaleKeys.changingWalletPasswordDescription.tr(),
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'authPasswordChangeDisclosure'.tr(),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 21),
                      pageContent,
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FormView extends StatefulWidget {
  const _FormView({required this.onSuccess});

  final ValueChanged<PasswordChangeOutcome> onSuccess;

  @override
  State<_FormView> createState() => _FormViewState();
}

class _FormViewState extends State<_FormView> with WidgetsBindingObserver {
  bool _isObscured = true;
  final _oldController = TextEditingController();
  final _newController = TextEditingController();
  final _confirmController = TextEditingController();
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  String? _error;
  WalletAccessTone _errorTone = WalletAccessTone.error;
  bool _busy = false;
  bool _managed = false;
  WalletId? _walletId;
  Future<WalletAccessStatus?>? _accessStatus;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Clicking another window on desktop or web is not leaving: a password
    // being typed, or pasted from a manager beside the app, must survive it.
    if (!lifecycleLeavesApp(state)) return;
    _oldController.clear();
    _newController.clear();
    _confirmController.clear();
    if (mounted) setState(() => _isObscured = true);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _oldController.clear();
    _newController.clear();
    _confirmController.clear();
    _oldController.dispose();
    _newController.dispose();
    _confirmController.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final walletId = context.read<AuthBloc>().state.currentUser?.walletId;
    if (_walletId != walletId || _accessStatus == null) {
      _walletId = walletId;
      _accessStatus =
          context.read<WalletAccessService?>()?.status(walletId: walletId) ??
          Future<WalletAccessStatus?>.value();
    }
    return FutureBuilder<WalletAccessStatus?>(
      future: _accessStatus,
      builder: (context, snapshot) {
        _managed = snapshot.data?.hasManagedCredential == true;
        if (snapshot.connectionState != ConnectionState.done) {
          return Center(
            child: WalletAccessProgress(label: 'authProtectionChecking'.tr()),
          );
        }
        return AutofillGroup(
          onDisposeAction: AutofillContextAction.cancel,
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Offstage(
                  child: ExcludeFocus(
                    child: ExcludeSemantics(
                      child: TextFormField(
                        key: const Key('password-update-autofill-username'),
                        initialValue: snapshot.data?.entryId == null
                            ? _walletId?.name
                            : 'gleec-${snapshot.data!.entryId}',
                        readOnly: true,
                        autofillHints: const [AutofillHints.username],
                      ),
                    ),
                  ),
                ),
                if (_managed) ...[
                  WalletAccessNotice(
                    text: 'authPersonalPasswordOptional'.tr(),
                    announce: false,
                  ),
                  const SizedBox(height: 16),
                ] else
                  _CurrentField(
                    controller: _oldController,
                    isObscured: _isObscured,
                    onVisibilityChange: _onVisibilityChange,
                    formKey: _formKey,
                  ),
                const SizedBox(height: 30),
                _NewField(
                  controller: _newController,
                  isObscured: _isObscured,
                  onVisibilityChange: _onVisibilityChange,
                ),
                const SizedBox(height: 20),
                _ConfirmField(
                  confirmController: _confirmController,
                  newController: _newController,
                  isObscured: _isObscured,
                  onVisibilityChange: _onVisibilityChange,
                  onSubmitted: _onUpdate,
                ),
                const SizedBox(height: 30),
                if (_error != null) ...[
                  WalletAccessNotice(
                    key: const Key('password-update-error'),
                    text: _error!,
                    tone: _errorTone,
                  ),
                  const SizedBox(height: 12),
                ],
                // Stays enabled while busy: a disabled button drops keyboard
                // focus, and a failed change should leave the user on it.
                UiPrimaryButton(
                  key: const Key('password-update-submit'),
                  expandForText: true,
                  onPressed: _onUpdate,
                  text: _busy
                      ? LocaleKeys.pleaseWait.tr()
                      : LocaleKeys.updatePassword.tr(),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _onUpdate() async {
    if (_busy || !(_formKey.currentState?.validate() ?? false)) return;
    final expected = _walletId;
    final owner = context.read<AuthBloc>().state.currentUser;
    if (expected == null || owner == null) return;
    final expectedEntry = WalletAccessService.entryId(owner);
    final currentPassword = _managed ? null : _oldController.text;
    final newPassword = _newController.text;

    if (currentPassword == newPassword) {
      setState(() {
        _error = LocaleKeys.usedSamePassword.tr();
        _errorTone = WalletAccessTone.error;
      });
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final access = context.read<WalletAccessService?>();
      var outcome = PasswordChangeOutcome.completed;
      if (access != null) {
        outcome = await access.changePasswordWithOutcome(
          walletId: expected,
          currentPassword: currentPassword,
          newPassword: newPassword,
        );
      } else {
        await context.read<KomodoDefiSdk>().auth.updatePassword(
          currentPassword: currentPassword!,
          newPassword: newPassword,
          expectedWalletId: expected,
        );
      }
      if (!_ownsWallet(expected, expectedEntry)) return;
      setState(() => _error = null);
      await _requestPasswordManagerUpdate(
        access,
        expected,
        expectedEntry,
        newPassword,
      );
      if (!_ownsWallet(expected, expectedEntry)) return;
      _newController.clear();
      _confirmController.clear();
      // The stored credential may no longer follow the password, so whether
      // the wallet is opened for the user is read again, not remembered.
      _accessStatus = null;
      widget.onSuccess(outcome);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        // Cancelling the confirmation is the user's own choice, not a fault.
        _errorTone =
            e is WalletAccessException &&
                e.failure == WalletAccessFailure.canceled
            ? WalletAccessTone.info
            : WalletAccessTone.error;
        if (e is! AuthException) {
          _error = walletAccessFailureText(
            e,
            passwordEntered: currentPassword != null,
            unlocking: false,
          );
          return;
        }

        switch (e.type) {
          case AuthExceptionType.incorrectPassword:
            _error = LocaleKeys.incorrectPassword.tr();
            break;
          case AuthExceptionType.unauthorized:
            _error = LocaleKeys.noActiveWallet.tr();
            break;
          case AuthExceptionType.apiConnectionError:
            _error = LocaleKeys.activationFailedMessage.tr();
            break;
          default:
            _error = LocaleKeys.passwordNotAccepted.tr();
        }
      });
    } finally {
      if (mounted) {
        _oldController.clear();
        setState(() => _busy = false);
      }
    }
  }

  bool _ownsWallet(WalletId id, String entry) {
    if (!mounted) return false;
    final user = context.read<AuthBloc>().state.currentUser;
    return user?.walletId == id &&
        user != null &&
        WalletAccessService.entryId(user) == entry;
  }

  Future<void> _requestPasswordManagerUpdate(
    WalletAccessService? access,
    WalletId id,
    String entry,
    String password,
  ) async {
    try {
      if (!_ownsWallet(id, entry)) return;
      if (access != null) {
        final outcome = await access.saveToPasswordManager(
          walletId: id,
          password: password,
        );
        if (outcome != PasswordManagerOutcome.unavailable) {
          TextInput.finishAutofillContext(shouldSave: false);
          return;
        }
      }
      if (!_ownsWallet(id, entry)) return;
      final ensureCurrent = access?.captureSensitiveOperation(id);
      // Device confirmation may have cleared these controllers. Restore only
      // after the fields are obscured, then submit the actual committed value
      // through the ordinary autofill form. Never focus a hidden input.
      setState(() => _isObscured = true);
      await WidgetsBinding.instance.endOfFrame;
      if (!_ownsWallet(id, entry)) return;
      ensureCurrent?.call();
      _newController.text = password;
      _confirmController.text = password;
      await WidgetsBinding.instance.endOfFrame;
      if (!_ownsWallet(id, entry)) return;
      ensureCurrent?.call();
      TextInput.finishAutofillContext();
      await access?.recordPasswordManagerOutcome(
        walletId: id,
        outcome: PasswordManagerOutcome.unknown,
      );
    } catch (_) {
      // The password change is committed. Optional provider failures never
      // roll it back or turn success into a misleading password error.
      TextInput.finishAutofillContext(shouldSave: false);
    } finally {
      if (mounted) {
        _newController.clear();
        _confirmController.clear();
      }
    }
  }

  void _onVisibilityChange(bool isPasswordObscured) {
    setState(() {
      _isObscured = isPasswordObscured;
    });
  }
}
