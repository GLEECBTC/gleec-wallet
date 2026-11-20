import 'package:mutex/mutex.dart';

final _walletAccessLock = Mutex();
final _walletAccessRecordLock = Mutex();
Future<T> withWalletAccessLock<T>(Future<T> Function() action) =>
    _walletAccessLock.protect(action);
Future<T> withWalletAccessRecordLock<T>(Future<T> Function() action) =>
    _walletAccessRecordLock.protect(action);
