import 'package:http_parser/http_parser.dart' show formatHttpDate;
import 'package:jev_dart/jev_dart.dart';
import 'package:test/test.dart';

void main() {
  test('parseRetryAfter prefers retry-after-ms', () {
    final d = parseRetryAfter({
      'retry-after-ms': '1500',
      'retry-after': '10',
    });
    expect(d, const Duration(milliseconds: 1500));
  });

  test('parseRetryAfter seconds', () {
    expect(parseRetryAfter({'Retry-After': '2'}), const Duration(seconds: 2));
  });

  test('parseRetryAfter HTTP date', () {
    expect(
      parseRetryAfter(
        {'Retry-After': 'Sun, 06 Nov 1994 08:49:37 GMT'},
        now: DateTime.utc(1994, 11, 6, 8, 49),
      ),
      const Duration(seconds: 37),
    );
  });

  test('parseRetryAfter HTTP date in the past returns zero', () {
    expect(
      parseRetryAfter(
        {'Retry-After': 'Sun, 06 Nov 1994 08:49:37 GMT'},
        now: DateTime.utc(1994, 11, 6, 8, 50),
      ),
      Duration.zero,
    );
  });

  test('parseRetryAfter rejects malformed HTTP date', () {
    expect(parseRetryAfter({'Retry-After': 'not a date'}), isNull);
  });

  test('retryDelay caps an HTTP date beyond maxRetryAfter', () {
    final futureDate = DateTime.now().toUtc().add(const Duration(minutes: 1));
    final delay = retryDelay(
      0,
      headers: {'Retry-After': formatHttpDate(futureDate)},
      policy: RetryPolicy(
        backoffInitial: const Duration(milliseconds: 25),
        backoffMax: const Duration(milliseconds: 25),
        backoffJitter: 0,
        maxRetryAfter: const Duration(seconds: 1),
      ),
      random: () => 0,
    );
    expect(delay, const Duration(milliseconds: 25));
  });

  test('retryDelay uses exponential backoff without jitter when random is 0',
      () {
    final d = retryDelay(
      0,
      policy: RetryPolicy(backoffJitter: 0.25),
      random: () => 0,
    );
    expect(d, const Duration(milliseconds: 500));
    final d1 = retryDelay(
      1,
      policy: RetryPolicy(backoffJitter: 0),
      random: () => 0,
    );
    expect(d1, const Duration(milliseconds: 1000));
  });

  test('isRetryableStatus', () {
    expect(isRetryableStatus(429), isTrue);
    expect(isRetryableStatus(503), isTrue);
    expect(isRetryableStatus(400), isFalse);
  });
}
