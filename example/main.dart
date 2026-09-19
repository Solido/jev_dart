import 'package:jev_dart/jev_dart.dart';

Future<void> main() async {
  final client = TypeSafeClient();
  try {
    final result = await client.systemOne(
      state: 'I was charged twice. Please help.',
      questions: {
        'billing': noul('Is this about billing?'),
      },
    );
    print('model: ${result.model}');
    print('billing p(yes): ${result.noul('billing').noul}');
  } finally {
    client.close();
  }
}
