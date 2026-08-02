import 'dart:collection';

import 'package:code_scout/code_scout.dart';
import 'package:flutter/foundation.dart';

/// What the on-device overlay reads.
///
/// Deliberately not the SQLite table. Logs are deleted from there the moment
/// they upload, so with a server configured the overlay would show an emptying
/// list — and the newest log, the one you opened the overlay to look at, would
/// be the first to go. This is a capped in-memory ring of what this launch has
/// logged, which is what someone holding the phone actually wants, and it works
/// identically whether or not a server is configured.
class LogBuffer extends ChangeNotifier {
  static final LogBuffer i = LogBuffer._();

  LogBuffer._();

  /// Enough to scroll back through a bug, few enough that a chatty app cannot
  /// grow the heap without bound. Old entries fall off the back.
  static const int maxEntries = 500;

  final Queue<LogEntry> _entries = Queue<LogEntry>();

  /// Newest first, which is the order the overlay lists them in.
  List<LogEntry> get entries => _entries.toList(growable: false);

  int get length => _entries.length;

  void add(LogEntry entry) {
    _entries.addFirst(entry);
    while (_entries.length > maxEntries) {
      _entries.removeLast();
    }
    // Only when the overlay is open. A chatty app would otherwise schedule a
    // rebuild per log for a widget tree nobody is looking at.
    if (hasListeners) notifyListeners();
  }

  void clear() {
    _entries.clear();
    if (hasListeners) notifyListeners();
  }

  /// Every tag in the buffer, most used first, so the chips are the ones worth
  /// having rather than an alphabetical list of everything ever emitted.
  List<String> tags() {
    final counts = <String, int>{};
    for (final entry in _entries) {
      for (final tag in entry.tags ?? const <String>{}) {
        counts[tag] = (counts[tag] ?? 0) + 1;
      }
    }
    final tags = counts.keys.toList();
    tags.sort((a, b) {
      final byCount = counts[b]!.compareTo(counts[a]!);
      return byCount != 0 ? byCount : a.compareTo(b);
    });
    return tags;
  }

  /// The network calls in the buffer, phases paired by request id, newest
  /// first. The same collapsing the dashboard does, on the same data.
  List<OverlayCall> calls() {
    final byRequest = <String, List<LogEntry>>{};
    final order = <String>[];

    for (final entry in _entries) {
      if (!entry.isNetworkCall || entry.requestId == null) continue;
      final id = entry.requestId!;
      if (!byRequest.containsKey(id)) {
        byRequest[id] = [];
        order.add(id);
      }
      byRequest[id]!.add(entry);
    }

    return order.map((id) => OverlayCall(id, byRequest[id]!)).toList();
  }
}

/// One network call: its phases, and the answers the list needs from them.
class OverlayCall {
  OverlayCall(this.requestId, this.phases);

  final String requestId;

  /// Newest first, because that is the order they came out of the buffer.
  final List<LogEntry> phases;

  LogEntry? phase(NetworkCallPhase want) {
    for (final entry in phases) {
      if (entry.callPhase == want) return entry;
    }
    return null;
  }

  bool get hasRequest => phase(NetworkCallPhase.request) != null;
  bool get hasResponse => phase(NetworkCallPhase.response) != null;
  bool get hasError => phase(NetworkCallPhase.error) != null;

  Map<String, dynamic> get _requestMeta {
    final direct = phase(NetworkCallPhase.request)?.metadata;
    if (direct != null) return direct;
    // The response and error phases nest the request they belong to, so a call
    // whose request phase fell off the back of the buffer still has a method
    // and a path to show.
    for (final entry in phases) {
      final nested = entry.metadata?['request'];
      if (nested is Map<String, dynamic>) return nested;
    }
    return const {};
  }

  String get method => (_requestMeta['method'] as String?) ?? '—';

  String get path {
    final url = _requestMeta['url'] as String?;
    if (url == null || url.isEmpty) return '—';
    var s = url;
    final scheme = s.indexOf('://');
    if (scheme >= 0) {
      s = s.substring(scheme + 3);
      final slash = s.indexOf('/');
      s = slash >= 0 ? s.substring(slash) : '/';
    }
    return s.isEmpty ? '/' : s;
  }

  int? get statusCode {
    final code = phase(NetworkCallPhase.response)?.metadata?['status_code'];
    return code is int ? code : null;
  }

  /// The same four states the dashboard distinguishes.
  String get status {
    if (hasError) return 'error';
    if (statusCode != null) return '$statusCode';
    if (hasResponse) return 'done';
    return 'pending';
  }

  bool get failed => hasError || (statusCode != null && statusCode! >= 400);

  /// Request to response, or null while a call is still in flight — timing an
  /// unfinished call against now would grow every time the list rebuilt.
  Duration? get duration {
    if (!hasRequest || (!hasResponse && !hasError)) return null;
    final start = phase(NetworkCallPhase.request)?.timestamp;
    final end = (phase(NetworkCallPhase.response) ?? phase(NetworkCallPhase.error))?.timestamp;
    if (start == null || end == null || end.isBefore(start)) return null;
    return end.difference(start);
  }

  DateTime? get startedAt => phase(NetworkCallPhase.request)?.timestamp ?? phases.last.timestamp;
}
