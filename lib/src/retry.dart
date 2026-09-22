import 'package:http_parser/http_parser.dart' show parseHttpDate;

/// Retry configuration. Unset override fields inherit client / SDK defaults.
class RetryPolicy {
  RetryPolicy({
    this.maxRetries = 2,
    this.backoffInitial = const Duration(milliseconds: 500),
    this.backoffMax = const Duration(seconds: 5),
    this.backoffJitter = 0.25,
    Set<int>? httpStatuses,
    this.respectRetryAfter = true,
    this.maxRetryAfter = const Duration(seconds: 60),
    this.retryConnectionErrors = true,
    this.retryTimeouts = true,
  }) : httpStatuses = httpStatuses ?? defaultRetryStatuses;

  final int maxRetries;
  final Duration backoffInitial;
  final Duration backoffMax;
  final double backoffJitter;
  final Set<int> httpStatuses;
  final bool respectRetryAfter;
  final Duration maxRetryAfter;
  final bool retryConnectionErrors;
  final bool retryTimeouts;

  RetryPolicy copyWith({
    int? maxRetries,
    Duration? backoffInitial,
    Duration? backoffMax,
    double? backoffJitter,
    Set<int>? httpStatuses,
    bool? respectRetryAfter,
    Duration? maxRetryAfter,
    bool? retryConnectionErrors,
    bool? retryTimeouts,
  }) {
    return RetryPolicy(
      maxRetries: maxRetries ?? this.maxRetries,
      backoffInitial: backoffInitial ?? this.backoffInitial,
      backoffMax: backoffMax ?? this.backoffMax,
      backoffJitter: backoffJitter ?? this.backoffJitter,
      httpStatuses: httpStatuses ?? this.httpStatuses,
      respectRetryAfter: respectRetryAfter ?? this.respectRetryAfter,
      maxRetryAfter: maxRetryAfter ?? this.maxRetryAfter,
      retryConnectionErrors:
          retryConnectionErrors ?? this.retryConnectionErrors,
      retryTimeouts: retryTimeouts ?? this.retryTimeouts,
    );
  }
}

/// HTTP 408, 429, and 5xx.
final defaultRetryStatuses = Set<int>.unmodifiable({
  408,
  429,
  for (var s = 500; s <= 599; s++) s,
});

final defaultRetryPolicy = RetryPolicy();

const defaultTimeout = Duration(seconds: 10);

bool isRetryableStatus(int status, [RetryPolicy? policy]) =>
    (policy ?? defaultRetryPolicy).httpStatuses.contains(status);

/// Parse `retry-after-ms` or `Retry-After` into a [Duration].
Duration? parseRetryAfter(Map<String, String> headers, {DateTime? now}) {
  final lower = <String, String>{
    for (final e in headers.entries) e.key.toLowerCase(): e.value,
  };
  final msRaw = lower['retry-after-ms'];
  if (msRaw != null) {
    final ms = num.tryParse(msRaw);
    if (ms != null && ms >= 0) {
      return Duration(milliseconds: ms.round());
    }
  }
  final raw = lower['retry-after'];
  if (raw == null) return null;
  final seconds = num.tryParse(raw);
  if (seconds != null) {
    if (seconds < 0) return null;
    return Duration(milliseconds: (seconds * 1000).round());
  }
  DateTime? date;
  try {
    date = parseHttpDate(raw);
  } on FormatException {
    // Keep accepting ISO-8601 dates accepted by earlier SDK versions.
    date = DateTime.tryParse(raw);
  }
  if (date == null) return null;
  final delta = date.difference(now ?? DateTime.now());
  return delta.isNegative ? Duration.zero : delta;
}

Duration retryDelay(
  int attempt, {
  Map<String, String>? headers,
  RetryPolicy? policy,
  double Function()? random,
}) {
  policy ??= defaultRetryPolicy;
  if (policy.respectRetryAfter && headers != null) {
    final after = parseRetryAfter(headers);
    if (after != null && after <= policy.maxRetryAfter) return after;
  }
  final expMs = policy.backoffInitial.inMilliseconds * (1 << attempt);
  final capped = expMs < policy.backoffMax.inMilliseconds
      ? expMs
      : policy.backoffMax.inMilliseconds;
  final r = random?.call() ?? 0.5;
  final jittered = (capped * (1 - r * policy.backoffJitter)).round();
  return Duration(milliseconds: jittered);
}

void validateRetryPolicy(RetryPolicy policy) {
  if (policy.maxRetries < 0) {
    throw ArgumentError.value(policy.maxRetries, 'maxRetries');
  }
  if (policy.backoffInitial.isNegative) {
    throw ArgumentError.value(policy.backoffInitial, 'backoffInitial');
  }
  if (policy.backoffMax.isNegative) {
    throw ArgumentError.value(policy.backoffMax, 'backoffMax');
  }
  if (policy.backoffJitter < 0 || policy.backoffJitter > 1) {
    throw ArgumentError.value(policy.backoffJitter, 'backoffJitter');
  }
  for (final status in policy.httpStatuses) {
    if (status < 100 || status > 999) {
      throw ArgumentError.value(status, 'httpStatuses');
    }
  }
  if (policy.maxRetryAfter.isNegative) {
    throw ArgumentError.value(policy.maxRetryAfter, 'maxRetryAfter');
  }
}
