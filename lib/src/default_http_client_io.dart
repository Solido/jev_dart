import 'package:http/http.dart' as http;
import 'package:http2/client.dart';

http.Client createDefaultHttpClient() {
  // Http2Client is marked @experimental in http2 3.1.0.
  // ignore: experimental_member_use
  return Http2Client();
}
