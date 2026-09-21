import 'dart:convert';

import 'package:http/http.dart' as http;

final _encoder = JsonUtf8Encoder();

List<int> encodeJson(Object? value) => _encoder.convert(value);

Object? decodeResponse(http.Response response) {
  final text = response.body;
  if (text.isEmpty) return null;
  try {
    return jsonDecode(text);
  } on FormatException {
    return text;
  }
}
