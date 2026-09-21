import 'package:http/http.dart' as http;

import 'json_codec_fallback.dart' if (dart.library.io) 'json_codec_crimson.dart'
    as impl;

List<int> encodeJson(Object? value) => impl.encodeJson(value);

Object? decodeResponse(http.Response response) => impl.decodeResponse(response);
