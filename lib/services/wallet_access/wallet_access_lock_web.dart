import 'dart:js_interop';
import 'package:web/web.dart' as web;
import 'wallet_access_types.dart';

Future<T> withWalletAccessLock<T>(Future<T> Function() action) =>
    _withLock('gleec-wallet-access', action, ifAvailable: true);
Future<T> withWalletAccessRecordLock<T>(Future<T> Function() action) =>
    _withLock('gleec-wallet-access-records', action);
Future<T> _withLock<T>(
  String name,
  Future<T> Function() action, {
  bool ifAvailable = false,
}) async {
  late T value;
  Object? error;
  StackTrace? stack;
  var completed = false;
  await web.window.navigator.locks
      .request(
        name,
        web.LockOptions(ifAvailable: ifAvailable),
        ((web.Lock? lock) => Future<void>.sync(() async {
          if (lock == null) {
            error = const WalletAccessException(WalletAccessFailure.busy);
            return;
          }
          try {
            value = await action();
            completed = true;
          } catch (e, s) {
            error = e;
            stack = s;
          }
        }).toJS).toJS,
      )
      .toDart;
  if (error != null)
    Error.throwWithStackTrace(error!, stack ?? StackTrace.current);
  if (!completed) throw const WalletAccessException(WalletAccessFailure.busy);
  return value;
}
