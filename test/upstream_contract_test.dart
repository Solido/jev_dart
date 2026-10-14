import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:jev_dart/jev_dart.dart';
import 'package:test/test.dart';

final fixture =
    jsonDecode(File('test/fixtures/js_0_7_0.json').readAsStringSync()) as Map;
const png = [137, 80, 78, 71, 13, 10, 26, 10, 1, 2, 3];

Object normalize(Object value) {
  final refs = <String, String>{};
  return jsonDecode(jsonEncode(value).replaceAllMapped(
      RegExp(r'<image:[0-9a-f]{32}>'),
      (m) => refs.putIfAbsent(m[0]!, () => '<image:auto${refs.length}>')));
}

Map capture(http.Request request) {
  final type = request.headers['content-type']!;
  if (!type.startsWith('multipart/')) {
    return {'payload': jsonDecode(request.body), 'parts': []};
  }
  final boundary = type.split('boundary=').last;
  final parts = <Map>[];
  Object? payload;
  for (final raw
      in latin1.decode(request.bodyBytes).split('--$boundary').skip(1)) {
    if (raw.startsWith('--')) break;
    final split = raw.indexOf('\r\n\r\n');
    final header = raw.substring(0, split);
    final content = raw.substring(split + 4, raw.length - 2);
    final name = RegExp(r'name="([^"]+)"').firstMatch(header)![1]!;
    if (name == 'request') {
      payload = jsonDecode(utf8.decode(latin1.encode(content)));
    } else {
      parts.add({
        'name': name,
        'content_type': RegExp(r'content-type: (.+)', caseSensitive: false)
            .firstMatch(header)![1]!
            .trim(),
        'data_base64': base64Encode(latin1.encode(content))
      });
    }
  }
  return {'payload': payload, 'parts': parts};
}

void main() {
  for (final name in ['core', 'named_image', 'inline_image', 'joined_images']) {
    test('JS 0.7.0 differential wire contract: $name', () async {
      final client = TypeSafeClient(
          apiKey: 'fixture-key',
          compression: Compression.none,
          httpClient: MockClient((request) async {
            expect(normalize(capture(request)), fixture['requests'][name]);
            return http.Response(jsonEncode(fixture['response']), 200,
                headers: {
                  'content-type': 'application/json',
                  'x-typesafe-request-id': 'fixture-id'
                });
          }));
      addTearDown(client.close);
      final photo = image(png);
      final WithResponse<SystemOneResult> result;
      switch (name) {
        case 'core':
          result = await client.systemOneWithResponse(state: {
            'document': 'ticket'
          }, questions: {
            'yes': noul('yes?'),
            'category': choice('which?', {'a': null, 'b': null}),
            'rating': score('rate', ['low', 'high'])
          });
        case 'named_image':
          result = await client.systemOneWithResponse(
              state: {'photo': photo},
              assets: {'<photo>': photo},
              questions: {'target': box('target in <photo>')},
              model: 'jev-preview');
        case 'inline_image':
          result = await client.systemOneWithResponse(state: {
            'photos': [photo]
          }, questions: {
            'yes': noul(withAssets(['Does ', photo, ' show a dog?']))
          });
        default:
          final other = image(png);
          result = await client.systemOneWithResponse(
              state: withAssets([
                'Compare ',
                joinAssets([photo, other], ' / '),
                '.'
              ]),
              questions: {'yes': noul('same?')});
      }
      expect(result.requestId, 'fixture-id');
      expect(result.response.statusCode, 200);
      expect(result.data.usage.inputTokens, isNull);
      expect(result.data.usage.outputTokens, isNull);
      expect(result.data.box('target').confidence, isNull);
      expect(result.data.box('target').box.left, 0.2);
      expect(result.data.score('rating').score, 0.7);
      expect(result.data.score('rating').legend, {'0': 'low', '1': 'high'});
    });
  }

  test('invalid requests reject asynchronously without sending', () async {
    var calls = 0;
    final client = TypeSafeClient(
        apiKey: 'k',
        httpClient: MockClient((_) async {
          calls++;
          return http.Response('', 200);
        }));
    addTearDown(client.close);
    for (final q in <Map<String, Question>>[
      {},
      {'q': noul()},
      {'q': choice(null, {})},
      {'q': const ScoreQuestion(criteria: [])}
    ]) {
      final future = client.systemOne(state: 'x', questions: q);
      await expectLater(future, throwsA(isA<TypeSafeException>()));
    }
    await expectLater(
        client.systemOne(state: null, questions: {'q': noul('yes?')}),
        throwsA(isA<TypeSafeException>()));
    await expectLater(
        client.systemOne(
            state: 'x',
            questions: {'q': noul('yes?')},
            assets: {'<unused>': image(png)}),
        throwsA(isA<TypeSafeException>()));
    await expectLater(
        client.systemOne(
            state: '<image:00000000000000000000000000000000>',
            questions: {'q': noul('yes?')}),
        throwsA(isA<TypeSafeException>()));
    expect(calls, 0);
  });

  test('base64 assets and stable bytes across retries', () async {
    final bodies = <List<int>>[];
    final client = TypeSafeClient(
        apiKey: 'k',
        assetEncoding: AssetEncoding.base64,
        compression: Compression.none,
        retry: RetryPolicy(backoffInitial: Duration.zero, backoffJitter: 0),
        httpClient: MockClient((r) async {
          bodies.add(r.bodyBytes);
          expect((jsonDecode(r.body) as Map)['assets'], {
            '<photo>': {
              'type': 'image',
              'format': 'png',
              'data_base64': base64Encode(png)
            }
          });
          return bodies.length == 1
              ? http.Response('', 429)
              : http.Response(jsonEncode(fixture['response']), 200);
        }));
    addTearDown(client.close);
    await client.systemOne(
        state: '<photo>',
        assets: {'<photo>': Image.fromBase64(base64Encode(png))},
        questions: {'q': noul('yes?')});
    expect(bodies[0], bodies[1]);
  });

  test('zstd threshold and protected encoding/retry headers', () async {
    final bodies = <List<int>>[];
    final client = TypeSafeClient(
        apiKey: 'k',
        retry: RetryPolicy(backoffInitial: Duration.zero, backoffJitter: 0),
        defaultHeaders: {
          'authorization': 'wrong',
          'content-encoding': 'gzip',
          'x-typesafe-retry-count': '99'
        },
        httpClient: MockClient((r) async {
          bodies.add(r.bodyBytes);
          expect(r.headers['authorization'], 'Bearer k');
          expect(r.headers['content-encoding'], 'zstd');
          expect(r.headers['x-typesafe-retry-count'],
              bodies.length == 1 ? isNull : '1');
          expect(
              jsonDecode(utf8.decode(ZstdDecoder().decodeBytes(r.bodyBytes))), {
            'state': 'x' * 3000,
            'questions': {
              'q': {'type': 'noul', 'instructions': 'yes?'}
            },
            'model': 'jev-latest'
          });
          return bodies.length == 1
              ? http.Response('', 429)
              : http.Response(jsonEncode(fixture['response']), 200);
        }));
    addTearDown(client.close);
    await client.systemOne(state: 'x' * 3000, questions: {'q': noul('yes?')});
    expect(bodies[0], bodies[1]);
    expect(bodies[0].length, lessThan(3000));
  });

  test('small payload and compression none remove caller encoding', () async {
    for (final compression in Compression.values) {
      final client = TypeSafeClient(
          apiKey: 'k',
          compression: compression,
          httpClient: MockClient((r) async {
            expect(r.headers['content-encoding'], isNull);
            expect(jsonDecode(r.body)['state'], 'x');
            return http.Response(jsonEncode(fixture['response']), 200);
          }));
      addTearDown(client.close);
      await client.systemOne(
          state: 'x',
          questions: {'q': noul('yes?')},
          headers: {'Content-Encoding': 'gzip'});
    }
  });

  test('partial retry overrides preserve client status policy', () async {
    var calls = 0;
    final client = TypeSafeClient(
        apiKey: 'k',
        retry: RetryPolicy(httpStatuses: {409}, backoffInitial: Duration.zero),
        httpClient: MockClient((_) async {
          calls++;
          return calls == 1
              ? http.Response('', 409)
              : http.Response(jsonEncode(fixture['response']), 200);
        }));
    addTearDown(client.close);
    await client.systemOne(
        state: 'x',
        questions: {'q': noul('yes?')},
        retryOverrides: const RetryOverrides(maxRetries: 1));
    expect(calls, 2);
  });

  test('zstd threshold is measured on encoded UTF-8 bytes', () async {
    for (final size in [1023, 1024]) {
      final client = TypeSafeClient(
          apiKey: 'k',
          httpClient: MockClient((r) async {
            expect(
                r.headers['content-encoding'], size == 1024 ? 'zstd' : isNull);
            final bytes = size == 1024
                ? ZstdDecoder().decodeBytes(r.bodyBytes)
                : r.bodyBytes;
            expect(bytes.length, size);
            return http.Response('{}', 200);
          }));
      addTearDown(client.close);
      await client.send('POST', '/v1/systemone',
          body: 'é' * ((size - 2) ~/ 2) + (size.isOdd ? 'x' : ''));
    }
  });

  test('models metadata uses one call', () async {
    var calls = 0;
    final client = TypeSafeClient(
        apiKey: 'k',
        httpClient: MockClient((r) async {
          calls++;
          expect(r.headers['content-type'], isNull);
          return http.Response(
              '{"models":[{"name":"jev-preview","description":"preview","release_date":"2026-10-14"}]}',
              200,
              headers: {'x-typesafe-request-id': 'models-id'});
        }));
    addTearDown(client.close);
    final result = await client.models.listWithResponse();
    expect(result.data.single.name, 'jev-preview');
    expect(result.requestId, 'models-id');
    expect(calls, 1);
  });

  test('cyclic data rejects; caller image mutation cannot change bytes',
      () async {
    var calls = 0;
    final original = List<int>.from(png);
    final photo = image(original);
    original[0] = 0;
    photo.bytes[0] = 0;
    final client = TypeSafeClient(
        apiKey: 'k',
        compression: Compression.none,
        httpClient: MockClient((r) async {
          calls++;
          expect(capture(r)['parts'][0]['data_base64'], base64Encode(png));
          return http.Response(jsonEncode(fixture['response']), 200);
        }));
    addTearDown(client.close);
    final cycle = <String, Object?>{};
    cycle['self'] = cycle;
    await expectLater(
        client.systemOne(state: cycle, questions: {'q': noul('yes?')}),
        throwsA(isA<TypeSafeException>()));
    expect(calls, 0);
    await client.systemOne(state: photo, questions: {'q': noul('yes?')});
    expect(calls, 1);
  });

  test('pre-cancelled calls send nothing', () async {
    var calls = 0;
    final client = TypeSafeClient(
        apiKey: 'k',
        httpClient: MockClient((_) async {
          calls++;
          return http.Response('', 200);
        }));
    addTearDown(client.close);
    await expectLater(
        client.systemOne(
            state: 'x',
            questions: {'q': noul('yes?')},
            cancellation: Future.value()),
        throwsA(isA<ApiAbortException>()));
    expect(calls, 0);
  });
}
