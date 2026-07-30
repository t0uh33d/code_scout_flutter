import 'package:code_scout/code_scout.dart';
import 'package:flutter_test/flutter_test.dart';

/// Regression: NetworkManager used to read CodeScout.instance.currentSessionId,
/// which was a `late` field assigned only in init(). Any capture before init()
/// threw a LateInitializationError — and because capture happens inside the
/// caller's request chain, that failed the HTTP request itself rather than just
/// losing a log line.
void main() {
  test('CodeScout is not initialized by default', () {
    expect(CodeScout.instance.isInitialized, isFalse);
  });

  test('a session id exists before init', () {
    expect(CodeScout.instance.currentSessionId, isNotEmpty);
  });

  test('configuration is readable before init', () {
    expect(CodeScout.instance.configuration, isNotNull);
  });

  // These assert only that capture does not THROW. Whether it also skips
  // recording (the isInitialized guards) is not observable from here without
  // reaching into NetworkManager's private state — the guards are redundancy on
  // top of the defaulted fields above, which are what actually prevent the crash.
  group('capture before init does not throw', () {
    test('processNetworkRequest does not throw', () {
      final request = NetworkRequestData(
        method: 'GET',
        url: Uri.parse('https://example.com/thing'),
        headers: const {},
        body: null,
        requestID: NetworkRequestData.newRequestID(),
      );

      expect(
        () => NetworkManager.i.processNetworkRequest(request),
        returnsNormally,
      );
    });

    test('processNetworkResponse does not throw', () {
      final response = NetworkResponseData(
        statusCode: 200,
        headers: const {},
        body: '{}',
      );

      expect(
        () => NetworkManager.i.processNetworkResponse(response, 'no-such-id'),
        returnsNormally,
      );
    });

    test('processNetworkError does not throw', () {
      final error = NetworkErrorData(
        type: 'unknown',
        message: 'boom',
        response: null,
        stackTrace: StackTrace.current,
      );

      expect(
        () => NetworkManager.i.processNetworkError(error, 'no-such-id'),
        returnsNormally,
      );
    });
  });
}
