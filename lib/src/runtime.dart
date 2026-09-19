import 'runtime_stub.dart' if (dart.library.io) 'runtime_io.dart' as impl;

/// Whether this isolate is running in a browser.
bool get isBrowser => impl.isBrowser;

/// Short runtime tag for `X-TypeSafe-Runtime`.
String describeRuntime() => impl.describeRuntime();
