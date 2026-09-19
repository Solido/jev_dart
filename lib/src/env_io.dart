import 'dart:io';

String? readEnv(String name) {
  final value = Platform.environment[name]?.trim();
  if (value == null || value.isEmpty) return null;
  return value;
}
