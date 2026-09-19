/// Extended playground demo for [jev_dart].
///
/// Cases come from the TypeSafe quickstart playground, the Dart SDK demo, and a
/// contrast ticket so answers can be checked in code.
///
/// ```sh
/// # TYPESAFE_API_KEY or JEV_API_KEY, or a .env in the package root
/// dart run example/main.dart
/// ```
library;

import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:jev_dart/jev_dart.dart';

Future<void> main() async {
  final apiKey = _apiKey();
  if (apiKey == null) {
    stderr.writeln(
      'Set ${Env.apiKey} or ${Env.apiKeyAlt} (environment or .env).',
    );
    exitCode = 64;
    return;
  }

  var client = TypeSafeClient(apiKey: apiKey, logLevel: LogLevel.info);
  try {
    try {
      await _run(client);
    } on ApiConnectionException {
      stderr.writeln('HTTP/2 failed; retrying with HTTP/1.1.');
      client.close();
      client = TypeSafeClient(apiKey: apiKey, httpClient: http.Client());
      await _run(client);
    }
  } on ApiException catch (e) {
    stderr.writeln('API ${e.status} (request ${e.requestId}): ${e.message}');
    exitCode = 1;
  } on _CheckFailure catch (e) {
    stderr.writeln('Check failed: $e');
    exitCode = 1;
  } finally {
    client.close();
  }
}

Future<void> _run(TypeSafeClient client) async {
  final models = await client.models.list();
  stdout.writeln(
    'models: ${models.map((m) => m.name).join(', ')}',
  );
  _check('at least one model', models.isNotEmpty);

  await _playgroundQuickstart(client);
  await _sdkDemoTicket(client);
  await _calmInvoiceContrast(client);

  stdout.writeln('\nAll playground checks passed.');
}

/// Official quickstart sample: Stripe connect failure, mixed primitives.
///
/// Docs: https://docs.typesafe.ai/introduction/quickstart
Future<void> _playgroundQuickstart(TypeSafeClient client) async {
  _heading('Playground / quickstart — Stripe connect');

  const ticket =
      "Hi, I've been trying to connect my Stripe account for 3 days and "
      "it keeps failing. I'm losing sales. Please help ASAP.";

  final result = await client.systemOne(
    state: ticket,
    questions: {
      'department': choice('Which team should handle this', {
        'billing': 'Payment or subscription issues',
        'technical': 'Bugs or integration problems',
        'sales': 'Pricing or account questions',
      }),
      'frustration': score('How frustrated the customer appears', [
        'Calm, just stating facts',
        'Frustrated but civil',
        'Very angry, strong language',
      ]),
      'is_urgent': noul('The message conveys urgency or time-sensitivity'),
    },
  );

  final department = result.choice('department');
  final frustration = result.score('frustration');
  final urgent = result.noul('is_urgent');

  _printChoice('department', department);
  _printScore('frustration', frustration);
  _printNoul('is_urgent', urgent);
  _printUsage(result);

  _check(
    'department is billing or technical (playground: billing; text is also an integration failure)',
    {'billing', 'technical'}.contains(department.choice),
  );
  _check('not sales', department.choice != 'sales');
  _check('frustration at least civil (playground ~1.0)', frustration.score >= 0.5);
  _check('urgency high (playground ~0.999)', urgent.noul >= 0.8);
}

/// Dart SDK : double charge, structured state.
Future<void> _sdkDemoTicket(TypeSafeClient client) async {
  _heading('Dart SDK demo — charged twice');

  final result = await client.systemOne(
    state: {
      'subject': 'Charged twice this month',
      'body':
          "Hi, I see two charges of \$49 on my card for August. I only have "
          'one account. Please fix this ASAP, I\'m pretty frustrated.',
    },
    questions: {
      'isBilling': noul('Is this ticket about billing?'),
      'sentiment': choice("What is the customer's tone?", {
        'calm': null,
        'frustrated': null,
        'angry': null,
      }),
      'urgency': score('How urgent is this ticket?', [
        'can wait',
        'this week',
        'today',
        'right now',
      ]),
      'refundRisk': score('How likely is the customer to demand a refund?', [
        'unlikely',
        'possible',
        'likely',
      ]),
    },
  );

  final billing = result.noul('isBilling');
  final tone = result.choice('sentiment');
  final urgency = result.score('urgency');
  final refund = result.score('refundRisk');

  _printNoul('isBilling', billing);
  _printChoice('sentiment', tone);
  _printScore('urgency (0–3)', urgency);
  _printScore('refundRisk (0–2)', refund);
  _printUsage(result);

  _check('billing noul high', billing.noul >= 0.8);
  _check(
    'tone frustrated or angry',
    {'frustrated', 'angry'}.contains(tone.choice),
  );
  _check('urgency at least "today" (ASAP)', urgency.score >= 1.5);
}

/// Contrast: polite invoice request should not look urgent or angry.
Future<void> _calmInvoiceContrast(TypeSafeClient client) async {
  _heading('Contrast — calm invoice copy');

  const ticket =
      'Hello, could you please send a copy of last month\'s invoice when '
      'you have a moment? No rush — thank you.';

  final result = await client.systemOne(
    state: ticket,
    questions: {
      'department': choice('Which team should handle this', {
        'billing': 'Payment or subscription issues',
        'technical': 'Bugs or integration problems',
        'sales': 'Pricing or account questions',
      }),
      'frustration': score('How frustrated the customer appears', [
        'Calm, just stating facts',
        'Frustrated but civil',
        'Very angry, strong language',
      ]),
      'is_urgent': noul(
        'The message conveys urgency or time-sensitivity',
        {
          'true': 'Needs action immediately or today',
          'false': 'Can wait; polite or informational',
        },
      ),
    },
  );

  final department = result.choice('department');
  final frustration = result.score('frustration');
  final urgent = result.noul('is_urgent');

  _printChoice('department', department);
  _printScore('frustration', frustration);
  _printNoul('is_urgent', urgent);

  _check('department billing', department.choice == 'billing');
  _check('frustration closer to calm than angry', frustration.score < 1.2);
  _check('urgency low', urgent.noul < 0.5);
}

void _heading(String title) {
  stdout.writeln('\n=== $title ===');
}

void _printNoul(String name, NoulAnswer a) {
  stdout.writeln('$name  noul=${a.noul.toStringAsFixed(3)}');
}

void _printChoice(String name, ChoiceAnswer a) {
  final p = a.probabilities[a.choice];
  final pStr = p == null ? '?' : p.toStringAsFixed(3);
  stdout.writeln(
    '$name  choice=${a.choice}  p=$pStr  confidence=${a.confidence.toStringAsFixed(3)}',
  );
  stdout.writeln('         probabilities=${_fmtMap(a.probabilities)}');
}

void _printScore(String name, ScoreAnswer a) {
  stdout.writeln(
    '$name  score=${a.score.toStringAsFixed(3)}  '
    'confidence=${a.confidence.toStringAsFixed(3)}',
  );
  stdout.writeln('         legend=${a.legend}');
}

void _printUsage(SystemOneResult result) {
  stdout.writeln(
    'model=${result.model}  tokens in=${result.usage.inputTokens} '
    'out=${result.usage.outputTokens}',
  );
}

String _fmtMap(Map<String, double> m) =>
    m.entries.map((e) => '${e.key}=${e.value.toStringAsFixed(3)}').join(', ');

void _check(String label, bool ok) {
  stdout.writeln(ok ? '  ✓ $label' : '  ✗ $label');
  if (!ok) throw _CheckFailure(label);
}

class _CheckFailure implements Exception {
  _CheckFailure(this.label);
  final String label;
  @override
  String toString() => label;
}

String? _apiKey() {
  final fromEnv = resolveApiKey(null);
  if (fromEnv != null) return fromEnv;
  for (final path in ['.env', '../.env', 'example/.env']) {
    final key = _keyFromDotEnv(path);
    if (key != null) return key;
  }
  return null;
}

String? _keyFromDotEnv(String path) {
  final file = File(path);
  if (!file.existsSync()) return null;
  for (final raw in file.readAsLinesSync()) {
    final line = raw.trim();
    if (line.isEmpty || line.startsWith('#')) continue;
    final eq = line.indexOf('=');
    if (eq <= 0) continue;
    final name = line.substring(0, eq).trim();
    if (name != Env.apiKey && name != Env.apiKeyAlt) continue;
    var value = line.substring(eq + 1).trim();
    if (value.length >= 2) {
      final q = value[0];
      if ((q == '"' || q == "'") && value.endsWith(q)) {
        value = value.substring(1, value.length - 1);
      }
    }
    if (value.isNotEmpty) return value;
  }
  return null;
}
