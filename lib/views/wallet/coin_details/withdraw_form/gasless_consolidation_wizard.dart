import 'package:decimal/decimal.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/bloc/auth_bloc/auth_bloc.dart';
import 'package:web_dex/bloc/coin_addresses/bloc/coin_addresses_bloc.dart';
import 'package:web_dex/bloc/coin_addresses/bloc/coin_addresses_event.dart';
import 'package:web_dex/bloc/coin_addresses/bloc/coin_addresses_state.dart';
import 'package:web_dex/bloc/withdraw_form/withdraw_form_state.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/model/wallet.dart';
import 'package:web_dex/shared/gasless/tron_gasless_consolidation_gate.dart';
import 'package:web_dex/views/wallet/coin_details/withdraw_form/withdraw_form.dart';

enum _ConsolidationSourceAvailability {
  movable,
  tokenFrozen,
  needsTrx,
  preflightUnavailable,
}

typedef GaslessConsolidationAddressVerifier =
    String? Function(
      KomodoDefiSdk sdk,
      Asset asset,
      CoinAddressesState state, {
      required WalletType? walletType,
      required WalletId? currentWalletId,
    });

class _ConsolidationSource {
  const _ConsolidationSource({
    required this.pubkey,
    required this.trxSpendable,
    required this.availability,
    this.estimatedTrxFee,
    this.trxShortfall,
  });

  final PubkeyInfo pubkey;
  final Decimal trxSpendable;
  final _ConsolidationSourceAvailability availability;
  final Decimal? estimatedTrxFee;
  final Decimal? trxShortfall;
}

/// Moves each funded Standard TRC-20 address into the canonical GasFree
/// custody account as a separately reviewed native transaction.
///
/// TRX is checked on the exact derivation that owns the token. Sources are
/// never combined into one authorization, so every network fee and result is
/// visible independently.
class GaslessConsolidationWizard extends StatefulWidget {
  const GaslessConsolidationWizard({
    required this.asset,
    required this.custodyAddress,
    required this.expectedWalletId,
    required this.onDone,
    this.addressVerifier = verifiedTronGaslessConsolidationAddress,
    super.key,
  });

  final Asset asset;
  final String custodyAddress;
  final WalletId? expectedWalletId;
  final VoidCallback onDone;

  /// Authorization boundary used before every load, preview, and source form.
  ///
  /// Production uses the pinned provider and typed KDF status verifier. The
  /// injectable boundary keeps lifecycle behavior independently testable even
  /// in fail-closed builds where the production provider pin is absent.
  @visibleForTesting
  final GaslessConsolidationAddressVerifier addressVerifier;

  @override
  State<GaslessConsolidationWizard> createState() =>
      _GaslessConsolidationWizardState();
}

class _GaslessConsolidationWizardState extends State<GaslessConsolidationWizard>
    with WidgetsBindingObserver {
  Future<List<_ConsolidationSource>>? _loadFuture;
  List<_ConsolidationSource> _sources = const [];
  final Set<String> _completed = <String>{};
  _ConsolidationSource? _active;
  int _loadGeneration = 0;
  bool _gateResetScheduled = false;
  bool _isAppForeground = true;
  DateTime? _resumeRefreshRequestedAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final lifecycleState = WidgetsBinding.instance.lifecycleState;
    _isAppForeground =
        lifecycleState == null || lifecycleState == AppLifecycleState.resumed;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (!mounted) return;

    final resumed = state == AppLifecycleState.resumed;
    setState(() {
      _isAppForeground = resumed;
      _resumeRefreshRequestedAt = resumed ? DateTime.now().toUtc() : null;
      _loadGeneration += 1;
      _active = null;
      _sources = const [];
      _loadFuture = null;
    });
    context.read<CoinAddressesBloc>().add(
      CoinAddressesGaslessReceiveVisibilityChanged(resumed),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  bool _hasFreshForegroundStatus(CoinAddressesState state) {
    if (!_isAppForeground) return false;
    final refreshRequestedAt = _resumeRefreshRequestedAt;
    if (refreshRequestedAt == null) return true;
    final observedAt = state.gaslessAccountStatusObservedAt?.toUtc();
    return observedAt != null && !observedAt.isBefore(refreshRequestedAt);
  }

  String? _verifiedCustodyAddress({
    CoinAddressesState? addressesState,
    WalletType? walletType,
    WalletId? walletId,
  }) {
    final sdk = context.read<KomodoDefiSdk>();
    return widget.addressVerifier(
      sdk,
      widget.asset,
      addressesState ?? context.read<CoinAddressesBloc>().state,
      walletType:
          walletType ??
          context.read<AuthBloc>().state.currentUser?.wallet.config.type,
      currentWalletId:
          walletId ?? context.read<AuthBloc>().state.currentUser?.walletId,
    );
  }

  bool _isConsolidationReady() {
    final state = context.read<CoinAddressesBloc>().state;
    final currentWalletId = context
        .read<AuthBloc>()
        .state
        .currentUser
        ?.walletId;
    if (widget.expectedWalletId == null ||
        currentWalletId != widget.expectedWalletId) {
      return false;
    }
    return _hasFreshForegroundStatus(state) &&
        _verifiedCustodyAddress(
              addressesState: state,
              walletId: widget.expectedWalletId,
            ) ==
            widget.custodyAddress;
  }

  Future<bool> _isExpectedWalletCurrent() async {
    if (!_isConsolidationReady()) return false;
    final currentUser = await context.read<KomodoDefiSdk>().auth.currentUser;
    return mounted &&
        currentUser?.walletId == widget.expectedWalletId &&
        _isConsolidationReady();
  }

  Future<void> _requireExpectedWalletCurrent() async {
    if (await _isExpectedWalletCurrent()) return;
    throw const WalletChangedDisconnectException(
      'Wallet changed during GasFree consolidation',
    );
  }

  Future<List<_ConsolidationSource>> _beginLoad() {
    final generation = ++_loadGeneration;
    return _loadSources(generation);
  }

  Future<List<_ConsolidationSource>> _loadSources(int generation) async {
    await _requireExpectedWalletCurrent();
    final sdk = context.read<KomodoDefiSdk>();
    final parentId = widget.asset.id.parentId;
    if (parentId == null) {
      throw StateError('A TRC-20 parent asset is required for consolidation');
    }
    final parent = sdk.assets.fromId(parentId);
    if (parent == null) {
      throw StateError('The TRON fee asset is unavailable');
    }

    final walletId = widget.expectedWalletId!;
    final tokenPubkeys =
        sdk.pubkeys.lastKnownForWallet(widget.asset.id, walletId) ??
        await sdk.pubkeys.getPubkeys(widget.asset);
    await _requireExpectedWalletCurrent();
    final trxPubkeys =
        sdk.pubkeys.lastKnownForWallet(parentId, walletId) ??
        await sdk.pubkeys.getPubkeys(parent);
    await _requireExpectedWalletCurrent();

    final fundedTokenKeys = tokenPubkeys.keys
        .where((key) => key.balance.total > Decimal.zero)
        .toList();
    final sources = <_ConsolidationSource>[];
    for (final tokenKey in fundedTokenKeys) {
      PubkeyInfo? trxKey;
      for (final candidate in trxPubkeys.keys) {
        final path = tokenKey.derivationPath;
        final pathMatches =
            path != null && path.isNotEmpty && candidate.derivationPath == path;
        if (pathMatches || candidate.address == tokenKey.address) {
          trxKey = candidate;
          break;
        }
      }
      final trxSpendable = trxKey?.balance.spendable ?? Decimal.zero;
      if (tokenKey.balance.spendable <= Decimal.zero) {
        sources.add(
          _ConsolidationSource(
            pubkey: tokenKey,
            trxSpendable: trxSpendable,
            availability: _ConsolidationSourceAvailability.tokenFrozen,
          ),
        );
        continue;
      }

      try {
        // The remote receive authorization and SDK relay binding can expire
        // while sources are being enumerated. Revalidate immediately before
        // every preview; an old successful preview never authorizes a deposit.
        await _requireExpectedWalletCurrent();
        final derivationPath = tokenKey.derivationPath?.trim();
        if (fundedTokenKeys.length > 1 &&
            (derivationPath == null || derivationPath.isEmpty)) {
          throw StateError('The Standard source derivation is unavailable');
        }
        final preview = await sdk.withdrawals.previewWithdrawal(
          WithdrawParameters(
            asset: widget.asset.id.id,
            toAddress: widget.custodyAddress,
            amount: null,
            from: derivationPath == null || derivationPath.isEmpty
                ? null
                : WithdrawalSource.hdDerivationPath(derivationPath),
            expirationSeconds: WithdrawFormState.tronPreviewExpirationSeconds,
            isMax: true,
          ),
        );
        await _requireExpectedWalletCurrent();
        if (preview.fee case final FeeInfoTron fee) {
          final estimatedFee = fee.totalFee;
          final shortfall = estimatedFee > trxSpendable
              ? estimatedFee - trxSpendable
              : Decimal.zero;
          sources.add(
            _ConsolidationSource(
              pubkey: tokenKey,
              trxSpendable: trxSpendable,
              availability: shortfall > Decimal.zero
                  ? _ConsolidationSourceAvailability.needsTrx
                  : _ConsolidationSourceAvailability.movable,
              estimatedTrxFee: estimatedFee,
              trxShortfall: shortfall,
            ),
          );
        } else {
          throw StateError('The consolidation preview was not a TRON fee');
        }
      } on WalletChangedDisconnectException {
        rethrow;
      } catch (_) {
        // A source is movable only after the standard withdrawal preview
        // proves its exact derivation can fund the TRON network fee. Do not
        // infer safety from a merely non-zero TRX balance.
        sources.add(
          _ConsolidationSource(
            pubkey: tokenKey,
            trxSpendable: trxSpendable,
            availability: _ConsolidationSourceAvailability.preflightUnavailable,
          ),
        );
      }
    }
    if (!mounted ||
        generation != _loadGeneration ||
        !await _isExpectedWalletCurrent()) {
      throw StateError('GasFree consolidation is paused');
    }
    _sources = sources;
    return sources;
  }

  void _retryLoad() {
    if (!_isConsolidationReady()) return;
    setState(() {
      _sources = const [];
      _loadFuture = _beginLoad();
    });
  }

  void _start(_ConsolidationSource source) {
    if (source.availability != _ConsolidationSourceAvailability.movable ||
        _completed.contains(source.pubkey.address) ||
        !_isConsolidationReady()) {
      return;
    }
    setState(() => _active = source);
  }

  void _completeActive(_ConsolidationSource completedSource) {
    final active = _active;
    if (active == null ||
        active.pubkey.address != completedSource.pubkey.address ||
        !_isConsolidationReady()) {
      setState(() => _active = null);
      return;
    }
    _completed.add(active.pubkey.address);
    _ConsolidationSource? next;
    for (final source in _sources) {
      if (source.availability == _ConsolidationSourceAvailability.movable &&
          !_completed.contains(source.pubkey.address)) {
        next = source;
        break;
      }
    }
    setState(() => _active = next);
  }

  void _scheduleGateReset() {
    if (_gateResetScheduled) return;
    _gateResetScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        _gateResetScheduled = false;
        _loadGeneration += 1;
        _active = null;
        _sources = const [];
        _loadFuture = null;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final addressesState = context.watch<CoinAddressesBloc>().state;
    final currentUser = context.watch<AuthBloc>().state.currentUser;
    final walletType = currentUser?.wallet.config.type;
    final verifiedAddress = _verifiedCustodyAddress(
      addressesState: addressesState,
      walletType: walletType,
      walletId: currentUser?.walletId,
    );
    final gateReady =
        currentUser?.walletId == widget.expectedWalletId &&
        _hasFreshForegroundStatus(addressesState) &&
        verifiedAddress != null &&
        verifiedAddress == widget.custodyAddress;
    final hasOpenSession =
        _active != null || _sources.isNotEmpty || _loadFuture != null;
    if (!gateReady || _gateResetScheduled) {
      // If authorization is lost while a source form is open, dispose that
      // form and its preview. A later recovery starts from fresh previews.
      if (!gateReady && hasOpenSession) _scheduleGateReset();
      return _ConsolidationGateStatus(
        checking:
            _gateResetScheduled ||
            addressesState.gaslessReceiveStatus ==
                GaslessReceiveStatus.initial ||
            addressesState.gaslessReceiveStatus ==
                GaslessReceiveStatus.checking,
        onDone: widget.onDone,
      );
    }

    final loadFuture = _loadFuture ??= _beginLoad();
    final active = _active;
    if (active != null) {
      return WithdrawForm(
        key: ValueKey('gasless-consolidation-${active.pubkey.address}'),
        asset: widget.asset,
        initialRecipient: widget.custodyAddress,
        initialSourceAddress: active.pubkey,
        initialGaslessEnabled: false,
        initialIsMax: true,
        lockSourceSelection: true,
        authorizationGuard: _isExpectedWalletCurrent,
        authorizationFailureMessage: LocaleKeys.receiveGaslessPausedNotice.tr(),
        onBackButtonPressed: () => setState(() => _active = null),
        onSuccess: () => _completeActive(active),
      );
    }

    return FutureBuilder<List<_ConsolidationSource>>(
      future: loadFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(LocaleKeys.gaslessConsolidationLoadError.tr()),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _retryLoad,
                  icon: const Icon(Icons.refresh_rounded),
                  label: Text(LocaleKeys.retryButtonText.tr()),
                ),
              ],
            ),
          );
        }

        return _ConsolidationSourceList(
          asset: widget.asset,
          custodyAddress: widget.custodyAddress,
          sources: snapshot.data ?? const <_ConsolidationSource>[],
          completed: _completed,
          onStart: _start,
          onDone: widget.onDone,
        );
      },
    );
  }
}

class _ConsolidationGateStatus extends StatelessWidget {
  const _ConsolidationGateStatus({
    required this.checking,
    required this.onDone,
  });

  final bool checking;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      key: const Key('gasless-consolidation-gate'),
      padding: const EdgeInsets.all(16),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  IconButton(
                    onPressed: onDone,
                    tooltip: LocaleKeys.back.tr(),
                    constraints: const BoxConstraints(
                      minWidth: 48,
                      minHeight: 48,
                    ),
                    icon: const Icon(Icons.arrow_back_rounded),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Semantics(
                      header: true,
                      child: Text(
                        LocaleKeys.gaslessConsolidationTitle.tr(),
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              if (checking)
                const Center(child: CircularProgressIndicator())
              else
                Semantics(
                  liveRegion: true,
                  child: Card(
                    color: theme.colorScheme.secondaryContainer,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        LocaleKeys.receiveGaslessPausedNotice.tr(),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSecondaryContainer,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ConsolidationSourceList extends StatelessWidget {
  const _ConsolidationSourceList({
    required this.asset,
    required this.custodyAddress,
    required this.sources,
    required this.completed,
    required this.onStart,
    required this.onDone,
  });

  final Asset asset;
  final String custodyAddress;
  final List<_ConsolidationSource> sources;
  final Set<String> completed;
  final ValueChanged<_ConsolidationSource> onStart;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final symbol = asset.id.symbol.configSymbol;
    final hasRemaining = sources.any(
      (source) =>
          source.availability == _ConsolidationSourceAvailability.movable &&
          !completed.contains(source.pubkey.address),
    );
    final allMovableComplete = !hasRemaining && completed.isNotEmpty;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  IconButton(
                    onPressed: onDone,
                    tooltip: LocaleKeys.back.tr(),
                    constraints: const BoxConstraints(
                      minWidth: 48,
                      minHeight: 48,
                    ),
                    icon: const Icon(Icons.arrow_back_rounded),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Semantics(
                      header: true,
                      child: Text(
                        LocaleKeys.gaslessConsolidationTitle.tr(),
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                LocaleKeys.gaslessConsolidationBody.tr(args: [symbol]),
                style: theme.textTheme.bodyLarge,
              ),
              const SizedBox(height: 12),
              Card(
                color: theme.colorScheme.secondaryContainer,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    LocaleKeys.gaslessConsolidationFeeNotice.tr(),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSecondaryContainer,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              if (allMovableComplete) ...[
                const SizedBox(height: 12),
                Semantics(
                  liveRegion: true,
                  child: Card(
                    color: theme.colorScheme.primaryContainer,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        LocaleKeys.gaslessConsolidationComplete.tr(),
                        style: TextStyle(
                          color: theme.colorScheme.onPrimaryContainer,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              if (sources.isEmpty)
                Text(LocaleKeys.gaslessConsolidationEmpty.tr())
              else
                for (final source in sources) ...[
                  _ConsolidationSourceCard(
                    source: source,
                    symbol: symbol,
                    isComplete: completed.contains(source.pubkey.address),
                    onStart: () => onStart(source),
                  ),
                  const SizedBox(height: 12),
                ],
              const SizedBox(height: 4),
              SelectableText(
                LocaleKeys.gaslessConsolidationDestination.tr(
                  args: [custodyAddress],
                ),
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ConsolidationSourceCard extends StatelessWidget {
  const _ConsolidationSourceCard({
    required this.source,
    required this.symbol,
    required this.isComplete,
    required this.onStart,
  });

  final _ConsolidationSource source;
  final String symbol;
  final bool isComplete;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final reason = switch (source.availability) {
      _ConsolidationSourceAvailability.movable => null,
      _ConsolidationSourceAvailability.tokenFrozen =>
        LocaleKeys.gaslessConsolidationTokenFrozen.tr(),
      _ConsolidationSourceAvailability.needsTrx =>
        LocaleKeys.gaslessConsolidationNeedsTrx.tr(),
      _ConsolidationSourceAvailability.preflightUnavailable =>
        LocaleKeys.gaslessConsolidationPreflightUnavailable.tr(),
    };

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SelectableText(
              source.pubkey.address,
              maxLines: 2,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontFamily: 'monospace',
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 16,
              runSpacing: 8,
              children: [
                Text(
                  LocaleKeys.gaslessConsolidationTokenBalance.tr(
                    args: [source.pubkey.balance.total.toString(), symbol],
                  ),
                ),
                Text(
                  LocaleKeys.gaslessConsolidationTrxBalance.tr(
                    args: [source.trxSpendable.toString()],
                  ),
                ),
                if (source.estimatedTrxFee != null)
                  Text(
                    LocaleKeys.gaslessConsolidationFeeEstimate.tr(
                      args: [source.estimatedTrxFee.toString()],
                    ),
                  ),
              ],
            ),
            if ((source.trxShortfall ?? Decimal.zero) > Decimal.zero) ...[
              const SizedBox(height: 10),
              Text(
                LocaleKeys.gaslessConsolidationFeeShortfall.tr(
                  args: [source.trxShortfall.toString()],
                ),
                style: TextStyle(
                  color: theme.colorScheme.error,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
            if (reason != null) ...[
              const SizedBox(height: 10),
              Text(
                reason,
                style: TextStyle(
                  color: theme.colorScheme.error,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            const SizedBox(height: 12),
            if (isComplete)
              Row(
                children: [
                  Icon(
                    Icons.check_circle_rounded,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      LocaleKeys.gaslessConsolidationSourceComplete.tr(),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              )
            else
              FilledButton(
                key: Key('gasless-consolidation-move-${source.pubkey.address}'),
                onPressed:
                    source.availability ==
                        _ConsolidationSourceAvailability.movable
                    ? onStart
                    : null,
                child: Text(LocaleKeys.gaslessConsolidationMoveSource.tr()),
              ),
          ],
        ),
      ),
    );
  }
}
