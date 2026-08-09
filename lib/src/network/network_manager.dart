import 'dart:developer';

import 'package:code_scout/code_scout.dart';
import 'package:flutter/foundation.dart';
import 'package:code_scout/src/utils/stack_trace_parser.dart';
import 'package:uuid/uuid.dart';

part 'network_request.dart';
part 'network_response.dart';
part 'network_error_data.dart';
part 'network_data.dart';

class NetworkManager {
  static final NetworkManager i = NetworkManager._i();

  NetworkManager._i();

  final Map<String, _TimedRequest> _requests = {};

  static const Duration _requestTtl = Duration(minutes: 2);

  /// Where "now" comes from, so a test can move time without waiting two
  /// minutes for it.
  @visibleForTesting
  DateTime Function() clock = DateTime.now;

  /// Drops requests that were never answered.
  ///
  /// A request is held only until its response or error arrives, and almost all
  /// of them do. The ones that never do are real though: an app killed
  /// mid-flight, a socket that dies without either callback running, an
  /// interceptor whose error path an app swallowed. Nothing would ever remove
  /// those.
  ///
  /// Swept here rather than on a timer. There was a `startCleanupTimer` for
  /// years and nothing ever called it, so the eviction had never once run. A
  /// timer is also the wrong shape: it fires in every app that installs this
  /// package, forever, to walk a map that is usually empty. The map can only
  /// grow when a request is added, so that is the moment to look.
  void _evictStaleRequests() {
    final now = clock();
    _requests.removeWhere((key, timed) {
      if (now.difference(timed.addedAt) <= _requestTtl) return false;
      log('CodeScout: Evicted stale network request $key');
      return true;
    });
  }

  /// Does nothing. Eviction is automatic now, and this never ran: no code in
  /// this package ever called it, so no app was ever running the timer it
  /// started.
  ///
  /// Kept as a no-op for one release rather than deleted, because it is public
  /// on a published package and removing it would break a build to no purpose.
  @Deprecated('Stale requests are evicted automatically. Delete this call.')
  void startCleanupTimer() {}

  @Deprecated('Stale requests are evicted automatically. Delete this call.')
  void stopCleanupTimer() {}

  void processNetworkRequest(NetworkRequestData request) {
    // Telemetry degrades to silence before init — never fail the caller.
    if (!CodeScout.instance.isInitialized) return;

    _evictStaleRequests();
    _requests[request.requestID] = _TimedRequest(request, clock());

    request.logEntry.processLogEntry(networkData: request);
  }

  void processNetworkResponse(NetworkResponseData response, String reqID) {
    if (!CodeScout.instance.isInitialized) return;

    final timed = _requests.remove(reqID);
    if (timed == null) {
      log('CodeScout: No matching request for response $reqID');
      return;
    }

    response.attachNetworkRequest(timed.data);
    response.logEntry.processLogEntry(networkData: timed.data);
  }

  void processNetworkError(NetworkErrorData error, String reqID) {
    if (!CodeScout.instance.isInitialized) return;

    final timed = _requests.remove(reqID);
    if (timed == null) {
      log('CodeScout: No matching request for error $reqID');
      return;
    }

    error.attachNetworkRequest(timed.data);
    error.logEntry.processLogEntry(networkData: error);
  }
}

class _TimedRequest {
  final NetworkRequestData data;
  final DateTime addedAt;

  _TimedRequest(this.data, this.addedAt);
}
