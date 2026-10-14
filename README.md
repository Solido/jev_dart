# jev_dart

Dart client for [TypeSafe AI](https://typesafe.ai) — Jev and all compatibles System One api.

[![pub package](https://img.shields.io/pub/v/jev_dart.svg)](https://pub.dev/packages/jev_dart)

![Jev turns unstructured state into typed probabilistic decisions that software can act on](https://raw.githubusercontent.com/Solido/jev_dart/main/screenshots/jev_dart-overview.png)

This is a **pure Dart** package (no Flutter dependency). Use it from a CLI, a server, or a Flutter app via `import 'package:jev_dart/jev_dart.dart'`.

**Speed and memory use are core design priorities—and a key differentiator of this implementation.** The request path is built to avoid unnecessary work and short-lived copies, while keeping connections reusable. That means less client-side encoding and decoding overhead on each call, without changing the typed API.

![Snake](https://raw.githubusercontent.com/Solido/jev_dart/main/screenshots/snake_demo.png)

## Install

```yaml
dependencies:
  jev_dart: 
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

## Performance and memory

The hot path is designed to reduce both latency and transient memory use:

- **Reuse the connection.** One long-lived HTTP client lets the VM transport pool and reuse its HTTP/2 connection instead of creating a new client for every request. Close the `TypeSafeClient` when you are done with it.
- **Encode once, straight to bytes.** Request JSON is written directly as UTF-8 bytes, avoiding the intermediate JSON string and second UTF-8 encoding. The resulting bytes are also reused across retries, so retrying does not serialize the same payload again.
- **Parse response bytes directly.** On VM, mobile, and desktop, UTF-8 JSON responses are read from their original bytes with Crimson, avoiding an intermediate response string on the normal JSON path.
- **Keep a compatibility fallback.** Values that rely on `toJson()` use Dart's standard JSON encoder. Non-JSON responses and parser failures use the tolerant `dart:convert` path.

These choices target the SDK work it can control; total request time still depends on the network and the API response. The package does not publish comparative benchmark numbers.

## HTTP transport

- **VM / mobile / desktop:** default client is [`Http2Client`](https://pub.dev/packages/http2) (`http2: ^3.1.0`), with pooled HTTP/2 connections to `api.typesafe.ai`.
- **Web:** `package:http` delegates to the browser's HTTP transport. `http2` requires `dart:io`.
- Caller cancellation and timeouts signal transports that support `AbortableRequest`. The current HTTP/2 default ignores the signal, so requests already sent may continue after the SDK stops waiting.

On Web, the package uses Dart's `JsonUtf8Encoder` and standard decoder because Crimson's current VM-oriented implementation is not JavaScript-safe.

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

## Compatibility with the JavaScript SDK

Dart **0.7.0** tracks [TypeSafe JS 0.7.0](https://github.com/typesafe-ai/typesafe-sdk-js/releases/tag/v0.7.0).
See [COMPATIBILITY.md](COMPATIBILITY.md) for proven features and remaining differences.
The same version number identifies the upstream target; the matrix records the scope.
Native HTTP/2 remains the default. HTTP/1 is available by injecting `http.Client()`.

### Migrating from 0.1.x

- `Usage.inputTokens` and `outputTokens` are now `int?`. Handle missing counts as
  unknown, rather than treating them as zero.
- `systemOne` rejects null state, empty Choice criteria, and Noul questions that
  have neither instructions nor a described outcome.
- Request bodies of at least 1 KiB are compressed with pure Dart zstd on VM and
  Web. Pass `compression: Compression.none` for a server that does not accept it.

### Images and Box

Images and Box are experimental upstream. Enable them explicitly and use a
model that supports Box; the JS release recommends `jev-preview`.

```dart
final photo = image(pngBytes); // PNG/JPEG file bytes; IO callers can use File.readAsBytes.
final result = await client.systemOne(
  state: {'photo': photo},
  questions: {'target': box('The dog in `photo`')},
  model: 'jev-preview',
  headers: {'TypeSafe-Danger-Zone-Images': 'true'},
);
print(result.box('target').box.left); // Fraction of image width.
```

Images may also appear in instructions and criteria. Compose text using
`withAssets(['Compare ', photo, ' with ', other])` or `joinAssets([photo, other], ', ')`.
For named references pass `assets: {'<photo>': photo}` and write `<photo>` in the
content. Each image must be referenced. Multipart is the default; configure
`assetEncoding: AssetEncoding.base64` to send JSON with base64 image data.
`Image.fromBase64(text)` accepts file bytes without a `data:` prefix.

### Response metadata and retry overrides

`systemOneWithResponse` and `models.listWithResponse` return `WithResponse<T>`
with `data`, a buffered `http.Response`, and `requestId`, without another call.
HTTP errors still throw. This differs from JS `asResponse()`: the body is already
buffered and parsed. Existing `systemOne` and `models.list` calls still return Futures.

Use `retryOverrides: RetryOverrides(maxRetries: 1)` to inherit the other client
settings. The existing `retry` parameter replaces the whole policy; do not pass both.

Cancellation and timeouts signal an `AbortableRequest`. A supported injected
transport can stop its stream. The current HTTP/2 default ignores that signal,
so the SDK stops waiting while a request already sent may continue.

### Verification and upstream tracking

```sh
python3 tool/upstream_alignment.py --check
python3 tool/upstream_alignment.py --watch
dart test --exclude-tags live
dart run tool/qualify_api.dart /tmp/jev-api-qualification.json
```

The last command uses your configured API key and performs eight live scenarios,
reporting HTTP/2 and HTTP/1 independently with no fallback. The committed
[qualification report](compatibility/api-qualification.json) records the measured scope.
The weekly GitHub workflow creates or updates one alignment issue when releases
or API documentation change. It starts after this workflow is pushed to the default branch.
