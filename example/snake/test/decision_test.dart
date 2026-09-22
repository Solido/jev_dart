import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:jev_dart/jev_dart.dart';
import 'package:jev_snake_demo/jev_snake_demo.dart';
import 'package:test/test.dart';

void main() {
  test('sends typed questions and shields an unsafe Jev proposal', () async {
    final game = SnakeGame();
    final safe = game.moves().where((move) => move.safe).toList();
    final unsafe = directions.firstWhere(
      (direction) => !safe.any((move) => move.direction == direction),
    );
    final probabilities = {
      for (final direction in directions)
        direction.label: direction == unsafe ? 0.91 : 0.03,
    };
    late Map<String, Object?> requestBody;
    final httpClient = MockClient((request) async {
      expect(request.method, 'POST');
      expect(request.url.path, '/v1/systemone');
      requestBody = jsonDecode(request.body) as Map<String, Object?>;
      return http.Response(
        jsonEncode({
          'model': 'jev-latest',
          'answers': {
            'move': {
              'type': 'choice',
              'choice': unsafe.label,
              'confidence': 0.91,
              'probabilities': probabilities,
            },
            'risk': {'type': 'noul', 'noul': 0.97},
            'food': {'type': 'noul', 'noul': 0.92},
          },
          'usage': {'input_tokens': 100, 'output_tokens': 0},
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    final client = TypeSafeClient(
      apiKey: 'test-key',
      httpClient: httpClient,
      closeClient: true,
      logLevel: LogLevel.off,
      retry: RetryPolicy(maxRetries: 0),
    );
    try {
      final decision = await JevDecisionProvider(client).decide(game);
      expect(requestBody['model'], 'jev-latest');
      final questions = requestBody['questions']! as Map<String, Object?>;
      expect(questions.keys, containsAll(['move', 'risk', 'food']));
      expect((questions['move']! as Map<String, Object?>)['type'], 'choice');
      expect((questions['risk']! as Map<String, Object?>)['type'], 'noul');
      expect(decision.proposed, unsafe);
      expect(safe.map((move) => move.direction), contains(decision.executed));
      expect(decision.intervened, isTrue);
      expect(decision.probabilities[unsafe], 0.91);
      expect(decision.deadEndRisk, closeTo(0.03, 1e-9));
      expect(decision.foodReachable, 0.92);
      expect(decision.inputTokens, 100);
    } finally {
      client.close();
    }
  });

  test('rejects incomplete probability maps before a move can be selected',
      () async {
    final httpClient = MockClient((_) async {
      return http.Response(
        jsonEncode({
          'model': 'jev-latest',
          'answers': {
            'move': {
              'type': 'choice',
              'choice': 'UP',
              'confidence': 1.0,
              'probabilities': {'UP': 1.0},
            },
            'risk': {'type': 'noul', 'noul': 1.0},
            'food': {'type': 'noul', 'noul': 1.0},
          },
          'usage': {'input_tokens': 10, 'output_tokens': 0},
        }),
        200,
      );
    });
    final client = TypeSafeClient(
      apiKey: 'test-key',
      httpClient: httpClient,
      closeClient: true,
      logLevel: LogLevel.off,
      retry: RetryPolicy(maxRetries: 0),
    );
    try {
      await expectLater(
        JevDecisionProvider(client).decide(SnakeGame()),
        throwsFormatException,
      );
    } finally {
      client.close();
    }
  });
}
