import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/bloc/security_settings/security_settings_bloc.dart';
import 'package:web_dex/bloc/security_settings/security_settings_event.dart';
import 'package:web_dex/bloc/security_settings/security_settings_state.dart';
import 'package:web_dex/model/wallet.dart';
import 'package:web_dex/services/wallet_access/unlock_coordinator.dart';
import 'package:web_dex/services/wallet_access/wallet_access_service.dart';
import 'package:web_dex/services/wallet_access/wallet_operation_gate.dart';

KdfUser accessibilityUser() => KdfUser(
  walletId: WalletId.withPubkeyHash(
    'Gleec Wallet',
    const AuthOptions(derivationMethod: DerivationMethod.hdWallet),
    'accessibility-fixture',
  ),
  isBip39Seed: true,
  metadata: const {'type': 'hdwallet'},
);

class AccessibilityAccess extends Fake implements WalletAccessService {
  @override
  bool get isPasswordManagerPending => false;
  bool protected = true;
  final renamed = <String>[];
  final authorized = <String?>[];
  final outcomes = <PasswordManagerOutcome>[];
  @override
  final unlockCoordinator = WalletUnlockCoordinator(
    operationGate: WalletOperationGate(),
  );
  @override
  Stream<void> get changes => const Stream.empty();
  @override
  Future<bool> get hasPendingCredentialCleanup async => false;
  @override
  Future<WalletAccessStatus> status({WalletId? walletId}) async =>
      WalletAccessStatus(
        entryId: 'accessibility-entry',
        protection: protected
            ? CredentialProtection.authenticationBound
            : CredentialProtection.browserLocal,
        hasManagedCredential: true,
        requiresAuthentication: protected,
        generatedPassword: true,
      );
  @override
  Future<WalletAccessStatus> statusForWallet(Wallet wallet) => status();
  @override
  Future<CredentialCapabilities> capabilities() async =>
      const CredentialCapabilities(
        available: true,
        protection: CredentialProtection.authenticationBound,
        deviceAuthentication: true,
        passkeyCandidate: true,
      );
  @override
  Future<String> authorize({
    required WalletId walletId,
    String? password,
    String reason = 'Unlock your wallet',
  }) async {
    authorized.add(password);
    return 'synthetic-a11y-password';
  }

  @override
  void Function() captureSensitiveOperation(WalletId walletId) {
    final generation = unlockCoordinator.state.generation;
    final authorization = unlockCoordinator.authorizationGeneration;
    final entry = unlockCoordinator.state.walletEntryId;
    final permit = entry == null
        ? null
        : unlockCoordinator.operationGate.capture(expectedWalletEntryId: entry);
    void ensureCurrent() {
      final state = unlockCoordinator.state;
      if (walletId != accessibilityUser().walletId ||
          state.generation != generation ||
          unlockCoordinator.authorizationGeneration != authorization ||
          state.isLocked ||
          !state.isForeground) {
        throw const WalletAccessException(WalletAccessFailure.staleOperation);
      }
      permit?.ensureCurrent();
    }

    ensureCurrent();
    return ensureCurrent;
  }

  @override
  Future<bool> unlockCurrent({String? password, bool automatic = false}) async {
    final attempt = unlockCoordinator.beginUnlock(automatic: automatic);
    if (attempt == null) return false;
    await authorize(walletId: accessibilityUser().walletId, password: password);
    return unlockCoordinator.completeUnlock(attempt);
  }

  @override
  Future<void> renameDisplayName({
    required WalletId walletId,
    required String name,
    String? password,
  }) async => renamed.add(name);
  @override
  Future<PasswordManagerOutcome> saveToPasswordManager({
    required WalletId walletId,
    String? password,
  }) async => PasswordManagerOutcome.unavailable;
  @override
  Future<void> recordPasswordManagerOutcome({
    required WalletId walletId,
    required PasswordManagerOutcome outcome,
  }) async => outcomes.add(outcome);
}

class AccessibilitySecurity extends Cubit<SecuritySettingsState>
    implements SecuritySettingsBloc {
  AccessibilitySecurity() : super(SecuritySettingsState.initialState());
  final events = <SecuritySettingsEvent>[];
  @override
  void add(SecuritySettingsEvent event) => events.add(event);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
