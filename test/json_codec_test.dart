import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:jev_dart/src/json_codec.dart';
import 'package:test/test.dart';

void main() {
  test('encodes ordinary payloads directly as equivalent UTF-8 JSON', () {
    final value = {
      'message': 'été 😀',
      'empty': <Object?>[],
      'nested': {'enabled': true, 'value': 1.25},
    };

    expect(
      utf8.decode(encodeJson(value)),
      jsonEncode(value),
    );
  });

  test('falls back to dart:convert for toJson values', () {
    final value = _JsonValue('fallback');

    expect(
      utf8.decode(encodeJson(value)),
      '{"value":"fallback"}',
    );
  });

  test('decodes JSON response bytes without a String conversion', () {
    final response = http.Response(
      '{"value":"été 😀"}',
      200,
      headers: {'content-type': 'application/json'},
    );

    expect(decodeResponse(response), {'value': 'été 😀'});
  });

  test('keeps non-JSON response fallback behavior', () {
    final response = http.Response('not json', 200);

    expect(decodeResponse(response), 'not json');
  });
}

class _JsonValue {
  _JsonValue(this.value);

  final String value;

  Map<String, Object?> toJson() => {'value': value};
}
