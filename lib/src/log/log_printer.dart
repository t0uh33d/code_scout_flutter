import 'dart:convert';
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

    if (logEntry.formattedStackTrace != null) {
      buffer
          .writeln('Stack Trace:\n${logEntry.formattedStackTrace?.join('\n')}');
    }
    // buffer.writeln('Stack Trace:\n${logEntry.formattedStackTrace?.join('\n')}');

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
