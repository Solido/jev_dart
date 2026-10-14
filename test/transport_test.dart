import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:jev_dart/jev_dart.dart';
import 'package:test/test.dart';

void main() {
  for (final cancel in [true, false]) {
    test(
        'IO transport ${cancel ? 'cancellation' : 'timeout'} interrupts mid-body',
        () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final bodyStarted = Completer<void>();
      final release = Completer<void>();
      final abort = Completer<void>();
      final errors = <Object>[];
      server.listen((request) async {
        try {
          await request.drain<void>();
          request.response.headers.contentType = ContentType.json;
          request.response.write('{"model":');
          await request.response.flush();
          bodyStarted.complete();
          await release.future;
          await request.response.close();
        } catch (e) {
          errors.add(e);
        }
      });
      final client = TypeSafeClient(
          apiKey: 'k',
          baseUrl: 'http://127.0.0.1:${server.port}',
          httpClient: http.Client(),
          closeClient: true,
          retry: RetryPolicy(maxRetries: 0));
      addTearDown(() async {
        client.close();
        if (!release.isCompleted) release.complete();
        await server.close(force: true);
      });
      final future = client.systemOne(
          state: 'x',
          questions: {'q': noul('yes?')},
          cancellation: cancel ? abort.future : null,
          timeout: Duration(milliseconds: cancel ? 2000 : 150));
      // Attach rejection handler before waiting for the server.
      final expected = expectLater(
          future,
          throwsA(
              cancel ? isA<ApiAbortException>() : isA<ApiTimeoutException>()));
      await bodyStarted.future;
      if (cancel) abort.complete();
      await expected;
      release.complete();
    });
  }

  test('cancellation during backoff prevents a second attempt', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final first = Completer<void>();
    final abort = Completer<void>();
    var calls = 0;
    server.listen((request) async {
      calls++;
      await request.drain<void>();
      request.response.statusCode = 429;
      request.response.headers.set('retry-after-ms', '1000');
      request.response.write(jsonEncode({
        'error': {'message': 'wait'}
      }));
      await request.response.close();
      if (!first.isCompleted) first.complete();
    });
    final client = TypeSafeClient(
        apiKey: 'k',
        baseUrl: 'http://127.0.0.1:${server.port}',
        httpClient: http.Client(),
        closeClient: true);
    addTearDown(() async {
      client.close();
      await server.close(force: true);
    });
    final future = client.systemOne(
        state: 'x', questions: {'q': noul('yes?')}, cancellation: abort.future);
    final expected = expectLater(future, throwsA(isA<ApiAbortException>()));
    await first.future;
    await Future<void>.delayed(const Duration(milliseconds: 30));
    abort.complete();
    await expected;
    expect(calls, 1);
  });
}
