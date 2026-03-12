import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart' show ValueGetter;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:logging/logging.dart';
import 'package:web_dex/app_config/package_information.dart';
import 'package:web_dex/mm2/mm2_api/mm2_api.dart';

part 'version_info_event.dart';
part 'version_info_state.dart';

class VersionInfoBloc extends Bloc<VersionInfoEvent, VersionInfoState> {
  VersionInfoBloc({
    required Mm2Api mm2Api,
    required KomodoDefiSdk komodoDefiSdk,
    Duration? pollInterval,
  }) : _mm2Api = mm2Api,
       _komodoDefiSdk = komodoDefiSdk,
       _pollInterval = pollInterval ?? const Duration(minutes: 5),
       super(const VersionInfoInitial()) {
    on<LoadVersionInfo>(_onLoadVersionInfo);
    on<StartPeriodicPolling>(_onStartPeriodicPolling);
    on<StopPeriodicPolling>(_onStopPeriodicPolling);
    on<PollVersionInfo>(_onPollVersionInfo);
  }

  final Mm2Api _mm2Api;
  final KomodoDefiSdk _komodoDefiSdk;
  final Duration _pollInterval;
  Timer? _pollTimer;
  static final Logger _logger = Logger('VersionInfoBloc');

  Future<void> _onLoadVersionInfo(
    LoadVersionInfo event,
    Emitter<VersionInfoState> emit,
  ) async {
    emit(const VersionInfoLoading());

    final appVersion = packageInformation.packageVersion;
    final commitHash = packageInformation.commitHash != null
        ? _tryParseCommitHash(packageInformation.commitHash!)
        : null;
    final buildDate = packageInformation.buildDate;

    _logger.info(
      'Basic app info retrieved - Version: $appVersion, '
      'Commit: $commitHash',
    );

    var currentInfo = VersionInfoLoaded(
      appVersion: appVersion,
      commitHash: commitHash,
      buildDate: buildDate,
    );
    emit(currentInfo);

    try {
      final apiVersion = await _mm2Api.version();
      if (apiVersion == null) {
        _logger.severe('Failed to load MM2 API version');
      }

      final apiCommitHash = apiVersion != null
          ? () => _tryParseCommitHash(apiVersion)
          : null;
      currentInfo = currentInfo.copyWith(apiCommitHash: apiCommitHash);
      emit(currentInfo);
      _logger.info(
        'MM2 API version loaded successfully - Version: $apiVersion, '
        'Commit: ${apiCommitHash?.call()}',
      );
    } catch (e, s) {
      _logger.severe('Failed to load MM2 API version', e, s);
      // Continue without API version if it fails
    }

    try {
      final currentCommit = await _komodoDefiSdk.assets.currentCoinsCommit;
      final latestCommit = await _komodoDefiSdk.assets.latestCoinsCommit;
      if (currentCommit == null || latestCommit == null) {
        _logger.severe(
          'Failed to load SDK coins commits. '
          'Current commit: $currentCommit, latest commit: $latestCommit',
        );
      }

      currentInfo = currentInfo.copyWith(
        currentCoinsCommit: () => _tryParseCommitHash(currentCommit ?? '-'),
        latestCoinsCommit: () => _tryParseCommitHash(latestCommit ?? '-'),
      );
      emit(currentInfo);
      _logger.info(
        'SDK coins commits loaded successfully - Current: $currentCommit, '
        'Latest: $latestCommit',
      );
    } catch (e, s) {
      _logger.severe('Failed to load SDK coins commits', e, s);
      // Continue without SDK commits if it fails
    }
  }

  Future<void> _onStartPeriodicPolling(
    StartPeriodicPolling event,
    Emitter<VersionInfoState> emit,
  ) async {
    _logger.info('Starting periodic polling for version updates');

    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(_pollInterval, (_) {
      add(const PollVersionInfo());
    });
  }

  Future<void> _onStopPeriodicPolling(
    StopPeriodicPolling event,
    Emitter<VersionInfoState> emit,
  ) async {
    _logger.info('Stopping periodic polling for version updates');
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  @override
  Future<void> close() async {
    _pollTimer?.cancel();
    return super.close();
  }

  Future<void> _onPollVersionInfo(
    PollVersionInfo event,
    Emitter<VersionInfoState> emit,
  ) async {
    try {
      _logger.fine('Polling for latest commit hash update');
      final latestCommit = await _komodoDefiSdk.assets.latestCoinsCommit;
      final currentCommit = await _komodoDefiSdk.assets.currentCoinsCommit;
      if (latestCommit == null || currentCommit == null) {
        _logger.severe(
          'Failed to poll commit hash updates. '
          'Latest commit: $latestCommit, current commit: $currentCommit',
        );
        return;
      }

      final parsedLatest = _tryParseCommitHash(latestCommit);
      final parsedCurrent = _tryParseCommitHash(currentCommit);

      if (state is VersionInfoLoaded) {
        final currentState = state as VersionInfoLoaded;
        if (currentState.latestCoinsCommit != parsedLatest ||
            currentState.currentCoinsCommit != parsedCurrent) {
          _logger.info(
            'Commit hash update detected - Current: $parsedCurrent, Latest: $parsedLatest',
          );
          emit(
            currentState.copyWith(
              currentCoinsCommit: () => parsedCurrent,
              latestCoinsCommit: () => parsedLatest,
            ),
          );
        }
      }
    } catch (e, s) {
      _logger.severe('Failed to poll commit hash updates', e, s);
    }
  }

  /// Returns the first 7 characters of the commit hash,
  /// or the unmodified [commitHash] if it is not valid.
  String _tryParseCommitHash(String commitHash) {
    final RegExp regExp = RegExp(r'[0-9a-fA-F]{7,40}');
    final Match? match = regExp.firstMatch(commitHash);

    if (match == null || match.group(0) == null) {
      _logger.fine('No valid commit hash pattern found in: $commitHash');
      return commitHash;
    }

    // '!' is safe because we know that match.group(0) is not null
    return match.group(0)!.substring(0, 7);
  }
}
