import 'dart:ffi';
import 'dart:io' show Platform;

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart' as win32;

/// Returns null when the runner cannot read the setting directly.
bool? readDesktopReducedMotion() {
  try {
    if (Platform.isMacOS) return _readMacOS();
    if (Platform.isWindows) return _readWindows();
  } on ArgumentError {
    // The engine may be running in a test host without these native symbols.
    return null;
  }
  return null;
}

bool? _readWindows() => using((arena) {
  final animations = arena<Int32>();
  final success = win32.SystemParametersInfo(
    win32.SPI_GETCLIENTAREAANIMATION,
    0,
    animations,
    0,
  );
  return success == 0 ? null : animations.value == 0;
});

bool? _readMacOS() {
  // AppKit is main-thread bound. Flutter normally runs its root isolate there
  // on macOS, but embedders and test hosts can use a separate UI thread.
  if (_isMainThread() == 0 || _workspaceClass == nullptr) return null;

  final workspace = _sharedWorkspace(_workspaceClass, _sharedWorkspaceSelector);
  if (workspace == nullptr) return null;

  // Objective-C BOOL is a signed char on Intel macOS and bool on Apple silicon.
  return Abi.current() == Abi.macosX64
      ? _reduceMotionIntel(workspace, _reduceMotionSelector) != 0
      : _reduceMotionArm(workspace, _reduceMotionSelector);
}

typedef _ObjCPointer = Pointer<Void>;

final _process = DynamicLibrary.process();
final _isMainThread = _process.lookupFunction<Int Function(), int Function()>(
  'pthread_main_np',
);
final _getClass = _process
    .lookupFunction<
      _ObjCPointer Function(Pointer<Utf8>),
      _ObjCPointer Function(Pointer<Utf8>)
    >('objc_getClass');
final _registerSelector = _process
    .lookupFunction<
      _ObjCPointer Function(Pointer<Utf8>),
      _ObjCPointer Function(Pointer<Utf8>)
    >('sel_registerName');
final _workspaceClass = using(
  (arena) => _getClass('NSWorkspace'.toNativeUtf8(allocator: arena)),
);
final _sharedWorkspaceSelector = using(
  (arena) =>
      _registerSelector('sharedWorkspace'.toNativeUtf8(allocator: arena)),
);
final _reduceMotionSelector = using(
  (arena) => _registerSelector(
    'accessibilityDisplayShouldReduceMotion'.toNativeUtf8(allocator: arena),
  ),
);

// objc_msgSend must use the signature of the Objective-C method being called.
final _sendMessage = _process.lookup<NativeFunction<Void Function()>>(
  'objc_msgSend',
);
final _sharedWorkspace = _sendMessage
    .cast<NativeFunction<_ObjCPointer Function(_ObjCPointer, _ObjCPointer)>>()
    .asFunction<_ObjCPointer Function(_ObjCPointer, _ObjCPointer)>();
final _reduceMotionIntel = _sendMessage
    .cast<NativeFunction<Int8 Function(_ObjCPointer, _ObjCPointer)>>()
    .asFunction<int Function(_ObjCPointer, _ObjCPointer)>();
final _reduceMotionArm = _sendMessage
    .cast<NativeFunction<Bool Function(_ObjCPointer, _ObjCPointer)>>()
    .asFunction<bool Function(_ObjCPointer, _ObjCPointer)>();
