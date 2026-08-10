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

  final Set<String> _integrations = {};

  /// Which companion packages are loaded in this app.
  ///
  /// Network calls are captured by a companion package, never by the core, so
  /// an app that forgot to add the interceptor produces an empty Network tab
  /// that looks exactly like an app making no calls. There is no way to detect
  /// a package that was never constructed, so each one says so when it is
  /// built. Without this, the most common setup mistake has no symptom anyone
  /// can search for.
  Set<String> get integrations => Set.unmodifiable(_integrations);

  /// Called by a companion package when it is constructed. Not meant to be
  /// called by an app.
  void registerIntegration(String name) => _integrations.add(name);

  /// The manager is a singleton, so one test registering an integration would
  /// otherwise leak into every test that runs after it.
  @visibleForTesting
  void resetIntegrations() => _integrations.clear();

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
