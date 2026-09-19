import 'dart:io';

/// Parse a dotenv file. Values are never printed by tests.
Map<String, String> loadDotEnv({String path = '.env'}) {
  final file = File(path);
  if (!file.existsSync()) return const {};
  final out = <String, String>{};
  for (final raw in file.readAsLinesSync()) {
    final line = raw.trim();
    if (line.isEmpty || line.startsWith('#')) continue;
    final eq = line.indexOf('=');
    if (eq <= 0) continue;
    final key = line.substring(0, eq).trim();
    var value = line.substring(eq + 1).trim();
    if (value.length >= 2) {
      final q = value[0];
      if ((q == '"' || q == "'") && value.endsWith(q)) {
        value = value.substring(1, value.length - 1);
      }
    }
    out[key] = value;
  }
  return out;
}

String? apiKeyFromDotEnv([String path = '.env']) {
  final env = loadDotEnv(path: path);
  final key = env[EnvNames.typesafe] ?? env[EnvNames.jev];
  if (key == null || key.isEmpty) return null;
  return key;
}

abstract final class EnvNames {
  static const typesafe = 'TYPESAFE_API_KEY';
  static const jev = 'JEV_API_KEY';
}
