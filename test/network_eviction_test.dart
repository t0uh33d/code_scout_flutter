// Requests nobody ever answered.
//
// A request is held from the moment it goes out until its response or error
// arrives, so the three phases can be stitched into one call. Almost all of
// them arrive. The ones that do not are real: an app killed mid-flight, a
// socket that dies without either callback running, an interceptor whose error
// path the app swallowed. Nothing removed those, so the map only ever grew.
//
// There was a `startCleanupTimer` for that, and nothing ever called it, so the
// eviction had never once run in any app. It is a sweep on insert now, which
// needs no timer running in somebody else's app and looks at exactly the moment
// the map can grow.

import 'package:code_scout/code_scout.dart';
import 'package:code_scout/src/csx_interface/log_buffer.dart';
import 'package:flutter_test/flutter_test.dart';

NetworkRequestData _request(String id) => NetworkRequestData(
      method: 'GET',
      url: Uri.parse('https://api.example.com/thing/$id'),
      headers: const {},
      body: null,
      requestID: id,
    );

NetworkResponseData _response() =>
    NetworkResponseData(statusCode: 200, headers: const {}, body: '{}');

/// The response phases in the buffer, which is what says whether a response
/// found the request it belongs to. An unmatched response is dropped whole.
int _responses() => LogBuffer.i.entries
    .where((e) => e.callPhase == NetworkCallPhase.response)
    .length;

void main() {
  var now = DateTime.utc(2026, 8, 9, 12);

  setUp(() async {
    // minimumLevel matters: network phases are debug, and the default level
    // drops them before the buffer. Without this every assertion below counts
    // zero and passes whether or not anything was evicted.
    await CodeScout.instance.init(
      configuration: CodeScoutConfiguration(
        logging: LoggingBehavior(minimumLevel: LogLevel.all),
      ),
    );
    addTearDown(CodeScout.instance.dispose);

    now = DateTime.utc(2026, 8, 9, 12);
    NetworkManager.i.clock = () => now;
    addTearDown(() => NetworkManager.i.clock = DateTime.now);
  });

  test('a request answered inside the window still pairs', () async {
    final id = NetworkRequestData.newRequestID();
    NetworkManager.i.processNetworkRequest(_request(id));

    // Well inside the two minutes, and past a sweep triggered by other traffic.
    now = now.add(const Duration(seconds: 90));
    NetworkManager.i.processNetworkRequest(
        _request(NetworkRequestData.newRequestID()));

    LogBuffer.i.clear();
    NetworkManager.i.processNetworkResponse(_response(), id);

    expect(_responses(), 1,
        reason: 'a slow but ordinary call lost its request half');
  });

  test('a request nobody answered is dropped once it goes stale', () async {
    final orphan = NetworkRequestData.newRequestID();
    NetworkManager.i.processNetworkRequest(_request(orphan));

    // Past the two minute window. The sweep runs on the next request, because
    // that is the only moment the map can grow.
    now = now.add(const Duration(minutes: 3));
    NetworkManager.i.processNetworkRequest(
        _request(NetworkRequestData.newRequestID()));

    LogBuffer.i.clear();
    // A response arriving this late has nothing to attach to, which is the
    // observable half of "it was evicted".
    NetworkManager.i.processNetworkResponse(_response(), orphan);

    expect(_responses(), 0,
        reason: 'the stale request was still being held, so the map never '
            'stops growing');
  });

  test('one stale request does not take the live ones with it', () async {
    final orphan = NetworkRequestData.newRequestID();
    NetworkManager.i.processNetworkRequest(_request(orphan));

    now = now.add(const Duration(minutes: 3));
    final fresh = NetworkRequestData.newRequestID();
    NetworkManager.i.processNetworkRequest(_request(fresh));

    LogBuffer.i.clear();
    NetworkManager.i.processNetworkResponse(_response(), fresh);

    expect(_responses(), 1,
        reason: 'the sweep evicted a request that was seconds old');
  });
}
