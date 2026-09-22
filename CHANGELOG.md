# Changelog

## 0.1.5 - 2026-09-23

- Use the platform `package:http` client by default so caller cancellation and
  request timeouts abort the transport. Injected clients that do not support
  abortable requests may continue in the background.
- Parse standard HTTP-date values in `Retry-After` headers, while retaining
  support for ISO-8601 dates accepted by earlier versions.
- Add `http_parser` as a direct dependency for HTTP-date parsing.
- Add a package screenshot and a Snake example; expand the README with the
  package overview and performance characteristics.

## 0.1.4 - 2026-09-21

- Major serialization and memory-path optimization for request/response throughput.
- Native VM/mobile/desktop requests now encode directly to UTF-8 bytes with Crimson,
  avoiding the intermediate JSON `String` and reducing encoding allocations.
- Native JSON responses are decoded from `bodyBytes` through Crimson; non-JSON,
  unsupported targets, and decoder failures retain the tolerant standard fallback.
- Encoded request bytes are reused across retries instead of being serialized again.
- Reduced hot-path allocations by caching invariant headers and removing redundant
  `Map` copies during typed response decoding.
- Avoided stopwatch, redaction, and debug-log allocations when logging is disabled.
- Kept a `JsonUtf8Encoder` fallback for values that expose `toJson()` and for Web.
- Documented the valid-JSON API contract required by the native fast decoder.

## 0.1.1

- Dart analysis fix

## 0.1.0

- Example: playground quickstart, JS SDK demo ticket, and a calm contrast case with checks.

- Package name: `jev_dart`.

- Initial Dart client for TypeSafe System One (`systemOne`, `models.list`).
- Question builders: `noul`, `choice`, `score`.
- HTTP/2 default on VM via `package:http2`; `package:http` on web.
- Retries, timeouts, and typed API errors.
