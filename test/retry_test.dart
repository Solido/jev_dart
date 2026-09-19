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

  test('retryDelay uses exponential backoff without jitter when random is 0', () {
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
