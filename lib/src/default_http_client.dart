import 'package:http/http.dart' as http;

import 'default_http_client_stub.dart'
    if (dart.library.io) 'default_http_client_io.dart' as impl;

/// Uses `package:http` so request cancellation is supported on each platform.
http.Client createDefaultHttpClient() => impl.createDefaultHttpClient();
