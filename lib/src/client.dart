import 'dart:async';

import 'package:http/http.dart' as http;

import 'default_http_client.dart';
import 'env.dart';
import 'errors.dart';
import 'json_codec.dart';
import 'logging.dart';
import 'models.dart';
import 'questions.dart';
import 'retry.dart';
import 'runtime.dart';
import 'types.dart';
import 'version.dart';

/// Default API root.
const kDefaultBaseUrl = 'https://api.typesafe.ai';

/// Default System One model alias.
const kDefaultModel = 'jev-latest';

final _runtime = describeRuntime();

/// Client for the TypeSafe AI API (Jev / System One).
class TypeSafeClient {
  TypeSafeClient({
    String? apiKey,
    String? baseUrl,
    String? defaultModel,
    LogLevel? logLevel,
    TypeSafeLogger? logger,
    RetryPolicy? retry,
    Duration? timeout,
    Map<String, String>? defaultHeaders,
    bool allowBrowser = false,
    http.Client? httpClient,
    bool closeClient = false,
  })  : _apiKey = resolveApiKey(apiKey) ??
            (throw TypeSafeException(
              'No API key was provided. Pass apiKey to TypeSafeClient or set '
              '${Env.apiKey} or ${Env.apiKeyAlt}.',
            )),
        baseUrl = _stripTrailingSlashes(
          fromCodeOrEnv(baseUrl, Env.baseUrl) ?? kDefaultBaseUrl,
        ),
        defaultModel =
            fromCodeOrEnv(defaultModel, Env.defaultModel) ?? kDefaultModel,
        logLevel = _resolveLogLevel(logLevel),
        retry = _validatedRetry(retry),
        timeout = timeout ?? defaultTimeout,
        defaultHeaders = Map.unmodifiable(defaultHeaders ?? const {}),
        _ownsClient = httpClient == null || closeClient,
        httpClient = httpClient ?? createDefaultHttpClient() {
    if (isBrowser && !allowBrowser) {
      throw TypeSafeException(
        'TypeSafeClient is running in a browser, which would expose your API '
        'key. Call the API from a server instead, or pass allowBrowser: true '
        'if you understand the risk.',
      );
    }
    if (this.timeout <= Duration.zero) {
      throw ArgumentError.value(this.timeout, 'timeout');
    }
    this.logger = withLevel(logger ?? const PrintLogger(), this.logLevel);
    final baseHeaders = _mergeHeaders(this.defaultHeaders, const {});
    baseHeaders['Authorization'] = 'Bearer $_apiKey';
    baseHeaders['Accept'] = 'application/json';
    baseHeaders['User-Agent'] = 'jev_dart/$packageVersion';
    baseHeaders['X-TypeSafe-SDK'] = 'jev_dart/$packageVersion';
    baseHeaders['X-TypeSafe-Runtime'] = _runtime;
    _baseHeaders = Map.unmodifiable(baseHeaders);
    models = Models(this);
  }

  final String _apiKey;

  /// API root without trailing slashes.
  final String baseUrl;

  /// Model used when a request omits `model`.
  final String defaultModel;

  final LogLevel logLevel;
  late final TypeSafeLogger logger;
  final RetryPolicy retry;
  final Duration timeout;
  final Map<String, String> defaultHeaders;
  final http.Client httpClient;
  final bool _ownsClient;
  late final Map<String, String> _baseHeaders;

  late final Models models;

  int _requestCount = 0;

  bool get _debugEnabled => logLevel == LogLevel.debug;

  bool get _infoEnabled =>
      logLevel == LogLevel.debug || logLevel == LogLevel.info;

  /// Answer named questions about text or structured state.
  Future<SystemOneResult> systemOne({
    required Object? state,
    required Map<String, Question> questions,
    String? model,
    Duration? timeout,
    RetryPolicy? retry,
    Map<String, String>? headers,
    Future<void>? cancellation,
  }) async {
    validateQuestions(questions);
    final body = {
      'state': state,
      'questions': questionsToJson(questions),
      'model': model ?? defaultModel,
    };
    final json = await send(
      'POST',
      '/v1/systemone',
      body: body,
      timeout: timeout,
      retry: retry,
      headers: headers,
      cancellation: cancellation,
    );
    if (json is! Map) {
      throw TypeSafeException('Unexpected systemOne response.');
    }
    return SystemOneResult.fromJson(json as Map<String, Object?>);
  }

  /// Low-level JSON request used by resources.
  Future<Object?> send(
    String method,
    String path, {
    Object? body,
    Duration? timeout,
    RetryPolicy? retry,
    Map<String, String>? headers,
    Future<void>? cancellation,
  }) async {
    final policy = retry ?? this.retry;
    validateRetryPolicy(policy);
    final attemptTimeout = timeout ?? this.timeout;
    if (attemptTimeout <= Duration.zero) {
      throw ArgumentError.value(attemptTimeout, 'timeout');
    }
    final tag = '#${++_requestCount} $method $path';
    final url = Uri.parse('$baseUrl$path');
    final merged = headers == null || headers.isEmpty
        ? Map<String, String>.from(_baseHeaders)
        : _mergeHeaders(_baseHeaders, headers);
    if (headers != null && headers.isNotEmpty) {
      // System headers are always authoritative, matching the previous merge
      // order even when callers supply case variants of these names.
      merged['Authorization'] = _baseHeaders['Authorization']!;
      merged['Accept'] = _baseHeaders['Accept']!;
      merged['User-Agent'] = _baseHeaders['User-Agent']!;
      merged['X-TypeSafe-SDK'] = _baseHeaders['X-TypeSafe-SDK']!;
      merged['X-TypeSafe-Runtime'] = _baseHeaders['X-TypeSafe-Runtime']!;
    }
    if (body != null) {
      merged['Content-Type'] = 'application/json';
    }

    // Encode directly to the bytes consumed by package:http. The old
    // jsonEncode -> Request.body path created a JSON String and then encoded
    // that same value to UTF-8 a second time for every attempt.
    final encoded = body == null ? null : encodeJson(body);

    for (var attempt = 0;; attempt++) {
      final retriesLeft = policy.maxRetries - attempt;
      if (attempt > 0) {
        merged['X-TypeSafe-Retry-Count'] = '$attempt';
      }
      if (_debugEnabled) {
        logger.debug('$tag -> $url', {
          'headers': redactHeaders(merged),
          'body': body,
        });
      }

      final started = _infoEnabled ? (Stopwatch()..start()) : null;
      http.Response response;
      try {
        response = await _attempt(
          tag: tag,
          url: url,
          method: method,
          headers: merged,
          encoded: encoded,
          timeout: attemptTimeout,
          cancellation: cancellation,
        );
      } on ApiAbortException {
        rethrow;
      } on ApiTimeoutException catch (err) {
        if (retriesLeft <= 0 || !policy.retryTimeouts) rethrow;
        await _backOff(
            tag, attempt, retriesLeft, err.message, null, policy, cancellation);
        continue;
      } on ApiConnectionException catch (err) {
        if (retriesLeft <= 0 || !policy.retryConnectionErrors) rethrow;
        await _backOff(
            tag, attempt, retriesLeft, err.message, null, policy, cancellation);
        continue;
      }

      final requestId = requestIdFrom(response);
      if (_infoEnabled) {
        logger.info(
          '$tag <- ${response.statusCode} in ${started!.elapsedMilliseconds}ms'
          '${requestId != null ? ' (request $requestId)' : ''}',
        );
      }

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final parsed = _parseBody(response);
        if (_debugEnabled) logger.debug('$tag <- body', parsed);
        return parsed;
      }

      final errorBody = _parseBody(response);
      if (_debugEnabled) logger.debug('$tag <- error body', errorBody);
      final error = ApiException.fromResponse(
        response.statusCode,
        errorBody,
        response.headers,
        requestId: requestId,
      );
      if (retriesLeft <= 0 || !isRetryableStatus(response.statusCode, policy)) {
        throw error;
      }
      await _backOff(
        tag,
        attempt,
        retriesLeft,
        '${response.statusCode}',
        response.headers,
        policy,
        cancellation,
      );
    }
  }

  Future<http.Response> _attempt({
    required String tag,
    required Uri url,
    required String method,
    required Map<String, String> headers,
    required List<int>? encoded,
    required Duration timeout,
    required Future<void>? cancellation,
  }) async {
    final started = _infoEnabled ? (Stopwatch()..start()) : null;
    String elapsed() => '${started?.elapsedMilliseconds ?? 0}ms';
    final abortTrigger = Completer<void>();
    _AttemptAbortReason? abortReason;

    void abort(_AttemptAbortReason reason) {
      if (abortReason != null) return;
      abortReason = reason;
      abortTrigger.complete();
    }

    try {
      final request = http.AbortableRequest(
        method,
        url,
        abortTrigger: abortTrigger.future,
      );
      request.headers.addAll(headers);
      if (encoded != null) request.bodyBytes = encoded;

      final future = httpClient.send(request).then(http.Response.fromStream);
      final raced = cancellation == null
          ? future
          : Future.any([
              future,
              cancellation.then((_) {
                abort(_AttemptAbortReason.caller);
                throw ApiAbortException();
              }),
            ]);

      return await raced.timeout(
        timeout,
        onTimeout: () {
          abort(_AttemptAbortReason.timeout);
          throw ApiTimeoutException(timeout);
        },
      );
    } on ApiAbortException {
      if (_infoEnabled) {
        logger.info('$tag aborted by caller after ${elapsed()}');
      }
      rethrow;
    } on ApiTimeoutException {
      if (_infoEnabled) logger.info('$tag timed out after ${elapsed()}');
      rethrow;
    } on TimeoutException catch (err) {
      if (_infoEnabled) logger.info('$tag timed out after ${elapsed()}');
      throw ApiTimeoutException(timeout, cause: err);
    } on http.RequestAbortedException catch (err) {
      if (abortReason == _AttemptAbortReason.caller) {
        if (_infoEnabled) {
          logger.info('$tag aborted by caller after ${elapsed()}');
        }
        throw ApiAbortException('Request was aborted.', err);
      }
      if (abortReason == _AttemptAbortReason.timeout) {
        if (_infoEnabled) logger.info('$tag timed out after ${elapsed()}');
        throw ApiTimeoutException(timeout, cause: err);
      }
      if (_infoEnabled) {
        logger.info('$tag connection error after ${elapsed()}', err);
      }
      throw ApiConnectionException('Connection error: $err', err);
    } catch (err) {
      if (err is ApiException || err is TypeSafeException) rethrow;
      if (_infoEnabled) {
        logger.info('$tag connection error after ${elapsed()}', err);
      }
      throw ApiConnectionException('Connection error: $err', err);
    }
  }

  Future<void> _backOff(
    String tag,
    int attempt,
    int retriesLeft,
    String reason,
    Map<String, String>? headers,
    RetryPolicy policy,
    Future<void>? cancellation,
  ) async {
    final delay = retryDelay(attempt, headers: headers, policy: policy);
    final nth = attempt + 1;
    final total = attempt + retriesLeft;
    logger.info(
        '$tag retrying in ${delay.inMilliseconds}ms (retry $nth/$total) after $reason');
    try {
      if (cancellation == null) {
        await Future<void>.delayed(delay);
        return;
      }
      await Future.any([
        Future<void>.delayed(delay),
        cancellation.then((_) => throw ApiAbortException()),
      ]);
    } on ApiAbortException {
      logger.info('$tag aborted by caller while waiting to retry');
      rethrow;
    }
  }

  /// Close the underlying HTTP client if this instance created it.
  void close() {
    if (_ownsClient) httpClient.close();
  }

  static RetryPolicy _validatedRetry(RetryPolicy? retry) {
    final policy = retry ?? defaultRetryPolicy;
    validateRetryPolicy(policy);
    return policy;
  }

  static LogLevel _resolveLogLevel(LogLevel? fromCode) {
    if (fromCode != null) return fromCode;
    final fromEnv = readEnv(Env.logLevel);
    if (fromEnv != null) return parseLogLevel(fromEnv, Env.logLevel);
    return defaultLogLevel;
  }
}

enum _AttemptAbortReason { caller, timeout }

String _stripTrailingSlashes(String url) =>
    url.replaceFirst(RegExp(r'/+$'), '');

Map<String, String> _mergeHeaders(
  Map<String, String> a,
  Map<String, String> b,
) {
  final entries = <String, MapEntry<String, String>>{};
  void add(Map<String, String> source) {
    for (final e in source.entries) {
      entries[e.key.toLowerCase()] = e;
    }
  }

  add(a);
  add(b);
  return {for (final e in entries.values) e.key: e.value};
}

Object? _parseBody(http.Response response) {
  return decodeResponse(response);
}
