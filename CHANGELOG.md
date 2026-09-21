# Changelog

## 0.1.2 - 2026-09-21

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

## 0.1.2

- Dart analysis fix

## 0.1.0

- Example: playground quickstart, JS SDK demo ticket, and a calm contrast case with checks.

- Package name: `jev_dart`.

- Initial Dart client for TypeSafe System One (`systemOne`, `models.list`).
- Question builders: `noul`, `choice`, `score`.
- HTTP/2 default on VM via `package:http2`; `package:http` on web.
- Retries, timeouts, and typed API errors.
