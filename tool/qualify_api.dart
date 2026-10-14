import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:jev_dart/jev_dart.dart';
import '../test/helpers/dotenv.dart';

/// Manual live qualification. Records each transport independently; no fallback.
Future<void> main(List<String> args) async {
  final key = apiKeyFromDotEnv() ?? resolveApiKey(null);
  if (key == null) throw StateError('No API key configured.');
  final rows = <Map<String, Object?>>[];
  for (final transport in ['http2-default', 'http1-injected']) {
    final client = TypeSafeClient(
        apiKey: key,
        httpClient: transport == 'http1-injected' ? http.Client() : null,
        closeClient: true,
        timeout: const Duration(seconds: 15),
        retry: RetryPolicy(maxRetries: 0));
    for (final scenario in [
      'models',
      'text-score-zstd',
      'image-box-multipart-zstd',
      'image-base64'
    ]) {
      final row = <String, Object?>{
        'transport': transport,
        'scenario': scenario
      };
      try {
        if (scenario == 'models') {
          final models = await client.models.list();
          if (models.isEmpty) throw StateError('Empty model list');
          row['models'] = models.map((m) => m.name).toList();
        } else {
          final images = scenario.startsWith('image');
          final base64 = scenario == 'image-base64';
          final active = base64
              ? TypeSafeClient(
                  apiKey: key,
                  httpClient:
                      transport == 'http1-injected' ? http.Client() : null,
                  closeClient: true,
                  assetEncoding: AssetEncoding.base64,
                  timeout: const Duration(seconds: 15),
                  retry: RetryPolicy(maxRetries: 0))
              : client;
          try {
            final result = await active.systemOneWithResponse(
                state: images
                    ? {
                        'photo': image(File('test/fixtures/green-square.png')
                            .readAsBytesSync()),
                        'context': 'A plain green square. ' * 100
                      }
                    : {
                        'document': 'I was charged twice. Please help.',
                        'context': 'Support ticket. ' * 150
                      },
                questions: images
                    ? {
                        'target': box('The green square in photo'),
                        'green': noul('Is photo green?')
                      }
                    : {
                        'yes': noul('Is this about billing?'),
                        'category': choice(
                            'Category?', {'billing': null, 'other': null}),
                        'rating': score('Urgency?', ['low', 'high'])
                      },
                model: images ? 'jev-preview' : null,
                headers:
                    images ? {'TypeSafe-Danger-Zone-Images': 'true'} : null);
            row['model'] = result.data.model;
            row['request_id'] = result.requestId;
            row['status_code'] = result.response.statusCode;
            if (images) {
              final b = result.data.box('target').box;
              if ([b.top, b.bottom, b.left, b.right]
                  .any((v) => !v.isFinite || v < 0 || v > 1)) {
                throw StateError('Box coordinates out of range');
              }
            } else {
              if (result.data.score('rating').legend.length != 2) {
                throw StateError('Score legend mismatch');
              }
            }
          } finally {
            if (base64) active.close();
          }
        }
        row['status'] = 'passed';
      } catch (e) {
        row['status'] = 'failed';
        row['error_type'] = e.runtimeType.toString();
        if (e is ApiException) row['status_code'] = e.status;
      }
      rows.add(row);
      print(
          '$transport $scenario: ${row['status']} ${row['model'] ?? row['error_type'] ?? ''}');
    }
    client.close();
  }
  final report = {
    'date_utc': DateTime.now().toUtc().toIso8601String(),
    'dart_version': packageVersion,
    'upstream_tag': 'v0.7.0',
    'results': rows
  };
  File(args.isEmpty ? '/tmp/jev-api-qualification.json' : args.first)
      .writeAsStringSync(
          '${const JsonEncoder.withIndent('  ').convert(report)}\n');
  if (rows.any((r) => r['status'] == 'failed')) exitCode = 1;
}
