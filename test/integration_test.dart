import 'package:jev_dart/jev_dart.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

import 'helpers/dotenv.dart';

void main() {
  final apiKey = apiKeyFromDotEnv() ?? resolveApiKey(null);

  group('live TypeSafe API', () {
    TypeSafeClient? client;

    tearDown(() {
      client?.close();
    });

    test('systemOne noul + choice', () async {
      client = TypeSafeClient(apiKey: apiKey);
      try {
        await _runSystemOne(client!);
      } on ApiConnectionException {
        client?.close();
        client = TypeSafeClient(apiKey: apiKey, httpClient: http.Client());
        await _runSystemOne(client!);
      }
    }, timeout: const Timeout(Duration(seconds: 60)));

    test('models.list', () async {
      client = TypeSafeClient(apiKey: apiKey, httpClient: http.Client());
      final models = await client!.models.list();
      expect(models, isNotEmpty);
      expect(models.any((m) => m.name.contains('jev')), isTrue);
    }, timeout: const Timeout(Duration(seconds: 60)));
  }, skip: apiKey == null ? 'No API key in .env' : false);
}

Future<void> _runSystemOne(TypeSafeClient client) async {
  final result = await client.systemOne(
    state: 'I was charged twice. Please fix this ASAP.',
    questions: {
      'billing': noul('Is this about billing?'),
      'category': choice('What is this ticket about?', {
        'billing': null,
        'technical': null,
        'other': null,
      }),
    },
  );
  expect(result.model, isNotEmpty);
  expect(result.noul('billing').noul, inInclusiveRange(0, 1));
  expect(
    result.choice('category').choice,
    anyOf('billing', 'technical', 'other'),
  );
  expect(result.usage.inputTokens, greaterThan(0));
}
