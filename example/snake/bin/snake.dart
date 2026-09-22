import 'dart:io';

import 'package:jev_dart/jev_dart.dart';
import 'package:nocterm/nocterm.dart';
import 'package:jev_snake_demo/jev_snake_demo.dart';

Future<void> main() async {
  late final TypeSafeClient client;
  try {
    client = TypeSafeClient();
  } on TypeSafeException catch (error) {
    stderr.writeln(error.message);
    exitCode = 64;
    return;
  }

  try {
    await runApp(
      SnakeApp(
        decisions: JevDecisionProvider(client),
        onQuit: shutdownApp,
      ),
    );
  } finally {
    client.close();
  }
}
