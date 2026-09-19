import 'client.dart';
import 'errors.dart';
import 'retry.dart';
import 'types.dart';

/// Access to `GET /v1/models`.
class Models {
  Models(this._client);

  final TypeSafeClient _client;

  /// List models available to the account.
  Future<List<ModelCard>> list({
    Duration? timeout,
    RetryPolicy? retry,
    Map<String, String>? headers,
    Future<void>? cancellation,
  }) async {
    final json = await _client.send(
      'GET',
      '/v1/models',
      timeout: timeout,
      retry: retry,
      headers: headers,
      cancellation: cancellation,
    );
    if (json is! Map || json['models'] is! List) {
      throw TypeSafeException(
        'Unexpected response shape from GET /v1/models; expected { models: [...] }.',
      );
    }
    return (json['models'] as List)
        .map((e) => ModelCard.fromJson(Map<String, Object?>.from(e as Map)))
        .toList();
  }
}
