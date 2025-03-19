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

  final Map<String, NetworkRequestData> _requests = {};

  void processNetworkRequest(NetworkRequestData request) {
    _requests[request.requestID] = request;

    request.logEntry.processLogEntry(networkData: request);
  }

  void processNetworkResponse(NetworkResponseData response, String reqID) {
    if (!_requests.containsKey(reqID)) {
      return;
    }

    NetworkRequestData request = _requests[reqID]!;
    response.attachNetworkRequest(request);

    response.logEntry.processLogEntry(networkData: request);

    _requests.remove(reqID);
  }

  void processNetworkError(NetworkErrorData error, String reqID) {
    if (!_requests.containsKey(reqID)) {
      return;
    }

    NetworkRequestData request = _requests[reqID]!;
    error.attachNetworkRequest(request);
    error.logEntry.processLogEntry(networkData: error);

    _requests.remove(reqID);
  }
}
