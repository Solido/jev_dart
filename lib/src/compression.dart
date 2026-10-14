import 'package:archive/archive.dart';

/// Pure Dart zstd works on VM and Web; none sends the original bytes.
enum Compression { zstd, none }

const minCompressedBodyBytes = 1024;

List<int> compressRequest(List<int> bytes) =>
    ZstdEncoder().encodeBytes(bytes, level: 3);
