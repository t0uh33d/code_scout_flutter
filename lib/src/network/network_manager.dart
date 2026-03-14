import 'dart:async';
import 'dart:developer';

import 'package:code_scout/code_scout.dart';
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

  Timer? _cleanupTimer;

  void startCleanupTimer() {
    _cleanupTimer?.cancel();
    _cleanupTimer = Timer.periodic(
      const Duration(minutes: 1),
      (_) => _evictStaleRequests(),
    );
  }

  void stopCleanupTimer() {
    _cleanupTimer?.cancel();
    _cleanupTimer = null;
  }

  void _evictStaleRequests() {
    final now = DateTime.now();
    final staleKeys = <String>[];
    for (final entry in _requests.entries) {
      if (now.difference(entry.value.addedAt) > _requestTtl) {
        staleKeys.add(entry.key);
      }
    }
    for (final key in staleKeys) {
      _requests.remove(key);
      log('CodeScout: Evicted stale network request $key');
    }
  }

  void processNetworkRequest(NetworkRequestData request) {
    _requests[request.requestID] = _TimedRequest(request);

    request.logEntry.processLogEntry(networkData: request);
  }

  void processNetworkResponse(NetworkResponseData response, String reqID) {
    final timed = _requests.remove(reqID);
    if (timed == null) {
      log('CodeScout: No matching request for response $reqID');
      return;
    }

    response.attachNetworkRequest(timed.data);
    response.logEntry.processLogEntry(networkData: timed.data);
  }

  void processNetworkError(NetworkErrorData error, String reqID) {
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

  _TimedRequest(this.data) : addedAt = DateTime.now();
}
