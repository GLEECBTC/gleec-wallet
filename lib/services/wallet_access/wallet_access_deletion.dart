part of 'wallet_access_service.dart';

/// Preparing the removal of a wallet's stored credential. Nothing here
/// removes it: that follows only a deletion the engine has committed, and the
/// engine commits only for the wallet password.
extension _DeletionPreparation on WalletAccessService {
  Future<String> _credentialForDeletion(Wallet wallet, String? password) =>
      _runAccessOperation((revision) async {
        final user = await _resolveWallet(wallet);
        final record = await _recordFor(WalletAccessService.entryId(user));
        var value = password;
        if (value == null) {
          if (record == null || !record.managed) {
            throw const WalletAccessException(
              WalletAccessFailure.missingCredential,
            );
          }
          value = await _readManaged(
            record,
            reason: 'Remove this wallet from this device',
            revision: revision,
            purpose: 'delete',
          );
        }
        _ensureRevision(revision);
        if (WalletAccessService.entryId(await _resolveWallet(wallet)) !=
            WalletAccessService.entryId(user)) {
          throw const WalletAccessException(WalletAccessFailure.staleOperation);
        }
        final preparationStartedAt = _monotonicNow();
        if (record != null) {
          _ensureRevision(revision);
          String? token;
          CredentialRecordInfo? actual;
          var vaultItemGone = false;
          // A record a password change left unmanaged can still have a
          // passkey envelope beside it, which only the password path below
          // can authorize removing once the provider is gone.
          final current = await _sdk.auth.currentUser;
          final open =
              current != null &&
              WalletAccessService.entryId(current) ==
                  WalletAccessService.entryId(user);
          if (password != null && (record.managed || open)) {
            try {
              actual = await _backend.metadata(record.credentialKey);
              vaultItemGone = actual == null;
            } on WalletAccessException catch (error) {
              // A key the system invalidated has no readable metadata, yet
              // its leftover can still be authorized for removal below. The
              // unmanaged probe is best effort and never blocks the deletion.
              if (record.managed &&
                  error.failure != WalletAccessFailure.invalidated) {
                rethrow;
              }
            }
          }
          if (actual?.protection == CredentialProtection.passkey) {
            // A lost provider need not prevent removal after genuine password
            // proof. Verification is for the active wallet only: never switch
            // the engine silently to authorize deletion of another entry.
            final current = await _sdk.auth.currentUser;
            if (current == null ||
                WalletAccessService.entryId(current) !=
                    WalletAccessService.entryId(user) ||
                current.walletId != user.walletId) {
              throw const WalletAccessException(
                WalletAccessFailure.walletMustBeUnlocked,
              );
            }
            final session = await _sdk.auth.captureSessionContext();
            await _authorize(
              user.walletId,
              password: value,
              reason: 'Remove this wallet from this device',
              revision: revision,
            );
            await _ensureUserCurrent(user, session, revision);
            token = await _backend.prepareDeleteAfterPasswordVerification(
              record.credentialKey,
              expectedRevision: actual!.revision,
            );
            await _ensureUserCurrent(user, session, revision);
          } else if (record.managed && !vaultItemGone) {
            final requiresAuthentication =
                record.requiresAuthentication || actual?.enrolled == true;
            token = await unlockCoordinator.runSystemPrompt(() async {
              final token = await _backend.prepareDelete(
                record.credentialKey,
                reason: 'Remove this wallet from this device',
              );
              if (token == null && requiresAuthentication) {
                throw const WalletAccessException(
                  WalletAccessFailure.invalidResponse,
                );
              }
              return token;
            }, waitForForeground: requiresAuthentication);
          }
          // With the vault item already gone there is nothing to authorize:
          // only the record is left, to go with the wallet.
          _ensureRevision(revision);
          await _cleanup.prepare(
            record.copyWith(
              walletName: user.walletId.name,
              pubkeyHash: user.walletId.pubkeyHash,
            ),
            token,
          );
        }
        _ensureRevision(revision);
        final id = WalletAccessService.entryId(user);
        _preparedDeletionIds[jsonEncode([
              user.walletId.name,
              user.walletId.pubkeyHash,
            ])] =
            id;
        _preparedDeletionScopes[id] = _PreparedDeletionAuthorization(
          revision,
          unlockCoordinator.state.generation,
          preparationStartedAt + const Duration(seconds: 60),
        );
        return value;
      });

  Future<void> _abandonDeletion(Wallet wallet) async {
    final identity = jsonEncode([wallet.name, wallet.config.pubKey]);
    final id = _preparedDeletionIds[identity];
    // Once the engine has reported the deletion, cleanup owns the intent.
    if (id == null || (_deletedEntryIds[identity]?.contains(id) ?? false)) {
      return;
    }
    _preparedDeletionIds.remove(identity);
    _preparedDeletionScopes.remove(id);
    final users = await _sdk.auth.getUsers();
    // Only a wallet the engine still lists is proven undeleted. A retry may
    // also have prepared it again meanwhile; that intent is the retry's own.
    if (_preparedDeletionIds.containsKey(identity) ||
        !users.any((user) => WalletAccessService.entryId(user) == id)) {
      return;
    }
    await _cleanup.withdraw(id);
  }
}
