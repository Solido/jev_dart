import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:jev_dart/jev_dart.dart';
import 'package:test/test.dart';

void main() {
  test('systemOne parses noul and choice', () async {
    final mock = MockClient((request) async {
      expect(request.method, 'POST');
      expect(request.url.path, '/v1/systemone');
      expect(request.headers['authorization'], 'Bearer test-key');
      final body = jsonDecode(request.body) as Map;
      expect(body['model'], 'jev-latest');
      return http.Response(
        jsonEncode({
          'model': 'jev-latest',
          'answers': {
            'billing': {'type': 'noul', 'noul': 0.9},
            'category': {
              'type': 'choice',
              'choice': 'billing',
              'confidence': 0.8,
              'probabilities': {'billing': 0.8, 'other': 0.2},
            },
          },
          'usage': {'input_tokens': 10, 'output_tokens': 2},
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });

    final client = TypeSafeClient(apiKey: 'test-key', httpClient: mock);
    final result = await client.systemOne(
      state: 'charged twice',
      questions: {
        'billing': noul('billing?'),
        'category': choice('cat?', {'billing': null, 'other': null}),
      },
    );
    expect(result.noul('billing').noul, 0.9);
    expect(result.choice('category').choice, 'billing');
    expect(result.usage.inputTokens, 10);
    client.close();
  });

  test('retries 429 then succeeds', () async {
    var n = 0;
    final mock = MockClient((request) async {
      n++;
      if (n == 1) {
        return http.Response('rate', 429, headers: {'retry-after-ms': '1'});
      }
      return http.Response(
        jsonEncode({
          'model': 'jev-latest',
          'answers': {
            'ok': {'type': 'noul', 'noul': 1.0},
          },
          'usage': {'input_tokens': 1, 'output_tokens': 1},
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });

    final client = TypeSafeClient(
      apiKey: 'k',
      httpClient: mock,
      retry: RetryPolicy(backoffInitial: Duration.zero, backoffJitter: 0),
    );
    final result = await client.systemOne(
      state: 'x',
      questions: {'ok': noul()},
    );
    expect(n, 2);
    expect(result.noul('ok').noul, 1.0);
    client.close();
  });

  test('maps 401 to AuthenticationException', () async {
    final mock = MockClient((request) async {
      return http.Response(
        jsonEncode({
          'error': {'message': 'bad key'},
        }),
        401,
        headers: {'content-type': 'application/json'},
      );
    });
    final client = TypeSafeClient(
      apiKey: 'k',
      httpClient: mock,
      retry: RetryPolicy(maxRetries: 0),
    );
    expect(
      () => client.systemOne(state: 'x', questions: {'q': noul()}),
      throwsA(isA<AuthenticationException>()),
    );
    client.close();
  });

  test('caller cancellation aborts the request and does not retry', () async {
    final cancellation = Completer<void>();
    final abortAwareClient = _AbortAwareClient();
    final client = TypeSafeClient(
      apiKey: 'k',
      httpClient: abortAwareClient,
      retry: RetryPolicy(maxRetries: 2),
    );

    final result = client.systemOne(
      state: 'x',
      questions: {'q': noul()},
      cancellation: cancellation.future,
    );
    await abortAwareClient.requestStarted.future;
    cancellation.complete();

    await expectLater(result, throwsA(isA<ApiAbortException>()));
    await abortAwareClient.requestAborted.future;
    expect(abortAwareClient.requestCount, 1);
    client.close();
  });

  test('caller cancellation returns when an injected client ignores abort',
      () async {
    final cancellation = Completer<void>();
    final nonAbortAwareClient = _NonAbortAwareClient();
    final client = TypeSafeClient(
      apiKey: 'k',
      httpClient: nonAbortAwareClient,
      retry: RetryPolicy(maxRetries: 2),
    );

    final result = client.systemOne(
      state: 'x',
      questions: {'q': noul()},
      cancellation: cancellation.future,
    );
    await nonAbortAwareClient.requestStarted.future;
    cancellation.complete();

    await expectLater(result, throwsA(isA<ApiAbortException>()));
    expect(nonAbortAwareClient.requestCount, 1);
    client.close();
  });

  test('timeout aborts the in-flight request', () async {
    final abortAwareClient = _AbortAwareClient();
    final client = TypeSafeClient(
      apiKey: 'k',
      httpClient: abortAwareClient,
      retry: RetryPolicy(maxRetries: 2, retryTimeouts: false),
    );

    final result = client.systemOne(
      state: 'x',
      questions: {'q': noul()},
      timeout: const Duration(milliseconds: 20),
    );
    await abortAwareClient.requestStarted.future;

    await expectLater(result, throwsA(isA<ApiTimeoutException>()));
    await abortAwareClient.requestAborted.future;
    expect(abortAwareClient.requestCount, 1);
    client.close();
  });

  test('models.list unwraps wire format', () async {
    final mock = MockClient((request) async {
      expect(request.method, 'GET');
      expect(request.url.path, '/v1/models');
      return http.Response(
        jsonEncode({
          'models': [
            {
              'name': 'jev-latest',
              'description': 'alias',
              'release_date': '2026-01-01',
            },
          ],
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    final client = TypeSafeClient(apiKey: 'k', httpClient: mock);
    final models = await client.models.list();
    expect(models.single.name, 'jev-latest');
    client.close();
  });

  test('missing api key throws', () {
    expect(
      () => TypeSafeClient(
          httpClient: MockClient((_) async => http.Response('', 200))),
      throwsA(isA<TypeSafeException>()),
    );
  });
}

class _AbortAwareClient extends http.BaseClient {
  final requestStarted = Completer<void>();
  final requestAborted = Completer<void>();
  int requestCount = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requestCount++;
    if (!requestStarted.isCompleted) requestStarted.complete();
    if (request is! http.Abortable || request.abortTrigger == null) {
      throw StateError('Expected an abortable request.');
    }
    await request.abortTrigger;
    if (!requestAborted.isCompleted) requestAborted.complete();
    throw http.RequestAbortedException(request.url);
  }
}

class _NonAbortAwareClient extends http.BaseClient {
  final requestStarted = Completer<void>();
  final _pendingResponse = Completer<http.StreamedResponse>();
  int requestCount = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    requestCount++;
    if (!requestStarted.isCompleted) requestStarted.complete();
    return _pendingResponse.future;
  }
}
