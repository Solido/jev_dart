import 'errors.dart';
import 'types.dart';

const logLevels = LogLevel.values;

const defaultLogLevel = LogLevel.warn;

LogLevel parseLogLevel(String value, String source) {
  for (final level in LogLevel.values) {
    if (level.name == value) return level;
  }
  throw TypeSafeException(
    'Invalid log level "$value" from $source. Expected one of: '
    '${LogLevel.values.map((e) => e.name).join(', ')}.',
  );
}

const _prefix = '[typesafe-sdk]';

class PrintLogger implements TypeSafeLogger {
  const PrintLogger();

  @override
  void debug(String message, [Object? extra]) => _log('DEBUG', message, extra);

  @override
  void info(String message, [Object? extra]) => _log('INFO', message, extra);

  @override
  void warn(String message, [Object? extra]) => _log('WARN', message, extra);

  @override
  void error(String message, [Object? extra]) => _log('ERROR', message, extra);

  void _log(String level, String message, Object? extra) {
    if (extra == null) {
      print('$_prefix $level $message');
    } else {
      print('$_prefix $level $message $extra');
    }
  }
}

TypeSafeLogger withLevel(TypeSafeLogger sink, LogLevel level) {
  return _FilteredLogger(sink, level);
}

class _FilteredLogger implements TypeSafeLogger {
  _FilteredLogger(this._sink, this._level);

  final TypeSafeLogger _sink;
  final LogLevel _level;

  bool _enabled(LogLevel at) => at.index >= _level.index;

  @override
  void debug(String message, [Object? extra]) {
    if (_enabled(LogLevel.debug)) _sink.debug(message, extra);
  }

  @override
  void info(String message, [Object? extra]) {
    if (_enabled(LogLevel.info)) _sink.info(message, extra);
  }

  @override
  void warn(String message, [Object? extra]) {
    if (_enabled(LogLevel.warn)) _sink.warn(message, extra);
  }

  @override
  void error(String message, [Object? extra]) {
    if (_enabled(LogLevel.error)) _sink.error(message, extra);
  }
}

const _keyHeaders = {'authorization', 'proxy-authorization', 'x-api-key'};
const _opaqueHeaders = {'cookie', 'set-cookie'};

String _redactKey(String value) {
  final parts = value.split(RegExp(r'\s+'));
  final scheme = parts.length > 1 ? parts.first : null;
  final secret = parts.length > 1 ? parts.sublist(1).join(' ') : value;
  final tail = secret.length > 8 ? secret.substring(secret.length - 4) : '';
  return '${scheme != null ? '$scheme ' : ''}***$tail';
}

Map<String, String> redactHeaders(Map<String, String> headers) {
  return {
    for (final e in headers.entries)
      e.key: _redact(e.key, e.value),
  };
}

String _redact(String name, String value) {
  final lower = name.toLowerCase();
  if (_keyHeaders.contains(lower)) return _redactKey(value);
  if (_opaqueHeaders.contains(lower)) return '***';
  return value;
}
