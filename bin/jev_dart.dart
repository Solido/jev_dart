import 'package:jev_dart/jev_dart.dart';

Future<void> main(List<String> arguments) async {
  final text = arguments.isEmpty
      ? 'I was charged twice. Please fix this ASAP.'
      : arguments.join(' ');

  final client = TypeSafeClient();
  try {
    final result = await client.systemOne(
      state: text,
      questions: {
        'category': choice('What is this ticket about?', {
          'billing': null,
          'technical': null,
          'other': null,
        }),
        'urgent': noul('Is this urgent?'),
      },
    );
    print('model: ${result.model}');
    print('category: ${result.choice('category').choice}');
    print('urgent: ${result.noul('urgent').noul}');
  } finally {
    client.close();
  }
}
