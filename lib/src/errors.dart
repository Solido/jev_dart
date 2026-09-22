import 'package:http/http.dart' as http;

import 'retry.dart';

const requestIdHeader = 'x-typesafe-request-id';

String? requestIdFrom(http.BaseResponse response) {
  return response.headers[requestIdHeader] ??
      response.headers.entries
          .where((e) => e.key.toLowerCase() == requestIdHeader)
          .map((e) => e.value)
          .firstOrNull;
}

/// Base class for SDK errors.
class TypeSafeException implements Exception {
  TypeSafeException(this.message, {this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() =>
      cause == null ? message : '$message (cause: $cause)';
}

/// Unsuccessful HTTP response from the API.
class ApiException extends TypeSafeException {
  ApiException(
    this.status,
    this.body,
    this.headers, {
    String? message,
    this.requestId,
  }) : super(message ?? describe(status, body));

  final int status;
  final Object? body;
  final Map<String, String> headers;
  final String? requestId;

  static const _maxRaw = 200;

  static String describe(int status, Object? body) {
    final detail = extractMessage(body);
    if (detail != null) return '$status $detail';
    if (body == null) return '$status status code (no body)';
    final raw = body is String ? body : body.toString();
    if (raw.length > _maxRaw) {
      return '$status ${raw.substring(0, _maxRaw)}…';
    }
    return '$status $raw';
  }

  static ApiException fromResponse(
    int status,
    Object? body,
    Map<String, String> headers, {
    String? requestId,
  }) {
    if (status == 400) {
      return BadRequestException(status, body, headers, requestId: requestId);
    }
    if (status == 401) {
      return AuthenticationException(status, body, headers, requestId: requestId);
    }
    if (status == 403) {
      return PermissionDeniedException(
        status,
        body,
        headers,
        requestId: requestId,
      );
    }
    if (status == 404) {
      return NotFoundException(status, body, headers, requestId: requestId);
    }
    if (status == 422) {
      return UnprocessableEntityException(
        status,
        body,
        headers,
        requestId: requestId,
      );
    }
    if (status == 429) {
      return RateLimitException(status, body, headers, requestId: requestId);
    }
    if (status >= 500) {
      return InternalServerException(
        status,
        body,
        headers,
        requestId: requestId,
      );
    }
    return ApiException(status, body, headers, requestId: requestId);
  }
}

class BadRequestException extends ApiException {
  BadRequestException(
    super.status,
    super.body,
    super.headers, {
    super.requestId,
  });
}

class AuthenticationException extends ApiException {
  AuthenticationException(
    super.status,
    super.body,
    super.headers, {
    super.requestId,
  });
}

class PermissionDeniedException extends ApiException {
  PermissionDeniedException(
    super.status,
    super.body,
    super.headers, {
    super.requestId,
  });
}

class NotFoundException extends ApiException {
  NotFoundException(
    super.status,
    super.body,
    super.headers, {
    super.requestId,
  });
}

class UnprocessableEntityException extends ApiException {
  UnprocessableEntityException(
    super.status,
    super.body,
    super.headers, {
    super.requestId,
  });
}

class RateLimitException extends ApiException {
  RateLimitException(
    super.status,
    super.body,
    super.headers, {
    super.requestId,
  });

  Duration? get retryAfter => parseRetryAfter(headers);
}

class InternalServerException extends ApiException {
  InternalServerException(
    super.status,
    super.body,
    super.headers, {
    super.requestId,
  });
}

class ApiConnectionException extends TypeSafeException {
  ApiConnectionException([
    super.message = 'Connection error.',
    Object? cause,
  ]) : super(cause: cause);
}

class ApiTimeoutException extends ApiConnectionException {
  ApiTimeoutException(this.timeout, {Object? cause})
      : super(
          'Request timed out after ${timeout.inMilliseconds}ms.',
          cause,
        );

  final Duration timeout;
}

class ApiAbortException extends TypeSafeException {
  ApiAbortException([
    super.message = 'Request wait was aborted; the transport may continue.',
    Object? cause,
  ]) : super(cause: cause);
}

String? extractMessage(Object? body) {
  if (body is String) return body.isEmpty ? null : body;
  if (body is! Map) return null;
  final error = body['error'];
  if (error is String) return error;
  if (error is Map && error['message'] is String) {
    return error['message'] as String;
  }
  if (body['message'] is String) return body['message'] as String;
  final detail = body['detail'];
  if (detail is String) return detail;
  if (detail is Map && detail['message'] is String) {
    return detail['message'] as String;
  }
  if (detail is List) return describeValidationErrors(detail);
  return null;
}

String? describeValidationErrors(List<Object?> errors) {
  final parts = <String>[];
  for (final e in errors) {
    if (e is! Map || e['msg'] is! String) continue;
    final loc = e['loc'];
    var path = '';
    if (loc is List) {
      path = loc.where((x) => x != 'body').join('.');
    }
    final msg = e['msg'] as String;
    parts.add(path.isEmpty ? msg : '$path: $msg');
  }
  return parts.isEmpty ? null : parts.join('; ');
}
