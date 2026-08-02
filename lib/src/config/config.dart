import 'dart:async';
import 'dart:io';

import 'package:code_scout/src/const/global_vars.dart';

import 'package:code_scout/src/log/log_entry.dart' show LogEntry;
import 'package:code_scout/src/log/log_level.dart' show LogLevel;
import 'package:flutter/foundation.dart';

part 'logging_behaviour.dart';
part 'sync_behaviour.dart';
part 'real_time.dart';
part 'project_creds.dart';
part 'redaction.dart';

class CodeScoutConfiguration {
  final LoggingBehavior logging;
  final RealTimeConfig realTime;
  final ProjectCredentials? projectCredentials;

  /// What never leaves the device. On by default — see [RedactionBehavior].
  final RedactionBehavior redaction;

  LogSyncBehavior? sync;

  CodeScoutConfiguration({
    LoggingBehavior? logging,
    RealTimeConfig? realTime,
    this.projectCredentials,
    this.sync,
    this.redaction = const RedactionBehavior(),
  })  : logging = logging ?? LoggingBehavior(),
        realTime = realTime ?? RealTimeConfig();
}
