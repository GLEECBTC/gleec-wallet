part of 'auth_bloc.dart';

class AuthBlocState extends Equatable {
  const AuthBlocState({
    required this.mode,
    this.currentUser,
    this.authenticationState,
    this.authError,
  });

  factory AuthBlocState.initial() =>
      const AuthBlocState(mode: AuthorizeMode.noLogin);
  factory AuthBlocState.loading() => const AuthBlocState(
    mode: AuthorizeMode.noLogin,
    authenticationState: AuthenticationState(
      status: AuthenticationStatus.initializing,
    ),
  );
  factory AuthBlocState.error(AuthException authError) => AuthBlocState(
    mode: AuthorizeMode.noLogin,
    authenticationState: AuthenticationState.error(authError.toString()),
    authError: authError,
  );
  factory AuthBlocState.loggedIn(KdfUser user, {String? message}) =>
      AuthBlocState(
        mode: AuthorizeMode.logIn,
        authenticationState: AuthenticationState(
          status: AuthenticationStatus.completed,
          user: user,
          message: message,
        ),
        currentUser: user,
      );
  factory AuthBlocState.trezorInitializing({String? message, int? taskId}) =>
      AuthBlocState(
        mode: AuthorizeMode.noLogin,
        authenticationState: AuthenticationState(
          status: AuthenticationStatus.initializing,
          taskId: taskId,
          message: message,
        ),
      );
  factory AuthBlocState.trezorAwaitingConfirmation({
    String? message,
    int? taskId,
  }) => AuthBlocState(
    mode: AuthorizeMode.noLogin,
    authenticationState: AuthenticationState(
      status: AuthenticationStatus.waitingForDeviceConfirmation,
      taskId: taskId,
      message: message,
    ),
  );
  factory AuthBlocState.trezorPinRequired({
    String? message,
    required int taskId,
  }) => AuthBlocState(
    mode: AuthorizeMode.noLogin,
    authenticationState: AuthenticationState(
      status: AuthenticationStatus.pinRequired,
      taskId: taskId,
      message: message,
    ),
  );
  factory AuthBlocState.trezorPassphraseRequired({
    String? message,
    required int taskId,
  }) => AuthBlocState(
    mode: AuthorizeMode.noLogin,
    authenticationState: AuthenticationState(
      status: AuthenticationStatus.passphraseRequired,
      taskId: taskId,
      message: message,
    ),
  );
  factory AuthBlocState.trezorReady() => const AuthBlocState(
    mode: AuthorizeMode.noLogin,
    authenticationState: AuthenticationState(
      status: AuthenticationStatus.cancelled,
    ),
  );

  final KdfUser? currentUser;
  final AuthorizeMode mode;
  final AuthenticationState? authenticationState;
  final AuthException? authError;

  AuthenticationStatus? get status => authenticationState?.status;

  bool get isSignedIn => currentUser != null;
  bool get isLoading =>
      status == AuthenticationStatus.authenticating ||
      status == AuthenticationStatus.initializing;
  bool get isError => status == AuthenticationStatus.error;

  @override
  List<Object?> get props => [
    mode,
    currentUser,
    status,
    authError,
    authenticationState,
  ];
}
