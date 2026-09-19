# jev_dart

Dart client for [TypeSafe AI](https://typesafe.ai) — Jev, the System One model.

Send **state** and typed **questions** (`noul`, `choice`, `score`); get structured answers your code can branch on.

This is a **pure Dart** package (no Flutter dependency). Use it from a CLI, a server, or a Flutter app via `import 'package:jev_dart/jev_dart.dart'`.

## Install

```yaml
dependencies:
  jev_dart: ^0.1.0
```

Set `TYPESAFE_API_KEY` or `JEV_API_KEY` (also loaded from `.env` in tests and the example), then:

```dart
import 'package:jev_dart/jev_dart.dart';

void main() async {
  final client = TypeSafeClient();
  final result = await client.systemOne(
    state: {'document': 'I was charged twice. Please fix this ASAP.'},
    questions: {
      'category': choice('What is this ticket about?', {
        'billing': null,
        'technical': null,
        'other': null,
      }),
    },
  );
  print(result.choice('category').choice);
  client.close();
}
```

## HTTP transport

- **VM / mobile / desktop:** default client is [`Http2Client`](https://pub.dev/packages/http2) (`http2: ^3.1.0`) — pooled HTTP/2 to `api.typesafe.ai`.
- **Web:** `package:http` `Client` (HTTP/1.1). `http2` needs `dart:io`.
- HTTP/2 only: if the host does not negotiate `h2`, inject HTTP/1.1 explicitly:

```dart
TypeSafeClient(httpClient: http.Client());
```

## Flutter

Import this package. Do not add a Flutter plugin wrapper unless you need widgets or native channels.

## Configuration

Constructor values override environment variables, then SDK defaults.

| Option | Env | Default |
|---|---|---|
| `apiKey` | `TYPESAFE_API_KEY` | required |
| `baseUrl` | `TYPESAFE_BASE_URL` | `https://api.typesafe.ai` |
| `defaultModel` | `TYPESAFE_DEFAULT_MODEL` | `jev-latest` |
| `logLevel` | `TYPESAFE_LOG_LEVEL` | `warn` |
| `timeout` | — | 10s per attempt |
| `retry` | — | 2 retries, 408/429/5xx |

## Example

`example/main.dart` runs three live cases (TypeSafe [quickstart playground](https://docs.typesafe.ai/introduction/quickstart), the [JS SDK demo](https://github.com/typesafe-ai/typesafe-sdk-js/blob/main/examples/demo.ts), and a calm contrast ticket) and **checks** the answers (urgency high vs low, billing vs not sales, etc.):

```sh
dart run example/main.dart
```

Docs: [https://docs.typesafe.ai/](https://docs.typesafe.ai/)
