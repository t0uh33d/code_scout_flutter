import 'dart:math';

class StackCallDetails {
  final int? index;
  final String? method;
  final String? path;
  final int? line;
  final int? column;

  StackCallDetails({
    this.method,
    this.path,
    this.line,
    this.column,
    this.index,
  });

  static final RegExp _regex =
      RegExp(r"#(\d+)\s+([\w\.\<\>\s]+)\s+\(package:(.*):(\d+):(\d+)\)");

  static StackCallDetails? fromString(String line) {
    var match = _regex.firstMatch(line);
    if (match != null) {
      return StackCallDetails(
        column: int.parse(match.group(5)!),
        line: int.parse(match.group(4)!),
        path: match.group(3)!,
        method: match.group(2)!.trim(),
        index: int.parse(match.group(1)!),
      );
    }

    return null;
  }

  Map<String, dynamic> toJson() {
    return {
      'index': index,
      'method': method,
      'path': path,
      'line': line,
      'column': column,
    };
  }
}

class StackTraceParser {
  final int stackTraceBeginIndex;
  final List<String> excludePaths;

  final StackTrace? stackTrace;
  final int? methodCount;

  StackTraceParser({
    this.stackTraceBeginIndex = 0,
    this.excludePaths = const [],
    this.stackTrace,
    this.methodCount = 0,
  });

  final _deviceStackTraceRegex = RegExp(r'#[0-9]+\s+(.+) \((\S+)\)');

  List<String>? _formattedStackTrace;

  List<StackCallDetails>? _stackCallDetails;

  bool _isFormatted = false;

  List<String> get formattedTrace {
    parse();
    return _formattedStackTrace!;
  }

  List<StackCallDetails>? get stackCallDetails {
    if (_stackCallDetails == null) {
      _stackCallDetails = [];
      for (var line in formattedTrace) {
        var details = StackCallDetails.fromString(line);
        if (details != null) {
          _stackCallDetails?.add(details);
        }
      }
    }
    return _stackCallDetails;
  }

  void parse() {
    if (_isFormatted) {
      return;
    }

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
        (methodCount != null ? min(lines.length, methodCount!) : lines.length);
    for (int count = 0; count < stackTraceLength; count++) {
      var line = lines[count];
      if (count < stackTraceBeginIndex) {
        continue;
      }
      formatted.add('#$count   ${line.replaceFirst(RegExp(r'#\d+\s+'), '')}');
    }

    _formattedStackTrace = formatted;
    _isFormatted = true;
  }

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

  bool _isInExcludePaths(String segment) {
    for (var element in excludePaths) {
      if (segment.startsWith(element)) {
        return true;
      }
    }
    return false;
  }
}
