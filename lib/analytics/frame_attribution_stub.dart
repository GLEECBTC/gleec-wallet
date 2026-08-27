/// Non-web stub for the frame-attribution probe.
///
/// Attribution answers "which script blocked the main thread", which is only a
/// meaningful question where Flutter, our Dart and KDF's wasm all share one
/// thread - i.e. on web. On native the UI and raster threads are separate and
/// KDF is a different process or an FFI call, so there is nothing here to
/// attribute and the real implementation is never compiled in.
///
/// See `frame_attribution_web.dart` for the contract these must both satisfy.
library;

/// Reserved snapshot keys. Declared here as well as in the web implementation
/// because a conditional import must present the same API on both sides - the
/// analyzer resolves this file, so a constant missing here fails the build for
/// every platform.
const String blockingKey = '~blocking';
const String countKey = '~count';
const String totalKey = '~total';

/// Always false off web: there is no `PerformanceObserver` to install.
bool installFrameAttribution() => false;

/// Always null off web, which the recorder reports as "no attribution" rather
/// than as a zeroed breakdown.
Map<String, double>? captureFrameAttribution() => null;
