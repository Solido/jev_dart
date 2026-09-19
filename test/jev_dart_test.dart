import 'package:jev_dart/jev_dart.dart';
import 'package:test/test.dart';

void main() {
  test('public API is exported', () {
    expect(kDefaultModel, 'jev-latest');
    expect(packageVersion, isNotEmpty);
  });
}
