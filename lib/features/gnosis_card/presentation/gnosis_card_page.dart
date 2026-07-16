import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';
import 'package:web_dex/features/gnosis_card/application/gnosis_card_bloc.dart';
import 'package:web_dex/features/gnosis_card/application/gnosis_card_coordinator.dart';
import 'package:web_dex/features/gnosis_card/domain/gnosis_card_models.dart';
import 'package:web_dex/features/gnosis_card/infrastructure/gnosis_card_dependencies.dart';
import 'package:web_dex/features/gnosis_card/presentation/gnosis_card_locale_keys.dart';
import 'package:web_dex/features/gnosis_card/presentation/gnosis_onboarding_view.dart';
import 'package:web_dex/features/gnosis_card/presentation/gnosis_onboarding_widgets.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/shared/screenshot/screenshot_sensitivity.dart';

part 'gnosis_card_page_activity.dart';
part 'gnosis_card_page_cards.dart';
part 'gnosis_card_page_dashboard.dart';
part 'gnosis_card_page_support.dart';

class GnosisCardPage extends StatefulWidget {
  const GnosisCardPage({this.manageLifecycle = true, super.key});

  /// Previews render static fixtures and must not invoke KDF or repositories.
  final bool manageLifecycle;

  @override
  State<GnosisCardPage> createState() => _GnosisCardPageState();
}

class _GnosisCardPageState extends State<GnosisCardPage>
    with WidgetsBindingObserver {
  GnosisCardBloc? _bloc;
  bool _entered = false;
  bool _isAppBackgrounded = false;
  bool _approvalSheetOpen = false;
  NavigatorState? _approvalNavigator;
  String? _lastPresentedNonce;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _bloc ??= context.read<GnosisCardBloc>();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final current = _bloc!.state;
      if (current.intervention == GnosisCardIntervention.walletApproval &&
          current.snapshot?.siweChallenge != null) {
        _presentWalletApproval(context, current);
      }
    });
    if (widget.manageLifecycle && !_entered) {
      _entered = true;
      _bloc!.add(const GnosisCardEntered());
    }
  }

  @override
  void dispose() {
    if (widget.manageLifecycle && _entered) {
      _bloc?.add(const GnosisCardExited());
    }
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!widget.manageLifecycle || !mounted) return;
    if (state == AppLifecycleState.resumed) {
      setState(() => _isAppBackgrounded = false);
      _bloc?.add(const GnosisCardResumed());
    } else {
      setState(() => _isAppBackgrounded = true);
      if (_approvalSheetOpen) _approvalNavigator?.maybePop(false);
      _bloc?.add(const GnosisCardExited());
    }
  }

  @override
  Widget build(BuildContext context) {
    final baseTheme = Theme.of(context);
    final dark = baseTheme.brightness == Brightness.dark;
    final foreground = dark ? const Color(0xFFF8F4FC) : const Color(0xFF28183D);
    final actionColor = dark
        ? const Color(0xFFEBDDFF)
        : const Color(0xFF4A176A);
    final errorColor = dark ? const Color(0xFFFFB4C8) : const Color(0xFFA00038);
    final errorBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: errorColor, width: 1.5),
    );
    final cardTheme = baseTheme.copyWith(
      colorScheme: baseTheme.colorScheme.copyWith(
        primary: actionColor,
        onPrimary: dark ? const Color(0xFF28183D) : Colors.white,
        onSurface: foreground,
        outline: actionColor,
        error: errorColor,
        onError: dark ? const Color(0xFF28183D) : Colors.white,
      ),
      textTheme: baseTheme.textTheme.apply(
        bodyColor: foreground,
        displayColor: foreground,
      ),
      inputDecorationTheme: baseTheme.inputDecorationTheme.copyWith(
        labelStyle: TextStyle(color: foreground),
        floatingLabelStyle: TextStyle(color: foreground),
        hintStyle: TextStyle(color: foreground.withValues(alpha: 0.78)),
        helperStyle: TextStyle(color: foreground),
        errorStyle: TextStyle(color: errorColor, fontWeight: FontWeight.w600),
        errorBorder: errorBorder,
        focusedErrorBorder: errorBorder,
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: actionColor,
          minimumSize: const Size(48, 48),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(minimumSize: const Size(48, 48)),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: actionColor,
          side: BorderSide(color: actionColor),
          minimumSize: const Size(48, 48),
        ),
      ),
    );
    return ScreenshotSensitive(
      child: Theme(
        data: cardTheme,
        child: MultiBlocListener(
          listeners: [
            BlocListener<GnosisCardBloc, GnosisCardState>(
              listenWhen: (previous, current) =>
                  previous.externalFlow?.id != current.externalFlow?.id &&
                  current.externalFlow != null,
              listener: _launchExternalFlow,
            ),
            BlocListener<GnosisCardBloc, GnosisCardState>(
              listenWhen: (previous, current) {
                final challenge = current.snapshot?.siweChallenge;
                return current.intervention ==
                        GnosisCardIntervention.walletApproval &&
                    challenge != null &&
                    challenge.nonce != previous.snapshot?.siweChallenge?.nonce;
              },
              listener: _presentWalletApproval,
            ),
            BlocListener<GnosisCardBloc, GnosisCardState>(
              listenWhen: (previous, current) =>
                  _approvalSheetOpen &&
                  (previous.activeWalletGeneration !=
                          current.activeWalletGeneration ||
                      current.intervention !=
                          GnosisCardIntervention.walletApproval ||
                      previous.snapshot?.siweChallenge?.approvalId !=
                          current.snapshot?.siweChallenge?.approvalId),
              listener: (_, _) => _approvalNavigator?.maybePop(false),
            ),
          ],
          child: BlocBuilder<GnosisCardBloc, GnosisCardState>(
            builder: (context, state) {
              if (widget.manageLifecycle && _isAppBackgrounded) {
                return const _PrivacyShield();
              }
              if (state.status == GnosisCardLoadStatus.disabled) {
                return _RecoveryState(
                  icon: Icons.credit_card_off_outlined,
                  title: LocaleKeys.gnosisCard_disabledTitle.tr(),
                  message: LocaleKeys.gnosisCard_disabledBody.tr(),
                );
              }
              if (state.status == GnosisCardLoadStatus.failure &&
                  state.snapshot == null) {
                return _RecoveryState(
                  icon: Icons.cloud_off_outlined,
                  title: LocaleKeys.gnosisCard_failureTitle.tr(),
                  message: state.failure == null
                      ? LocaleKeys.gnosisCard_recovery_unknown.tr()
                      : gnosisLocalizedFailureMessage(state.failure!),
                  actionLabel: LocaleKeys.gnosisCard_retrySafely.tr(),
                  onAction: () => context.read<GnosisCardBloc>().add(
                    const GnosisSignInRequested(),
                  ),
                );
              }
              final snapshot = state.snapshot;
              if (snapshot == null) {
                return GnosisProgressIndicator(
                  label: LocaleKeys.gnosisCard_loading.tr(),
                );
              }
              if (snapshot.progress.nextStage != GnosisOnboardingStage.ready ||
                  snapshot.dashboard == null) {
                return GnosisOnboardingView(state: state, snapshot: snapshot);
              }
              final migrationId = snapshot.safeMigration.migrationId;
              if (snapshot.safeMigration.hasAddressChanged &&
                  migrationId != null &&
                  state.checkedMigrationId != migrationId) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) {
                    _bloc?.add(
                      GnosisMigrationNoticeStatusRequested(migrationId),
                    );
                  }
                });
              }
              return _Dashboard(
                snapshot: snapshot,
                state: state,
                showMigrationNotice:
                    snapshot.safeMigration.hasAddressChanged &&
                    migrationId != null &&
                    state.checkedMigrationId == migrationId &&
                    migrationId != state.dismissedMigrationId,
                onDismissMigration: () => context.read<GnosisCardBloc>().add(
                  GnosisMigrationNoticeDismissed(migrationId!),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Future<void> _presentWalletApproval(
    BuildContext context,
    GnosisCardState state,
  ) async {
    final challenge = state.snapshot?.siweChallenge;
    if (challenge == null ||
        _approvalSheetOpen ||
        challenge.nonce == _lastPresentedNonce) {
      return;
    }
    _approvalSheetOpen = true;
    _lastPresentedNonce = challenge.nonce;
    final approved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) {
        _approvalNavigator = Navigator.of(sheetContext);
        return ScreenshotSensitive(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              24,
              24,
              24,
              24 + MediaQuery.viewInsetsOf(sheetContext).bottom,
            ),
            child: SingleChildScrollView(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 620),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Semantics(
                      header: true,
                      child: Text(
                        GnosisCardLocaleKeys.consentTitle.tr(),
                        style: Theme.of(sheetContext).textTheme.headlineSmall,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(GnosisCardLocaleKeys.consentBody.tr()),
                    const SizedBox(height: 24),
                    _InfoRow(
                      label: GnosisCardLocaleKeys.consentDomain.tr(),
                      value: challenge.domain,
                    ),
                    _InfoRow(
                      label: GnosisCardLocaleKeys.consentAccount.tr(),
                      value: _short(challenge.ownerAddress),
                    ),
                    ExpansionTile(
                      tilePadding: EdgeInsets.zero,
                      title: Text(GnosisCardLocaleKeys.consentDetails.tr()),
                      children: [
                        _InfoRow(
                          label: _cardText('discovery.consentAccount'),
                          value: challenge.ownerAddress,
                        ),
                        _InfoRow(
                          label: _cardText('discovery.consentUri'),
                          value: challenge.uri.toString(),
                        ),
                        _InfoRow(
                          label: _cardText('dashboard.network'),
                          value:
                              '${_cardText('dashboard.gnosisNetwork')} · '
                              '${challenge.chainId}',
                        ),
                        _InfoRow(
                          label: _cardText('discovery.consentVersion'),
                          value: '1',
                        ),
                        _InfoRow(
                          label: _cardText('discovery.consentNonce'),
                          value: challenge.nonce,
                        ),
                        _InfoRow(
                          label: _cardText('discovery.consentIssued'),
                          value: _formatDateTime(
                            sheetContext,
                            challenge.issuedAt,
                          ),
                        ),
                        _InfoRow(
                          label: _cardText('discovery.consentExpires'),
                          value: _formatDateTime(
                            sheetContext,
                            challenge.expiresAt,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _cardText('discovery.consentExactMessage'),
                          style: Theme.of(sheetContext).textTheme.labelLarge,
                        ),
                        const SizedBox(height: 6),
                        SelectableText(challenge.message),
                      ],
                    ),
                    const SizedBox(height: 20),
                    FilledButton(
                      onPressed: () => Navigator.of(sheetContext).pop(true),
                      child: Text(LocaleKeys.gnosisCard_discovery_signIn.tr()),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: () => Navigator.of(sheetContext).pop(false),
                      child: Text(GnosisCardLocaleKeys.notNow.tr()),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
    _approvalSheetOpen = false;
    _approvalNavigator = null;
    if (!mounted) return;
    _bloc?.add(
      approved == true
          ? GnosisSiweApprovalRequested(challenge.approvalId)
          : GnosisSiweApprovalDeclined(challenge.approvalId),
    );
    final current = _bloc?.state;
    final currentChallenge = current?.snapshot?.siweChallenge;
    if (current?.intervention == GnosisCardIntervention.walletApproval &&
        currentChallenge != null &&
        currentChallenge.approvalId != challenge.approvalId) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _presentWalletApproval(context, _bloc!.state);
      });
    }
  }

  Future<void> _launchExternalFlow(
    BuildContext context,
    GnosisCardState state,
  ) async {
    final flow = state.externalFlow;
    if (flow == null) return;
    try {
      await context.read<GnosisCardDependencies>().externalFlowLauncher.launch(
        flow,
      );
      if (context.mounted) {
        context.read<GnosisCardBloc>().add(GnosisExternalFlowHandled(flow.id));
      }
    } catch (_) {
      if (context.mounted) {
        context.read<GnosisCardBloc>().add(
          GnosisExternalFlowLaunchFailed(flow.id),
        );
      }
    }
  }
}
