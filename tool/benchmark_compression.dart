import 'dart:convert';
import 'package:jev_dart/src/compression.dart';

void main() {
  print(
      'Uncompressed bytes, zstd bytes, mean encoding microseconds (JIT; 100 iterations)');
  for (final size in [2048, 32768, 65536]) {
    final bytes =
        utf8.encode(jsonEncode({'state': 'support ticket. ' * (size ~/ 16)}));
    for (var i = 0; i < 20; i++) {
      compressRequest(bytes);
    }
    final clock = Stopwatch()..start();
    var compressed = 0;
    for (var i = 0; i < 100; i++) {
      compressed = compressRequest(bytes).length;
    }
    clock.stop();
    print('${bytes.length}, $compressed, ${clock.elapsedMicroseconds ~/ 100}');
  }
}
