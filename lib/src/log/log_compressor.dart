import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:code_scout/src/log/log_entry.dart';

class LogCompressor {
  static List<int> compressLogs(List<LogEntry> logs) {
    GZipEncoder encoder = GZipEncoder();

    String jsonLogs = jsonEncode(logs.map((log) => log.toJson()).toList());
    return encoder.encode(utf8.encode(jsonLogs))!;
  }
}
