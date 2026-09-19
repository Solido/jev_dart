import 'package:jev_dart/jev_dart.dart';
import 'package:test/test.dart';

void main() {
  test('noul / choice / score builders', () {
    expect(noul('yes?').type, 'noul');
    expect(choice('which?', {'a': null, 'b': 'bee'}).choiceCriteria['b'], 'bee');
    expect(score('how much?', ['low', 'high']).scoreCriteria.length, 2);
  });

  test('score requires two criteria', () {
    expect(() => score('x', ['only']), throwsA(isA<TypeSafeException>()));
  });

  test('validateQuestions rejects empty set', () {
    expect(() => validateQuestions({}), throwsA(isA<TypeSafeException>()));
  });
}
