import 'env_stub.dart' if (dart.library.io) 'env_io.dart' as impl;

/// Environment variable names. Explicit constructor values take precedence.
abstract final class Env {
  static const apiKey = 'TYPESAFE_API_KEY';

  /// Alternate key name used in local `.env` files.
  static const apiKeyAlt = 'JEV_API_KEY';
  static const baseUrl = 'TYPESAFE_BASE_URL';
  static const defaultModel = 'TYPESAFE_DEFAULT_MODEL';
  static const logLevel = 'TYPESAFE_LOG_LEVEL';
}

/// Trimmed environment value, or `null` when missing/blank (web: always `null`).
String? readEnv(String name) => impl.readEnv(name);

/// [fromCode] if set, otherwise [readEnv].
String? fromCodeOrEnv(String? fromCode, String envVar) =>
    fromCode ?? readEnv(envVar);

/// API key from code, `TYPESAFE_API_KEY`, then `JEV_API_KEY`.
String? resolveApiKey(String? fromCode) =>
    fromCodeOrEnv(fromCode, Env.apiKey) ?? readEnv(Env.apiKeyAlt);
