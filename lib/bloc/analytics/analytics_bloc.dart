import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:web_dex/bloc/analytics/analytics_repo.dart';
import 'package:web_dex/bloc/settings/settings_repository.dart';
import 'package:web_dex/model/stored_settings.dart';

import 'analytics_event.dart';
import 'analytics_state.dart';

class AnalyticsBloc extends Bloc<AnalyticsEvent, AnalyticsState> {
  AnalyticsBloc({
    required AnalyticsRepo analytics,
    required StoredSettings storedData,
    required SettingsRepository repository,
  }) : _analytics = analytics,
       _settingsRepo = repository,
       super(AnalyticsState.fromSettings(storedData.analytics)) {
    on<AnalyticsActivateEvent>(_onActivate);
    on<AnalyticsDeactivateEvent>(_onDeactivate);
    on<AnalyticsSendDataEvent>(_onSendData);
  }

  final AnalyticsRepo _analytics;
  final SettingsRepository _settingsRepo;

  Future<void> _onActivate(
    AnalyticsActivateEvent event,
    Emitter<AnalyticsState> emit,
  ) async {
    await _analytics.activate();
    emit(state.copyWith(isSendDataAllowed: true));
    await _settingsRepo.updateSettingsWith(
      (current) => current.copyWith(
        analytics: current.analytics.copyWith(isSendAllowed: true),
      ),
    );
  }

  Future<void> _onDeactivate(
    AnalyticsDeactivateEvent event,
    Emitter<AnalyticsState> emit,
  ) async {
    await _analytics.deactivate();
    emit(state.copyWith(isSendDataAllowed: false));
    await _settingsRepo.updateSettingsWith(
      (current) => current.copyWith(
        analytics: current.analytics.copyWith(isSendAllowed: false),
      ),
    );
  }

  Future<void> _onSendData(
    AnalyticsSendDataEvent event,
    Emitter<AnalyticsState> emitter,
  ) async {
    // Use queueEvent instead of sendData for consistency
    // This will automatically handle the event based on analytics state
    await _analytics.queueEvent(event.data);
  }
}

// Extension to provide a helper method for logging analytics
extension AnalyticsBlocEventLogger on AnalyticsBloc {
  void logEvent(AnalyticsEventData event) {
    add(AnalyticsSendDataEvent(event));
  }
}
