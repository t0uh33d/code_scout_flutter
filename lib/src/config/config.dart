import 'dart:async';

import 'package:code_scout/src/const/global_vars.dart';
import 'package:http/http.dart' as http;

import 'package:code_scout/src/log/log_entry.dart' show LogEntry;
import 'package:code_scout/src/log/log_level.dart' show LogLevel;
import 'package:flutter/foundation.dart';

part 'logging_behaviour.dart';
part 'sync_behaviour.dart';
part 'real_time.dart';
part 'project_creds.dart';

class CodeScoutConfiguration {
  final LoggingBehavior logging;
  final RealTimeConfig realTime;
  final ProjectCredentials? projectCredentials;

  LogSyncBehavior? sync;

  CodeScoutConfiguration({
    LoggingBehavior? logging,
    RealTimeConfig? realTime,
    this.projectCredentials,
    this.sync,
  })  : logging = logging ?? LoggingBehavior(),
        realTime = realTime ?? RealTimeConfig();
}
