import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:jev_dart/src/json_codec.dart';

void main() {
  final payload = <String, Object?>{
    'state': {
      'document': 'I was charged twice. Please fix this ASAP.',
      'metadata': List.generate(
        32,
        (index) => {
          'id': index,
          'label': 'item-$index',
          'active': index.isEven,
        },
      ),
    },
    'questions': {
      'billing': {
        'type': 'noul',
        'instructions': 'Is this about billing?',
      },
      'category': {
        'type': 'choice',
        'instructions': 'What is this ticket about?',
        'criteria': {
          'billing': null,
          'technical': null,
          'other': null,
        },
      },
    },
    'model': 'jev-latest',
  };

  final jsonText = jsonEncode(payload);
  final jsonBytes = utf8.encode(jsonText);
  final response = http.Response.bytes(
    jsonBytes,
    200,
    headers: {'content-type': 'application/json'},
  );
  final directEncoder = JsonUtf8Encoder();
  const iterations = 10000;
  print('payload bytes: ${jsonBytes.length}');

  _report(
    'encode jsonEncode + utf8.encode',
    iterations,
    () => utf8.encode(jsonEncode(payload)),
  );
  _report(
    'encode JsonUtf8Encoder',
    iterations,
    () => directEncoder.convert(payload),
  );
  _report(
    'encode Crimson fast path',
    iterations,
    () => encodeJson(payload),
  );
  _report(
    'decode utf8.decode + jsonDecode',
    iterations,
    () => jsonDecode(utf8.decode(jsonBytes)),
  );
  _report(
    'decode Crimson fast path',
    iterations,
    () => decodeResponse(response),
  );
}

void _report(String name, int iterations, Object? Function() operation) {
  for (var i = 0; i < 1000; i++) {
    operation();
  }
  final stopwatch = Stopwatch()..start();
  Object? last;
  for (var i = 0; i < iterations; i++) {
    last = operation();
  }
  stopwatch.stop();
  final micros = stopwatch.elapsedMicroseconds;
  print(
    '$name: ${micros / iterations} us/op '
    '(${micros / 1000} ms total, checksum ${last.hashCode})',
  );
}
