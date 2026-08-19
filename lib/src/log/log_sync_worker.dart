import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'dart:io';
import 'dart:math' show Random;

import 'package:code_scout/code_scout.dart';
import 'package:code_scout/src/log/log_compressor.dart';
import 'package:code_scout/src/log/log_persistence_service.dart';
import 'package:code_scout/src/log/sync_backoff.dart';

class LogSyncWorker {
  static final LogSyncWorker i = LogSyncWorker._i();

  LogSyncWorker._i();

  factory LogSyncWorker() {
    return i;
  }

  Timer? _syncTimer;
  bool _syncing = false;
  int _consecutiveFailures = 0;

  /// Set when the server asks for quiet. Cycles are skipped until it passes.
  ///
  /// Skipping rather than rescheduling the timer: the worker stays alive and
  /// `isRunning` stays honestly true. The cost is that the first attempt after
  /// the deadline can be up to one interval late, which errs slower — the safe
  /// direction when a server has just told you to back off.
  DateTime? _backoffUntil;

  /// Shrinks when the server says a batch was too large, and grows back on
  /// success. Starts at the configured size.
  int? _effectiveBatchSize;
  static const int _maxConsecutiveFailures = 5;
  static const Duration _uploadTimeout = Duration(seconds: 30);

  /// Bounds establishing the connection, separately from waiting for a reply.
  /// A phone on a captive portal gets a TCP handshake and then silence, which
  /// no response deadline covers because there is no request in flight yet.
  static const Duration _connectTimeout = Duration(seconds: 10);

  /// The caller's backstop, deliberately longer than [_uploadTimeout] so the
  /// deadline inside _uploadTarGz always fires first. That one can close the
  /// client; this one can only stop waiting.
  static const Duration _uploadBackstop = Duration(seconds: 40);

  /// How long to go quiet after [_maxConsecutiveFailures] in a row. Long
  /// enough that a server which is genuinely gone is left alone, short enough
  /// that one which comes back is picked up without restarting the app.
  static const Duration _failureBackoff = Duration(minutes: 5);

  /// Used when a 429 arrives with no usable Retry-After. Twice the sync
  /// interval: long enough to be a real pause, short enough to recover.
  Duration get _defaultBackoff {
    final interval = CodeScout.instance.configuration.sync?.syncInterval;
    return (interval ?? const Duration(minutes: 5)) * 2;
  }

  bool get isRunning => _syncTimer?.isActive ?? false;

  /// Whether a batch could ever leave this device.
  ///
  /// Both halves are required and neither has a default: without credentials
  /// there is nowhere to send, and without a [LogSyncBehavior] there is no
  /// interval to send on. This is also what decides whether a log is written
  /// to SQLite at all, because a row is only deleted once it has been
  /// uploaded — see LogEntry.processLogEntry.
  bool get canUpload {
    final config = CodeScout.instance.configuration;
    return config.projectCredentials != null && config.sync != null;
  }

  void start() {
    if (_syncTimer?.isActive ?? false) return;

    final config = CodeScout.instance.configuration;

    if (config.projectCredentials == null) {
      log('LogSyncWorker: Project credentials are not configured.');
      return;
    }

    if (config.sync == null) {
      log('LogSyncWorker: Sync behavior is not configured.');
      return;
    }

    _consecutiveFailures = 0;

    _syncTimer = Timer.periodic(
      config.sync!.syncInterval,
      (_) => _sync(),
    );
  }

  void stop() {
    _syncTimer?.cancel();
    _syncTimer = null;
  }

  /// Runs one cycle now instead of waiting for the timer, and completes when
  /// the upload has either landed or failed.
  ///
  /// Everything the timer does applies: an in-flight cycle is not doubled, a
  /// server-requested backoff is still honoured, and nothing is deleted locally
  /// until the server has taken it.
  Future<void> flush() => _sync();

  /// Ends the pause now, for a person who asked.
  ///
  /// [flush] alone returns immediately while a backoff is running, so a button
  /// wired only to it would be a guaranteed no-op on the one screen that exists
  /// to explain the pause. Safe because it takes a deliberate tap: the backoff
  /// is there to stop an automatic loop hammering a server that is down, not to
  /// overrule somebody who has just fixed it.
  void clearBackoff() => _backoffUntil = null;

  /// How long the worker is currently holding off, or null when it is not.
  Duration? get backoffRemaining {
    final until = _backoffUntil;
    if (until == null) return null;
    final left = until.difference(DateTime.now());
    return left.isNegative ? null : left;
  }

  Future<void> _sync() async {
    if (_syncing) return;

    final until = _backoffUntil;
    if (until != null && DateTime.now().isBefore(until)) return;

    _syncing = true;

    final config = CodeScout.instance.configuration;
    final syncBehaviour = config.sync;
    final creds = config.projectCredentials;
    if (syncBehaviour == null || creds == null) {
      _syncing = false;
      return;
    }

    List<Map<String, dynamic>> logs = [];
    List<String> logIds = [];
    File? file;

    // Set when a batch of one is refused for size. Such a log cannot be made
    // to fit by any amount of halving, so it is deleted rather than rolled
    // back — see the UploadTooLarge branch below.
    bool discardOversized = false;

    try {
      _effectiveBatchSize ??= syncBehaviour.maxBatchSize;
      logs = await LogPersistenceService.i
          .getLogEntries(limit: _effectiveBatchSize!);

      if (logs.isEmpty) {
        _syncing = false;
        return;
      }

      logIds = logs.map((l) => l['id'] as String).toList();

      // Mark logs as syncing so concurrent cycles don't pick them up
      await LogPersistenceService.i.markAsSyncing(logIds);

      // The session records these logs belong to. Not just the current launch:
      // a batch can carry logs from a previous one that was killed before it
      // could sync, and those need their session sent too or they arrive with
      // no device and no user attached.
      final sessions = await _sessionsFor(logs);

      // Compress
      file = await LogCompressor.compress(logs, sessions);

      // Upload with timeout
      await _uploadTarGz(creds.link, file, creds.authHeaders)
          .timeout(_uploadBackstop);

      // Success — delete the logs from DB
      await LogPersistenceService.i.deleteLogEntries(logIds);

      // Session records outlive their logs by one step, so this is where the
      // finished ones go. The current launch is kept: it has no logs left this
      // instant, but it is still running.
      await LogPersistenceService.i
          .pruneSessions(CodeScout.instance.currentSessionId);

      _consecutiveFailures = 0;
      _backoffUntil = null;
      _growBatch(syncBehaviour.maxBatchSize);
    } catch (e, st) {
      // A throttle and an oversized batch are the server working correctly.
      // Neither touches the failure counter, so neither can reach the pause
      // below — that keeps its original meaning: this server is broken, or
      // these credentials are wrong.
      if (e is SyncBackoff) {
        _backoffUntil = DateTime.now().add(e.retryAfter);
        log('LogSyncWorker: server asked for ${e.retryAfter.inSeconds}s of quiet.');
      } else if (e is UploadTooLarge) {
        // A batch of one that is still refused can never be made to fit, and
        // halving one is one. Rolling it back means re-sending the same log on
        // every cycle forever, and because it is the oldest row it is picked
        // first every time — so nothing written after it ever uploads either
        // and the device's database grows without bound behind it. One log is
        // a smaller loss than every log.
        if (logIds.length <= 1) {
          discardOversized = true;
          log('LogSyncWorker: a single log is larger than the server accepts; '
              'discarding it so the queue can drain.');
        } else {
          _shrinkBatch();
          log('LogSyncWorker: batch refused as too large, retrying with $_effectiveBatchSize.');
        }
      } else {
        log('LogSyncWorker: Sync failed: $e', stackTrace: st);
        _consecutiveFailures++;
      }

      // Roll back sync_status so logs are retried next cycle — unless the
      // server has told us this one will never be accepted, in which case
      // retrying it is what jams the queue.
      if (logIds.isNotEmpty) {
        try {
          if (discardOversized) {
            await LogPersistenceService.i.deleteLogEntries(logIds);
          } else {
            await LogPersistenceService.i.markAsUnsync(logIds);
          }
        } catch (rollbackError) {
          log('LogSyncWorker: Failed to rollback sync status: $rollbackError');
        }
      }

      // Repeated failures buy quiet, not death.
      //
      // This used to call stop(), which ended uploading for the rest of the
      // launch — a server down for a minute cost every log until the app was
      // restarted, and nothing said so. The point of the counter is to stop
      // hammering a server that is not answering, and a long pause does that
      // while still recovering on its own when the server comes back.
      if (_consecutiveFailures >= _maxConsecutiveFailures) {
        _backoffUntil = DateTime.now().add(_failureBackoff);
        _consecutiveFailures = 0;
        log('LogSyncWorker: $_maxConsecutiveFailures failures in a row, '
            'pausing for ${_failureBackoff.inMinutes}m.');
      }
    } finally {
      // Clean up temp file
      try {
        if (file != null && await file.exists()) {
          await file.delete();
        }
      } catch (_) {}
      _syncing = false;
    }
  }

  /// Halves the batch, with a floor of one.
  ///
  /// Dropping the log that will not fit is the caller's job, in the
  /// UploadTooLarge branch of [_sync]. This comment used to claim it happened
  /// here, and it did not happen anywhere: a batch already at one was halved to
  /// one and rolled back, so an oversized log was re-sent every cycle for the
  /// life of the app and held every later log behind it.
  void _shrinkBatch() {
    final current = _effectiveBatchSize ?? 100;
    _effectiveBatchSize = current <= 1 ? 1 : current ~/ 2;
  }

  /// Grows back toward the configured size after a success, so one large batch
  /// does not permanently halve the throughput.
  void _growBatch(int configured) {
    final current = _effectiveBatchSize;
    if (current == null || current >= configured) return;
    final grown = current * 2;
    _effectiveBatchSize = grown > configured ? configured : grown;
  }

  /// The distinct sessions a batch of logs refers to, as wire JSON.
  ///
  /// A missing record is not an error worth failing the upload over — the logs
  /// still carry their session id, so the dashboard has a row either way, just
  /// without the device on it.
  Future<List<Map<String, dynamic>>> _sessionsFor(
      List<Map<String, dynamic>> logs) async {
    final ids = <String>{};
    for (final entry in logs) {
      final id = entry['session_id'];
      if (id is String && id.isNotEmpty) ids.add(id);
    }
    if (ids.isEmpty) return const [];

    // Keep the current launch's record current: this is the only place
    // last_seen_at moves, and it is what makes "live 2m ago" mean anything.
    await CodeScout.instance.touchSession();

    final sessions =
        await LogPersistenceService.i.getSessionsByIds(ids.toList());
    return sessions.map((s) => s.toJson()).toList();
  }

  Future<void> _uploadTarGz(
      String baseURL, File file, Map<String, String> headers) async {
    final uri = Uri.parse('${baseURL}api/logs/dump');
    final fileBytes = await file.readAsBytes();
    final boundary =
        '----CodeScout${DateTime.now().millisecondsSinceEpoch}${Random().nextInt(99999)}';

    // Build multipart body
    final bodyParts = <List<int>>[];
    bodyParts.add(utf8.encode('--$boundary\r\n'));
    bodyParts.add(utf8.encode(
        'Content-Disposition: form-data; name="file"; filename="data.tar.gz"\r\n'));
    bodyParts.add(utf8.encode('Content-Type: application/gzip\r\n\r\n'));
    bodyParts.add(fileBytes);
    bodyParts.add(utf8.encode('\r\n--$boundary--\r\n'));

    final client = HttpClient();
    // Bounds the connect phase on its own. A network that accepts the SYN and
    // then goes quiet — a captive portal, a draining load balancer — would
    // otherwise sit here with no deadline of its own at all.
    client.connectionTimeout = _connectTimeout;
    try {
      final request = await client.postUrl(uri);
      request.headers.set('Content-Type', 'multipart/form-data; boundary=$boundary');
      headers.forEach((k, v) => request.headers.set(k, v));

      for (final part in bodyParts) {
        request.add(part);
      }

      // The deadline belongs in here, not only on the caller's await.
      //
      // `.timeout()` at the call site abandons the *await*; it cannot cancel
      // the request. This function stays suspended on request.close(), so the
      // finally below never runs and the client keeps its socket for as long
      // as the server holds the connection open. The timer then fires again on
      // the next interval and builds another one: one leaked HttpClient and
      // socket per sync cycle, for as long as the server hangs.
      //
      // force: true is the point — a plain close() waits for in-flight
      // requests, which is precisely the thing that is stuck.
      final response = await request.close().timeout(
        _uploadTimeout,
        onTimeout: () {
          client.close(force: true);
          throw TimeoutException('Upload timed out', _uploadTimeout);
        },
      );

      // Read the status while it is still a number. Collapsing everything into
      // one untyped throw is what made a throttle indistinguishable from an
      // outage.
      if (response.statusCode == 429 || response.statusCode == 503) {
        // 503 too: a reverse proxy in front of the instance sends it with
        // Retry-After during maintenance, and the right answer is identical.
        final header = response.headers.value('retry-after');
        await response.drain<void>();
        throw SyncBackoff(parseRetryAfter(header, fallback: _defaultBackoff));
      }
      if (response.statusCode == 413) {
        await response.drain<void>();
        throw const UploadTooLarge();
      }
      if (response.statusCode != 200) {
        final body = await response.transform(utf8.decoder).join();
        throw Exception('Upload failed (${response.statusCode}): $body');
      }
      // Drain the response to free resources
      await response.drain<void>();
    } finally {
      client.close();
    }
  }
}
