import 'dart:convert';
import 'dart:math';

import 'package:code_scout/src/log/ansi_color.dart';
import 'package:code_scout/src/log/log_entry.dart';

class CSxPrinter {
  final LogEntry logEntry;

  CSxPrinter(this.logEntry);

  void printToConsole() {
    final buffer = StringBuffer();
    buffer.writeln(
        '[${DateTime.now().toIso8601String()}] [${logEntry.level}] ${logEntry.message}');

    if (logEntry.metadata != null) {
      buffer.writeln('Metadata: ${_formatMetadata(logEntry.metadata!)}');
    }

    if (logEntry.error != null) {
      buffer.writeln('Error: ${logEntry.error.toString()}');
    }

    buffer.writeln(
        'Stack Trace:\n${formatStackTrace(logEntry.stackTrace ?? StackTrace.current, 3)}');

    print(buffer.toString());
  }

  String _formatMetadata(Map<String, dynamic> metadata) {
    return const JsonEncoder.withIndent('  ').convert(metadata);
  }

  String stringifyMessage(dynamic message) {
    final finalMessage = message is Function ? message() : message;
    if (finalMessage is Map || finalMessage is Iterable) {
      var encoder = JsonEncoder.withIndent('  ', toEncodableFallback);
      return encoder.convert(finalMessage);
    } else {
      return finalMessage.toString();
    }
  }

// Handles any object that is causing JsonEncoder() problems
  Object toEncodableFallback(dynamic object) {
    return object.toString();
  }

  int stackTraceBeginIndex = 0;

  String? formatStackTrace(StackTrace? stackTrace, int? methodCount) {
    List<String> lines = stackTrace
        .toString()
        .split('\n')
        .where(
          (line) =>
              !_discardDeviceStacktraceLine(line) &&
              !_discardWebStacktraceLine(line) &&
              !_discardBrowserStacktraceLine(line) &&
              line.isNotEmpty,
        )
        .toList();
    List<String> formatted = [];

    int stackTraceLength =
        (methodCount != null ? min(lines.length, methodCount) : lines.length);
    for (int count = 0; count < stackTraceLength; count++) {
      var line = lines[count];
      if (count < stackTraceBeginIndex) {
        continue;
      }
      formatted.add('#$count   ${line.replaceFirst(RegExp(r'#\d+\s+'), '')}');
    }

    if (formatted.isEmpty) {
      return null;
    } else {
      return formatted.join('\n');
    }
  }

  List<String> excludePaths = [];

  bool _isInExcludePaths(String segment) {
    for (var element in excludePaths) {
      if (segment.startsWith(element)) {
        return true;
      }
    }
    return false;
  }

  final _deviceStackTraceRegex = RegExp(r'#[0-9]+\s+(.+) \((\S+)\)');

  bool _discardDeviceStacktraceLine(String line) {
    var match = _deviceStackTraceRegex.matchAsPrefix(line);
    if (match == null) {
      return false;
    }
    final segment = match.group(2)!;
    if (segment.startsWith('package:logger')) {
      return true;
    }
    return _isInExcludePaths(segment);
  }

  final _browserStackTraceRegex = RegExp(r'^(?:package:)?(dart:\S+|\S+)');

  final _webStackTraceRegex = RegExp(r'^((packages|dart-sdk)/\S+/)');

  bool _discardWebStacktraceLine(String line) {
    var match = _webStackTraceRegex.matchAsPrefix(line);
    if (match == null) {
      return false;
    }
    final segment = match.group(1)!;
    if (segment.startsWith('packages/logger') ||
        segment.startsWith('dart-sdk/lib')) {
      return true;
    }
    return _isInExcludePaths(segment);
  }

  bool _discardBrowserStacktraceLine(String line) {
    var match = _browserStackTraceRegex.matchAsPrefix(line);
    if (match == null) {
      return false;
    }
    final segment = match.group(1)!;
    if (segment.startsWith('package:logger') || segment.startsWith('dart:')) {
      return true;
    }
    return _isInExcludePaths(segment);
  }

  String getTime(DateTime time) {
    String threeDigits(int n) {
      if (n >= 100) return '$n';
      if (n >= 10) return '0$n';
      return '00$n';
    }

    String twoDigits(int n) {
      if (n >= 10) return '$n';
      return '0$n';
    }

    var now = time;
    var h = twoDigits(now.hour);
    var min = twoDigits(now.minute);
    var sec = twoDigits(now.second);
    var ms = threeDigits(now.millisecond);
    var timeSinceStart = now.difference(DateTime.now()).toString();
    return '$h:$min:$sec.$ms (+$timeSinceStart)';
  }
}
