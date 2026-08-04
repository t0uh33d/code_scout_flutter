import 'dart:async';
import 'dart:convert';
import 'dart:developer' as dev;
import 'dart:io';

import 'package:code_scout/src/config/config.dart';
import 'package:code_scout/src/db/db_dispatcher.dart';
import 'package:code_scout/src/log/log_entry.dart';
import 'package:code_scout/src/session/session_record.dart';
import 'package:flutter/foundation.dart';

/// Turns the configured base link into a socket URL.
///
/// `http` becomes `ws` and `https` becomes `wss`. Getting this wrong in the
/// second direction would silently carry an instance's logs over a plaintext
/// socket while its owner believed TLS was on, which is why it is a named
/// function with its own test rather than an expression inside connect().
String socketUrlFor(String link) {
  final base = Uri.parse(link);
  return base
      .replace(
        scheme: base.scheme == 'https' ? 'wss' : 'ws',
        path: '${base.path.endsWith('/') ? base.path : '${base.path}/'}api/live/socket',
      )
      .toString();
}

/// Where a live session has got to. The overlay renders straight off this, so
/// every state a person can be looking at has a name here.
enum LiveSessionState {
  /// Nothing running. The normal state for an app nobody is debugging.
  idle,

  /// The socket is open and the code has gone up, but the server has not said
  /// yes yet.
  connecting,

  /// Streaming.
  live,

  /// Over, with [LiveSessionClient.error] saying why if it ended badly.
  ended,
}

/// Streams this launch's logs to the dashboard while somebody is watching.
///
/// Deliberately not part of the normal logging path. Logs still go to the
/// console, the overlay buffer and SQLite exactly as they did; live streaming
/// is an extra reader that a person turns on for a few minutes and then turns
/// off again. If it breaks, nothing else notices.
///
/// `dart:io`'s WebSocket, like the rest of this package: adding a socket
/// library to a debugging tool would put it in the dependency tree of every app
/// that installs one.
/// A [ChangeNotifier] so the overlay can rebuild off it directly rather than
/// polling for a state that changes about four times in a session.
class LiveSessionClient extends ChangeNotifier {
  LiveSessionClient._();

  static final LiveSessionClient i = LiveSessionClient._();

  WebSocket? _socket;
  StreamSubscription<dynamic>? _subscription;
  Timer? _heartbeat;

  LiveSessionState _state = LiveSessionState.idle;

  LiveSessionState get state => _state;

  bool get isLive => _state == LiveSessionState.live;

  String? _error;

  /// Why the session ended, when it ended badly. Null otherwise.
  String? get error => _error;

  String? _sessionId;

  /// The dashboard's id for this live session, once the server has confirmed
  /// the pairing.
  String? get sessionId => _sessionId;

  /// How often to tell the server we are still here when the app has logged
  /// nothing. Comfortably inside the server's idle timeout, so a quiet app is
  /// never mistaken for a closed one.
  static const Duration heartbeatInterval = Duration(seconds: 15);

  /// Starts a live session with a code read off the dashboard.
  ///
  /// Returns true once the server has accepted the pairing. Never throws:
  /// pairing fails through [error], because this is called from a button in an
  /// overlay drawn over somebody else's app.
  Future<bool> start({
    required String code,
    required CodeScoutConfiguration configuration,
    required String currentSessionId,
    SessionRecord? session,
  }) async {
    if (_state == LiveSessionState.connecting || _state == LiveSessionState.live) {
      return _state == LiveSessionState.live;
    }

    final creds = configuration.projectCredentials;
    if (creds == null) {
      return _fail('Add your project credentials to use live streaming.');
    }

    _error = null;
    _setState(LiveSessionState.connecting);

    try {
      _socket = await WebSocket.connect(
        socketUrlFor(creds.link),
        headers: creds.authHeaders,
      ).timeout(const Duration(seconds: 15));
    } catch (e) {
      return _fail('Could not reach the server. Check the link and try again.');
    }

    // The first frame is the pairing. The server has already authenticated the
    // credentials by this point, so the code only decides which session to
    // join, never whether we may join one.
    _send({
      'code': code,
      'device': _deviceFacts(currentSessionId, session),
    });

    final accepted = Completer<bool>();

    _subscription = _socket!.listen(
      (raw) => _onMessage(raw, accepted),
      onDone: () {
        if (!accepted.isCompleted) accepted.complete(false);
        _finish(_error ?? 'The connection closed.');
      },
      onError: (Object e) {
        if (!accepted.isCompleted) accepted.complete(false);
        _finish('The connection failed.');
      },
      cancelOnError: true,
    );

    // A server that accepts the socket and then says nothing must not leave a
    // person staring at a spinner.
    final ok = await accepted.future.timeout(
      const Duration(seconds: 15),
      onTimeout: () {
        _fail('The server did not answer. Try again.');
        return false;
      },
    );

    if (ok) {
      _heartbeat = Timer.periodic(heartbeatInterval, (_) => _send({'logs': const []}));
    }
    return ok;
  }

  void _onMessage(dynamic raw, Completer<bool> accepted) {
    Map<String, dynamic> message;
    try {
      message = jsonDecode(raw as String) as Map<String, dynamic>;
    } catch (_) {
      return;
    }

    // A frame carrying req is a question about this device's databases. It can
    // only arrive after pairing, so it is checked before the pairing branch
    // rather than after the early return that used to drop everything the
    // server said once the session was live.
    final req = message['req'];
    if (req is String && req.isNotEmpty) {
      _answer(req, message);
      return;
    }

    if (accepted.isCompleted) return;

    if (message['ok'] == true) {
      _sessionId = message['session_id'] as String?;
      _setState(LiveSessionState.live);
      accepted.complete(true);
      return;
    }

    // The server says the same thing for a wrong code, a used one and an
    // expired one, on purpose. Repeat that rather than inventing detail.
    _error = (message['error'] as String?) ?? 'That code is not valid.';
    accepted.complete(false);
    _closeSocket();
    _setState(LiveSessionState.ended);
  }

  /// Runs one question and sends the answer back under the same request id.
  ///
  /// Always answers, including when the command was nonsense. A dashboard that
  /// gets no reply waits out its full timeout and then cannot tell a broken
  /// query from a phone that went to sleep.
  Future<void> _answer(String req, Map<String, dynamic> message) async {
    final op = message['op'] as String? ?? '';
    final args = (message['args'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};

    Map<String, dynamic> body;
    try {
      body = await DatabaseDispatcher.handle(op, args);
    } catch (e) {
      body = {'ok': false, 'error': e.toString()};
    }

    // The session can end while a query is running: a big page off a cold
    // database takes real time, and the person watching may have closed the tab.
    if (_state != LiveSessionState.live) return;
    _send({...body, 'req': req});
  }

  /// Sends a log to whoever is watching. A no-op unless a session is live, so
  /// the logging path can call it unconditionally.
  void publish(LogEntry entry) {
    if (_state != LiveSessionState.live) return;
    _send({
      'logs': [_wireLog(entry)],
    });
  }

  /// Ends the session from the device's side.
  Future<void> stop() async {
    if (_state == LiveSessionState.idle) return;
    _error = null;
    await _closeSocket();
    _setState(LiveSessionState.idle);
  }

  /// Clears an error so the overlay can offer the code field again.
  void reset() {
    if (_state == LiveSessionState.live || _state == LiveSessionState.connecting) return;
    _error = null;
    _sessionId = null;
    _setState(LiveSessionState.idle);
  }

  // ---------------------------------------------------------------------------

  /// The live wire is its own shape, matching the server's LiveLog. The upload
  /// format is not reused: that one carries a client id and encodes metadata as
  /// a JSON string because it is on its way into a database, neither of which
  /// means anything to a browser rendering one row.
  Map<String, dynamic> _wireLog(LogEntry entry) {
    return {
      'level': entry.level.name,
      'message': entry.message,
      if (entry.error != null) 'error': entry.error.toString(),
      'timestamp': (entry.timestamp ?? DateTime.now().toUtc()).toIso8601String(),
      if (entry.isNetworkCall) 'is_network_call': true,
      if (entry.requestId != null) 'request_id': entry.requestId,
      if (entry.callPhase != null) 'call_phase': entry.callPhase!.name,
    };
  }

  Map<String, dynamic> _deviceFacts(String currentSessionId, SessionRecord? session) {
    return {
      'session_id': currentSessionId,
      'installation_id': session?.installationId ?? '',
      'device_model': session?.deviceModel ?? '',
      'os_name': session?.osName ?? '',
      'os_version': session?.osVersion ?? '',
      'app_version': session?.appVersion ?? '',
      'build_number': session?.buildNumber ?? '',
      'user_id': session?.userId ?? '',
    };
  }

  void _send(Map<String, dynamic> frame) {
    try {
      _socket?.add(jsonEncode(frame));
    } catch (e) {
      // A dead socket is the onDone handler's problem, not this call's. A log
      // that cannot be streamed is not a log that should throw.
      dev.log('CodeScout: live frame not sent: $e');
    }
  }

  bool _fail(String message) {
    _error = message;
    _setState(LiveSessionState.ended);
    return false;
  }

  /// _finish is the involuntary end: the server hung up, or the network did.
  void _finish(String reason) {
    if (_state == LiveSessionState.idle) return;
    _error = reason;
    _closeSocket();
    _setState(LiveSessionState.ended);
  }

  Future<void> _closeSocket() async {
    _heartbeat?.cancel();
    _heartbeat = null;
    final sub = _subscription;
    _subscription = null;
    await sub?.cancel();
    final socket = _socket;
    _socket = null;
    await socket?.close();
    _sessionId = null;
  }

  void _setState(LiveSessionState next) {
    if (_state == next) return;
    _state = next;
    notifyListeners();
  }
}
