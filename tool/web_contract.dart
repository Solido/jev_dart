import 'dart:convert';
import 'package:archive/archive.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:jev_dart/jev_dart.dart';

/// Compile to JavaScript and run with Node. No API key or remote request.
Future<void> main() async {
  var calls = 0;
  final client = TypeSafeClient(
      apiKey: 'fixture',
      allowBrowser: true,
      assetEncoding: AssetEncoding.base64,
      httpClient: MockClient((r) async {
        calls++;
        final bytes = r.headers['content-encoding'] == 'zstd'
            ? ZstdDecoder().decodeBytes(r.bodyBytes)
            : r.bodyBytes;
        final payload = jsonDecode(utf8.decode(bytes)) as Map;
        if (payload['assets'] == null || payload['state'] == null) {
          throw StateError('Web serialization failed');
        }
        return http.Response(
            jsonEncode({
              'model': 'web-fixture',
              'answers': {
                'target': {
                  'type': 'box',
                  'box': {'top': 0, 'bottom': 1, 'left': 0, 'right': 1},
                  'confidence': null
                }
              },
              'usage': {'input_tokens': null, 'output_tokens': null}
            }),
            200);
      }));
  final result = await client.systemOne(state: {
    'image': image([137, 80, 78, 71, 13, 10, 26, 10]),
    'text': 'x' * 2048
  }, questions: {
    'target': box('target')
  });
  if (calls != 1 ||
      result.box('target').box.right != 1 ||
      result.usage.inputTokens != null) {
    throw StateError('Web contract failed');
  }
  client.close();
  print('Web assets, Box, nullable usage and zstd contract passed');
}
