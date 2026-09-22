import 'package:http/http.dart' as http;

import 'default_http_client_stub.dart'
    if (dart.library.io) 'default_http_client_io.dart' as impl;

/// VM: pooled HTTP/2 client. Web: `http.Client`.
http.Client createDefaultHttpClient() => impl.createDefaultHttpClient();
