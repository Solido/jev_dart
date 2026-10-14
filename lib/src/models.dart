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
    RetryOverrides? retryOverrides,
    Map<String, String>? headers,
    Future<void>? cancellation,
  }) async {
    return (await listWithResponse(
            timeout: timeout,
            retry: retry,
            retryOverrides: retryOverrides,
            headers: headers,
            cancellation: cancellation))
        .data;
  }

  /// Models and buffered HTTP metadata from the same request.
  Future<WithResponse<List<ModelCard>>> listWithResponse({
    Duration? timeout,
    RetryPolicy? retry,
    RetryOverrides? retryOverrides,
    Map<String, String>? headers,
    Future<void>? cancellation,
  }) async {
    final result = await _client.sendWithResponse('GET', '/v1/models',
        timeout: timeout,
        retry: retry,
        retryOverrides: retryOverrides,
        headers: headers,
        cancellation: cancellation);
    final json = result.data;
    if (json is! Map || json['models'] is! List) {
      throw TypeSafeException(
          'Unexpected response shape from GET /v1/models; expected { models: [...] }.');
    }
    final cards = (json['models'] as List)
        .map((e) => ModelCard.fromJson(e as Map<String, Object?>))
        .toList();
    return WithResponse(cards, result.response);
  }
}
