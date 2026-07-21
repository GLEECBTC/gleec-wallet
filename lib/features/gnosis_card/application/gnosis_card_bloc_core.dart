part of 'gnosis_card_bloc.dart';

class GnosisCardBloc extends Bloc<GnosisCardEvent, GnosisCardState> {
  GnosisCardBloc({
    required this.config,
    required this.coordinator,
    this.identitySource,
    this.migrationNoticeStore,
    GnosisCardState initialState = const GnosisCardState.initial(),
  }) : super(initialState) {
    on<GnosisCardLifecycleEvent>(_onLifecycle, transformer: restartable());
    on<GnosisWalletIdentityChanged>(_onWalletIdentityChanged);
    on<GnosisSiweApprovalDeclined>(_onSiweApprovalDeclined);
    on<GnosisCardSubmissionEvent>(_onSubmission, transformer: droppable());
    on<GnosisTermOpenRequested>(_onTermOpenRequested);
    on<GnosisKycRefreshRequested>(
      _onKycRefreshRequested,
      transformer: restartable(),
    );
    on<GnosisSafeTransitionEvent>(_onSafeTransition, transformer: sequential());
    on<GnosisPhysicalTransitionEvent>(
      _onPhysicalTransition,
      transformer: sequential(),
    );
    on<GnosisExternalFlowHandled>(_onExternalFlowHandled);
    on<GnosisExternalFlowLaunchFailed>(_onExternalFlowLaunchFailed);
    on<GnosisCardFreezeChanged>(_onCardFreezeChanged, transformer: droppable());
    on<GnosisCardStatusChanged>(_onCardStatusChanged, transformer: droppable());
    on<GnosisCardControlsChanged>(
      _onCardControlsChanged,
      transformer: droppable(),
    );
    on<GnosisWithdrawalReviewRequested>(
      _onWithdrawalReviewRequested,
      transformer: droppable(),
    );
    on<GnosisDailyLimitReviewRequested>(
      _onDailyLimitReviewRequested,
      transformer: droppable(),
    );
    on<GnosisPreparedIntentConfirmed>(
      _onPreparedIntentConfirmed,
      transformer: droppable(),
    );
    on<GnosisPreparedIntentCancelled>(_onPreparedIntentCancelled);
    on<GnosisDelayedOperationsRefreshRequested>(
      _onDelayedOperationsRefreshRequested,
      transformer: restartable(),
    );
    on<GnosisMigrationNoticeStatusRequested>(
      _onMigrationNoticeStatusRequested,
      transformer: droppable(),
    );
    on<GnosisMigrationNoticeDismissed>(_onMigrationNoticeDismissed);
    _identitySubscription = identitySource?.watchWalletId().listen(
      (walletId) => add(GnosisWalletIdentityChanged(walletId)),
    );
  }

  final GnosisCardConfig config;
  final GnosisCardCoordinator? coordinator;
  final GnosisWalletIdentitySource? identitySource;
  final GnosisMigrationNoticeStore? migrationNoticeStore;

  var _externalFlowSequence = 0;
  var _walletGeneration = 0;
  String? _walletId;
  bool _approvalDeclined = false;
  StreamSubscription<String?>? _identitySubscription;
  Timer? _kycRefreshTimer;
  Timer? _dashboardReconnectTimer;
  Future<GnosisCardSnapshot> Function()? _pendingReauthenticationRetry;
  GnosisCardAction? _pendingReauthenticationAction;

  GnosisCardCoordinator get _coordinator {
    final value = coordinator;
    if (value == null) {
      throw const GnosisCardUnavailable(
        'Gnosis card dependencies are unavailable.',
      );
    }
    return value;
  }

  @override
  Future<void> close() async {
    _kycRefreshTimer?.cancel();
    _dashboardReconnectTimer?.cancel();
    await _identitySubscription?.cancel();
    return super.close();
  }
}
