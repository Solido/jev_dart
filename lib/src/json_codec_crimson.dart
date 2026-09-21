import 'dart:convert';

import 'package:crimson/crimson.dart';
import 'package:http/http.dart' as http;

final _fallbackEncoder = JsonUtf8Encoder();

/// Encode the wire payload without creating an intermediate JSON String.
///
/// CrimsonWriter covers the JSON values normally used by the SDK. If callers
/// pass a value that relies on dart:convert's `toJson()` convention, retain
/// the public behavior by falling back to the SDK encoder.
List<int> encodeJson(Object? value) {
  try {
    return (CrimsonWriter()..write(value)).toBytes();
  } on ArgumentError {
    return _fallbackEncoder.convert(value);
  }
}

/// Decode a response body while keeping the bytes as bytes on the hot path.
///
/// Crimson intentionally assumes valid JSON. The API contract makes that the
/// hot path; non-JSON responses and parser failures retain the old tolerant
/// dart:convert behavior.
Object? decodeResponse(http.Response response) {
  final bytes = response.bodyBytes;
  if (bytes.isEmpty) return null;

  if (_isUtf8Json(response.headers['content-type'])) {
    try {
      return Crimson(bytes).read();
    } catch (_) {
      // Preserve the old tolerant response behavior for malformed payloads.
    }
  }

  final text = response.body;
  try {
    return jsonDecode(text);
  } on FormatException {
    return text;
  }
}

bool _isUtf8Json(String? contentType) {
  if (contentType == 'application/json') return true;
  if (contentType == null) return false;
  final lower = contentType.toLowerCase();
  final separator = lower.indexOf(';');
  if (separator >= 0) return false;
  return lower.endsWith('/json') || lower.endsWith('+json');
}
