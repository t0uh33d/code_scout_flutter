import 'dart:convert';
import 'dart:developer';

import 'package:code_scout/code_scout.dart';
import 'package:code_scout/src/csx_interface/log_buffer.dart';
import 'package:code_scout/src/live/live_session_client.dart';
import 'package:code_scout/src/log/log_persistence_service.dart';
import 'package:code_scout/src/log/log_printer.dart';
import 'package:code_scout/src/utils/stack_trace_parser.dart';
import 'package:uuid/uuid.dart';

class LogEntry {
  final String id;
  final String sessionID;
  final LogLevel level;
  final String message;
  final dynamic error;
  final StackTrace? stackTrace;
  final Map<String, dynamic>? metadata;
  final Set<String>? tags;
  final DateTime? timestamp;
  final bool isNetworkCall;

  final String? requestId;
  final NetworkCallPhase? callPhase;

  List<String>? _formattedStackTrace;

  List<String>? get formattedStackTrace => _formattedStackTrace;

  List<StackCallDetails>? _stackCallDetails;

  List<StackCallDetails>? get stackCallDetails => _stackCallDetails;

  LogEntry({
    required this.level,
    required this.message,
    required this.sessionID,
    this.error,
    this.stackTrace,
    this.metadata,
    this.tags = const {},
    this.isNetworkCall = false,
    this.requestId,
    this.callPhase,
  })  : id = const Uuid().v4(),
        timestamp = DateTime.now().toUtc() {
    final includeCurrentStackTrace =
        CodeScout.instance.configuration.logging.includeCurrentStackTrace;

    if ((!includeCurrentStackTrace && stackTrace == null) || isNetworkCall) {
      return;
    }

    StackTraceParser parser = StackTraceParser(
      stackTrace: stackTrace == null && includeCurrentStackTrace
          ? StackTrace.current
          : stackTrace,
      methodCount: 10,
    );

    parser.parse();

    _formattedStackTrace = parser.formattedTrace;
    _stackCallDetails = parser.stackCallDetails;
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'session_id': sessionID,
      'level': level.name,
      'message': message,
      'error': error?.toString(),
      'stack_trace': jsonEncode(
        _stackCallDetails?.map((e) => e.toJson()).toList() ?? [],
      ),
      // Network metadata was redacted when it was built; this covers the other
      // case — a developer logging `metadata: {'token': ...}` by hand, which is
      // the same problem and deserves the same answer.
      'metadata': jsonEncode(
        isNetworkCall ? (metadata ?? {}) : (Redactor.metadata(metadata) ?? {}),
      ),
      'tags': jsonEncode(tags?.toList() ?? []),
      'timestamp': timestamp?.toIso8601String(),
      'is_network_call': isNetworkCall ? 1 : 0,
      'request_id': requestId,
      'call_phase': callPhase?.name,
    };
  }

  Future<void> processLogEntry({NetworkData? networkData}) async {
    try {
      CodeScoutConfiguration cfg = CodeScout.instance.configuration;
      if (!cfg.logging.shouldLog(this)) {
        return;
      }

      CSxPrinter printer = CSxPrinter(this);
      printer.printToConsole(networkData: networkData);

      // The on-device overlay reads this, not the table: rows are deleted from
      // SQLite as soon as they upload, so the overlay would empty out behind
      // you with a server configured.
      LogBuffer.i.add(this);

      // Live streaming sits above the sampling gate on purpose. Somebody is
      // watching this device right now, having deliberately paired with it —
      // showing them a sampled-down subset of what their app is doing would
      // make the feature useless exactly when it is being used.
      LiveSessionClient.i.publish(this);

      // Sampling gates the write and nothing above it. A sampled-out launch
      // still prints to the console and still fills the overlay, because those
      // are free and are what you are looking at while you work — what
      // sampling is there to reduce is rows on the server.
      //
      // System logs are exempt, for the same reason they are exempt from the
      // level gate. They are the SDK's own record of something it did to this
      // device — a dashboard edit to a local database — not app volume, and
      // there is no volume to control: they happen when a person presses Save.
      // Sampling one out means the row changed and nothing anywhere says who
      // changed it, which is the one question the record exists to answer.
      if (level != LogLevel.system && !CodeScout.instance.isSessionSampledIn) return;

      await LogPersistenceService.i.saveLogEntry(this);
    } catch (e, st) {
      log('CodeScout: Failed to process log entry: $e', stackTrace: st);
    }
  }
}
