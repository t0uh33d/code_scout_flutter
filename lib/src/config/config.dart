import 'package:code_scout/src/config/project_creds.dart'
    show ProjectCredentials;
import 'package:code_scout/src/log/log_entry.dart' show LogEntry;
import 'package:code_scout/src/log/log_level.dart' show LogLevel;
import 'package:flutter/foundation.dart';

part 'logging_behaviour.dart';
part 'sync_behaviour.dart';
part 'real_time.dart';

class CodeScoutConfiguration {
  final LoggingBehavior logging;
  final LogSyncBehavior sync;
  final RealTimeConfig realTime;
  final ProjectCredentials? projectCredentials;

  CodeScoutConfiguration({
    LoggingBehavior? logging,
    LogSyncBehavior? sync,
    RealTimeConfig? realTime,
    this.projectCredentials,
  })  : logging = logging ?? LoggingBehavior(),
        sync = sync ?? LogSyncBehavior(),
        realTime = realTime ?? RealTimeConfig();
}
