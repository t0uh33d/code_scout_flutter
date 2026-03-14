import 'dart:async';
import 'dart:developer';
import 'dart:io';

import 'package:code_scout/code_scout.dart';
import 'package:code_scout/src/log/log_compressor.dart';
import 'package:code_scout/src/log/log_persistence_service.dart';
import 'package:http/http.dart' as http;

class LogSyncWorker {
  static final LogSyncWorker i = LogSyncWorker._i();

  LogSyncWorker._i();

  factory LogSyncWorker() {
    return i;
  }

  Timer? _syncTimer;
  bool _syncing = false;
  int _consecutiveFailures = 0;
  static const int _maxConsecutiveFailures = 5;
  static const Duration _uploadTimeout = Duration(seconds: 30);

  bool get isRunning => _syncTimer?.isActive ?? false;

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

  Future<void> _sync() async {
    if (_syncing) return;
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

    try {
      logs = await LogPersistenceService.i
          .getLogEntries(limit: syncBehaviour.maxBatchSize);

      if (logs.isEmpty) {
        _syncing = false;
        return;
      }

      logIds = logs.map((l) => l['id'] as String).toList();

      // Mark logs as syncing so concurrent cycles don't pick them up
      await LogPersistenceService.i.markAsSyncing(logIds);

      // Compress
      file = await LogCompressor.compress(logs);

      // Upload with timeout
      await _uploadTarGz(creds.link, file, creds.authHeaders)
          .timeout(_uploadTimeout);

      // Success — delete the logs from DB
      await LogPersistenceService.i.deleteLogEntries(logIds);

      _consecutiveFailures = 0;
    } catch (e, st) {
      log('LogSyncWorker: Sync failed: $e', stackTrace: st);
      _consecutiveFailures++;

      // Roll back sync_status so logs are retried next cycle
      if (logIds.isNotEmpty) {
        try {
          await LogPersistenceService.i.markAsUnsync(logIds);
        } catch (rollbackError) {
          log('LogSyncWorker: Failed to rollback sync status: $rollbackError');
        }
      }

      // Back off after repeated failures
      if (_consecutiveFailures >= _maxConsecutiveFailures) {
        log('LogSyncWorker: Too many consecutive failures ($_consecutiveFailures), stopping sync.');
        stop();
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

  Future<void> _uploadTarGz(
      String baseURL, File file, Map<String, String> headers) async {
    final uri = Uri.parse('${baseURL}api/logs/dump');
    final request = http.MultipartRequest('POST', uri);
    request.files.add(await http.MultipartFile.fromPath('file', file.path));
    request.headers.addAll(headers);

    final response = await request.send();

    if (response.statusCode != 200) {
      final body = await response.stream.bytesToString();
      throw Exception(
        'Upload failed (${response.statusCode}): $body',
      );
    }
  }
}
