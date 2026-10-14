import 'dart:async';

import 'package:http/http.dart' as http;

import 'default_http_client.dart';
import 'assets.dart';
import 'compression.dart';
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
    this.compression = Compression.zstd,
    this.assetEncoding = AssetEncoding.multipart,
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

  final Compression compression;
  final AssetEncoding assetEncoding;

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
  ///
  /// Caller cancellation signals abort-capable transports and stops waiting.
  /// The default HTTP/2 transport may continue a request already sent.
  Future<SystemOneResult> systemOne({
    required Object? state,
    required Map<String, Question> questions,
    String? model,
    Map<String, Image>? assets,
    Duration? timeout,
    RetryPolicy? retry,
    RetryOverrides? retryOverrides,
    Map<String, String>? headers,
    Future<void>? cancellation,
  }) async =>
      (await systemOneWithResponse(
              state: state,
              questions: questions,
              model: model,
              assets: assets,
              timeout: timeout,
              retry: retry,
              retryOverrides: retryOverrides,
              headers: headers,
              cancellation: cancellation))
          .data;

  /// Typed result and buffered HTTP response from one request and one parse.
  Future<WithResponse<SystemOneResult>> systemOneWithResponse({
    required Object? state,
    required Map<String, Question> questions,
    String? model,
    Map<String, Image>? assets,
    Duration? timeout,
    RetryPolicy? retry,
    RetryOverrides? retryOverrides,
    Map<String, String>? headers,
    Future<void>? cancellation,
  }) async {
    if (state == null) throw TypeSafeException('State is required.');
    validateQuestions(questions);
    final body = await encodeAssetRequest({
      'state': state,
      'questions': questionsToJson(questions),
      'model': model ?? defaultModel,
    }, assets ?? const {}, assetEncoding);
    final result = await sendWithResponse('POST', '/v1/systemone',
        body: body,
        timeout: timeout,
        retry: retry,
        retryOverrides: retryOverrides,
        headers: headers,
        cancellation: cancellation);
    if (result.data is! Map<String, Object?>) {
      throw TypeSafeException('Unexpected systemOne response.');
    }
    return WithResponse(
        SystemOneResult.fromJson(result.data as Map<String, Object?>),
        result.response);
  }

  /// Low-level JSON request used by resources.
  ///
  /// Caller cancellation and timeouts stop waiting for the result; they do not
  /// guarantee that the transport stops a request that was already sent.
  Future<Object?> send(
    String method,
    String path, {
    Object? body,
    Duration? timeout,
    RetryPolicy? retry,
    RetryOverrides? retryOverrides,
    Map<String, String>? headers,
    Future<void>? cancellation,
  }) async =>
      (await sendWithResponse(method, path,
              body: body,
              timeout: timeout,
              retry: retry,
              retryOverrides: retryOverrides,
              headers: headers,
              cancellation: cancellation))
          .data;

  /// Low-level parsed result with buffered HTTP metadata. Non-2xx still throw.
  Future<WithResponse<Object?>> sendWithResponse(
    String method,
    String path, {
    Object? body,
    Duration? timeout,
    RetryPolicy? retry,
    RetryOverrides? retryOverrides,
    Map<String, String>? headers,
    Future<void>? cancellation,
  }) async {
    if (retry != null && retryOverrides != null) {
      throw ArgumentError('Use retry or retryOverrides, not both.');
    }
    final policy = retryOverrides?.apply(this.retry) ?? retry ?? this.retry;
    validateRetryPolicy(policy);
    final attemptTimeout = timeout ?? this.timeout;
    if (attemptTimeout <= Duration.zero) {
      throw ArgumentError.value(attemptTimeout, 'timeout');
    }
    final tag = '#${++_requestCount} $method $path';
    final url = Uri.parse('$baseUrl$path');
    var aborted = false;
    cancellation?.then((_) => aborted = true);
    // Let an already-completed cancellation settle before preparing/sending.
    await Future<void>.value();
    void checkCancellation() {
      if (aborted) throw ApiAbortException();
    }

    checkCancellation();
    final merged = _mergeHeaders(_baseHeaders, headers ?? const {});
    const protected = {
      'authorization',
      'accept',
      'user-agent',
      'x-typesafe-sdk',
      'x-typesafe-runtime',
      'content-type',
      'content-encoding',
      'x-typesafe-retry-count'
    };
    merged.removeWhere((key, _) => protected.contains(key.toLowerCase()));
    for (final e in _baseHeaders.entries) {
      if (protected.contains(e.key.toLowerCase()) &&
          !{'content-type', 'content-encoding', 'x-typesafe-retry-count'}
              .contains(e.key.toLowerCase())) {
        merged[e.key] = e.value;
      }
    }
    List<int>? encoded;
    if (body != null) {
      encoded = body is EncodedBody ? body.bytes : encodeJson(body);
      if (encoded.length > 32 * 1024 * 1024) {
        throw TypeSafeException(
            'Request body exceeds the API limit of 32 MiB.');
      }
      merged['Content-Type'] =
          body is EncodedBody ? body.contentType : 'application/json';
      if (compression == Compression.zstd &&
          encoded.length >= minCompressedBodyBytes) {
        encoded = compressRequest(encoded);
        merged['Content-Encoding'] = 'zstd';
      }
    }
    checkCancellation();

    for (var attempt = 0;; attempt++) {
      checkCancellation();
      final retriesLeft = policy.maxRetries - attempt;
      if (attempt > 0) {
        merged['X-TypeSafe-Retry-Count'] = '$attempt';
      }
      if (_debugEnabled) {
        logger.debug('$tag -> $url', {
          'headers': redactHeaders(merged),
          'body': body is EncodedBody ? body.payload : body,
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
        return WithResponse(parsed, response);
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

    var cancelledByCaller = false;
    final abort = Completer<void>();
    void triggerAbort() {
      if (!abort.isCompleted) abort.complete();
    }

    final timer = Timer(timeout, triggerAbort);
    cancellation?.then((_) {
      cancelledByCaller = true;
      triggerAbort();
    });
    try {
      final request =
          http.AbortableRequest(method, url, abortTrigger: abort.future);
      request.headers.addAll(headers);
      if (encoded != null) request.bodyBytes = encoded;

      final future = httpClient.send(request).then(http.Response.fromStream);
      final raced = cancellation == null
          ? future
          : Future.any([
              future,
              cancellation.then((_) => throw ApiAbortException()),
            ]);

      return await raced.timeout(
        timeout,
        onTimeout: () => throw ApiTimeoutException(timeout),
      );
    } on http.RequestAbortedException {
      if (cancelledByCaller) throw ApiAbortException();
      throw ApiTimeoutException(timeout);
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
    } catch (err) {
      if (err is ApiException || err is TypeSafeException) rethrow;
      if (_infoEnabled) {
        logger.info('$tag connection error after ${elapsed()}', err);
      }
      throw ApiConnectionException('Connection error: $err', err);
    } finally {
      timer.cancel();
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

/// Parsed data plus the buffered response; obtaining it performs no second call.
class WithResponse<T> {
  const WithResponse(this.data, this.response);
  final T data;
  final http.Response response;
  String? get requestId => requestIdFrom(response);
}
