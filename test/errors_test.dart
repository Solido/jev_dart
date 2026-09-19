import 'package:jev_dart/jev_dart.dart';
import 'package:test/test.dart';

void main() {
  test('ApiException.fromResponse status mapping', () {
    expect(
      ApiException.fromResponse(400, 'x', {}),
      isA<BadRequestException>(),
    );
    expect(
      ApiException.fromResponse(429, 'x', {'retry-after': '1'}),
      isA<RateLimitException>(),
    );
    expect(
      ApiException.fromResponse(500, 'x', {}),
      isA<InternalServerException>(),
    );
  });

  test('extracts validation detail list', () {
    final err = ApiException.fromResponse(422, {
      'detail': [
        {
          'loc': ['body', 'questions'],
          'msg': 'required',
        },
      ],
    }, {});
    expect(err, isA<UnprocessableEntityException>());
    expect(err.message, contains('questions: required'));
  });
}
