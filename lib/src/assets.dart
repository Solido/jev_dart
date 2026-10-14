import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import 'errors.dart';
import 'json_codec.dart';

final _random = Random.secure();
String _reference() =>
    '<image:${List.generate(16, (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0')).join()}>';
final _references = RegExp(r'<image:[0-9a-f]{32}>');

/// PNG/JPEG file bytes. The API validates image format, dimensions and limits.
/// Bytes are copied on construction so later caller mutations cannot change a request.
class Image {
  Image(List<int> bytes) : _bytes = Uint8List.fromList(bytes) {
    if (bytes.isEmpty) throw TypeSafeException('Image data is empty.');
    if (bytes.any((b) => b < 0 || b > 255)) {
      throw TypeSafeException('Image data must contain bytes.');
    }
  }
  factory Image.fromBase64(String text) {
    if (text.startsWith('data:')) {
      throw TypeSafeException('Use base64 file bytes without a data: prefix.');
    }
    try {
      return Image(base64Decode(text));
    } on FormatException {
      throw TypeSafeException('Image data must contain valid base64 text.');
    }
  }
  final Uint8List _bytes;
  final String reference = _reference();
  Uint8List get bytes => Uint8List.fromList(_bytes);
  String get type => 'image';
  @override
  String toString() => reference;
  String toJson() => reference;

  String get _contentType {
    const png = [137, 80, 78, 71, 13, 10, 26, 10];
    if (_bytes.length >= 8 &&
        List.generate(8, (i) => _bytes[i] == png[i]).every((v) => v)) {
      return 'image/png';
    }
    if (_bytes.length >= 3 &&
        _bytes[0] == 255 &&
        _bytes[1] == 216 &&
        _bytes[2] == 255) {
      return 'image/jpeg';
    }
    return 'application/octet-stream';
  }
}

Image image(List<int> bytes) => Image(bytes);

/// Text retaining the images that were inserted into it.
class TextWithAssets {
  TextWithAssets(this.text, Iterable<Image> assets)
      : assets = List.unmodifiable(assets);
  final String text;
  final List<Image> assets;
  @override
  String toString() => text;
  String toJson() => text;
}

/// Compose text and assets: withAssets(['Compare ', photo, ' with ', other]).
TextWithAssets withAssets(Iterable<Object?> pieces) => joinAssets(pieces, '');

/// Dart equivalent of JS withAssets.join; supports nested TextWithAssets.
TextWithAssets joinAssets(Iterable<Object?> pieces, [String separator = ',']) {
  final values = pieces.toList();
  final found = <String, Image>{};
  for (final value in values) {
    if (value is Image) {
      found[value.reference] = value;
    }
    if (value is TextWithAssets) {
      for (final asset in value.assets) {
        found[asset.reference] = asset;
      }
    }
  }
  final text = values.map((v) => v?.toString() ?? '').join(separator);
  return TextWithAssets(text, {
    for (final m in _references.allMatches(text))
      if (found.containsKey(m[0])) found[m[0]]!,
  });
}

enum AssetEncoding { multipart, base64 }

/// Prepared once and reused on all retries.
class EncodedBody {
  EncodedBody(this.bytes, this.contentType, this.payload);
  final List<int> bytes;
  final String contentType;
  final Object? payload;
}

/// Replaces assets in content with references and attaches their file data.
Future<EncodedBody> encodeAssetRequest(Map<String, Object?> payload,
    Map<String, Image> named, AssetEncoding encoding) async {
  final names = <Image, String>{for (final e in named.entries) e.value: e.key};
  final known = <String, Image>{
    for (final asset in named.values) asset.reference: asset
  };
  final active = <Object>{};
  var containsReference = false;
  Object? visit(Object? value) {
    if (value is Image) {
      final name = names[value];
      if (name != null) return name;
      known[value.reference] = value;
      return value.reference;
    }
    if (value is TextWithAssets) {
      var text = value.text;
      for (final asset in value.assets) {
        final name = names[asset];
        if (name != null) {
          text = text.replaceAll(asset.reference, name);
        } else {
          known[asset.reference] = asset;
        }
      }
      return text;
    }
    if (value is Map || value is List) {
      if (!active.add(value!)) {
        throw TypeSafeException('Cyclic request content.');
      }
      try {
        if (value is Map) {
          Map<String, Object?>? changed;
          for (final e in value.entries) {
            final key = e.key as String;
            if (_references.hasMatch(key)) containsReference = true;
            final next = visit(e.value);
            if (!identical(next, e.value)) {
              changed ??= Map<String, Object?>.from(value);
              changed[key] = next;
            }
          }
          return changed ?? value;
        }
        final list = value as List;
        List<Object?>? changed;
        for (var i = 0; i < list.length; i++) {
          final next = visit(list[i]);
          if (!identical(next, list[i])) {
            changed ??= List<Object?>.from(list);
            changed[i] = next;
          }
        }
        return changed ?? list;
      } finally {
        active.remove(value);
      }
    }
    if (value is double && !value.isFinite) return value.toString();
    // Preserve the SDK's existing toJson convention for custom values.
    if (value is String && _references.hasMatch(value)) {
      containsReference = true;
    }
    if (value == null || value is String || value is num || value is bool) {
      return value;
    }
    if (!active.add(value)) throw TypeSafeException('Cyclic request content.');
    try {
      return visit((value as dynamic).toJson());
    } finally {
      active.remove(value);
    }
  }

  final converted = visit(payload) as Map<String, Object?>;
  // Keep the ordinary request path bytes-only; scan JSON only for assets.
  if (known.isEmpty && named.isEmpty && !containsReference) {
    return EncodedBody(encodeJson(converted), 'application/json', converted);
  }
  final json = jsonEncode(converted);
  for (final name in named.keys) {
    if (name.trim().isEmpty ||
        !json.contains(
            jsonEncode(name).substring(1, jsonEncode(name).length - 1))) {
      throw TypeSafeException(
          'Asset "$name" is not referenced in the request.');
    }
  }
  final sent = Map<String, Image>.from(named);
  for (final match in _references.allMatches(json)) {
    final reference = match[0]!;
    if (sent.containsKey(reference)) continue;
    final asset = known[reference];
    if (asset == null) {
      throw TypeSafeException(
          'Image reference $reference has no attached image. Use withAssets.');
    }
    sent[reference] = asset;
  }
  if (sent.isEmpty) {
    return EncodedBody(encodeJson(converted), 'application/json', converted);
  }
  if (encoding == AssetEncoding.base64) {
    final body = {
      ...converted,
      'assets': {
        for (final e in sent.entries)
          e.key: {
            'type': 'image',
            'format': e.value._contentType == 'image/png' ? 'png' : 'jpg',
            'data_base64': base64Encode(e.value._bytes),
          },
      }
    };
    if (sent.values.any((a) => a._contentType == 'application/octet-stream')) {
      throw TypeSafeException('Base64 assets require PNG or JPEG bytes.');
    }
    return EncodedBody(encodeJson(body), 'application/json', body);
  }
  final request =
      http.MultipartRequest('POST', Uri.parse('https://unused.invalid'));
  final entries = <String, Object?>{};
  var index = 0;
  final files = <http.MultipartFile>[];
  for (final e in sent.entries) {
    final part = 'asset-${index++}';
    entries[e.key] = {'type': 'image', 'part': part};
    files.add(http.MultipartFile.fromBytes(part, e.value._bytes,
        filename: part, contentType: MediaType.parse(e.value._contentType)));
  }
  final body = {...converted, 'assets': entries};
  request.files.add(http.MultipartFile.fromBytes('request', encodeJson(body),
      contentType: MediaType('application', 'json')));
  request.files.addAll(files);
  final bytes = await request.finalize().toBytes();
  return EncodedBody(bytes, request.headers['content-type']!, body);
}
