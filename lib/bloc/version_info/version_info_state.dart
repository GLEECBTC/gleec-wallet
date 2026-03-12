part of 'version_info_bloc.dart';

abstract class VersionInfoState extends Equatable {
  const VersionInfoState();
}

class VersionInfoInitial extends VersionInfoState {
  const VersionInfoInitial();

  @override
  List<Object?> get props => [];
}

class VersionInfoLoading extends VersionInfoState {
  const VersionInfoLoading();

  @override
  List<Object?> get props => [];
}

class VersionInfoLoaded extends VersionInfoState {
  const VersionInfoLoaded({
    required this.appVersion,
    required this.commitHash,
    this.buildDate,
    this.apiCommitHash,
    this.currentCoinsCommit,
    this.latestCoinsCommit,
  });

  final String? appVersion;
  final String? commitHash;
  final String? buildDate;
  final String? apiCommitHash;
  final String? currentCoinsCommit;
  final String? latestCoinsCommit;

  VersionInfoLoaded copyWith({
    ValueGetter<String?>? appVersion,
    ValueGetter<String?>? commitHash,
    ValueGetter<String?>? buildDate,
    ValueGetter<String?>? apiCommitHash,
    ValueGetter<String?>? currentCoinsCommit,
    ValueGetter<String?>? latestCoinsCommit,
  }) {
    return VersionInfoLoaded(
      appVersion: appVersion?.call() ?? this.appVersion,
      commitHash: commitHash?.call() ?? this.commitHash,
      buildDate: buildDate?.call() ?? this.buildDate,
      apiCommitHash: apiCommitHash?.call() ?? this.apiCommitHash,
      currentCoinsCommit: currentCoinsCommit?.call() ?? this.currentCoinsCommit,
      latestCoinsCommit: latestCoinsCommit?.call() ?? this.latestCoinsCommit,
    );
  }

  @override
  List<Object?> get props => [
    appVersion,
    commitHash,
    buildDate,
    apiCommitHash,
    currentCoinsCommit,
    latestCoinsCommit,
  ];
}

class VersionInfoError extends VersionInfoState {
  const VersionInfoError(this.message);

  final String message;

  @override
  List<Object?> get props => [message];
}
