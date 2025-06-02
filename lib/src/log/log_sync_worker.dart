import 'dart:async';
import 'dart:convert';
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

  void start() {
    CodeScoutConfiguration config = CodeScout.instance.configuration;

    if (config.projectCredentials == null) {
      print(
        'LogSyncWorker: Project credentials are not configured.',
      );
      return;
    }

    if (config.sync == null) {
      print(
        'LogSyncWorker: Sync behavior is not configured.',
      );
      return;
    }

    LogSyncBehavior syncBehaviour = config.sync!;

    _syncTimer = Timer.periodic(
        syncBehaviour.syncInterval, (timer) => _sync(syncBehaviour, timer));
  }

  void _sync(LogSyncBehavior syncBehaviour, Timer timer) async {
    try {
      List<Map<String, dynamic>>? logs = await LogPersistenceService.i
          .getLogEntries(limit: syncBehaviour.maxBatchSize);

      if (logs == null || logs.isEmpty) {
        print(
          'LogSyncWorker: No logs to sync.',
        );
        return;
      }

      Future<File> file = LogCompressor.compress(logs);

      // Upload logs
      await _uploadTarGz(await file);

      LogPersistenceService.i.deleteLogEntries(
        logs.map((log) => log['id'] as String).toList(),
      );

      print(
        'LogSyncWorker: Logs uploaded successfully.',
      );
    } catch (e, _) {
      print(
        'LogSyncWorker: Error during log sync.',
      );
    }
  }

  Future<void> _uploadTarGz(File file) async {
    final uri = Uri.parse('http://localhost:24275/api/logs/dump');
    final request = http.MultipartRequest('POST', uri);
    request.files.add(await http.MultipartFile.fromPath('file', file.path));
    request.headers.addAll(
        CodeScout.instance.configuration.projectCredentials?.authHeaders ?? {});

    final response = await request.send();

    if (response.statusCode != 200) {
      throw Exception(
          'LogSyncWorker: Failed to upload logs. Status code: ${response.statusCode}');
    }
  }
}
