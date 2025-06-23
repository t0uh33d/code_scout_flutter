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
        syncBehaviour.syncInterval,
        (timer) =>
            _sync(syncBehaviour, timer, config.projectCredentials!.link));
  }

  void _sync(LogSyncBehavior syncBehaviour, Timer timer, String baseUrl) async {
    try {
      List<Map<String, dynamic>>? logs = await LogPersistenceService.i
          .getLogEntries(limit: syncBehaviour.maxBatchSize);

      if (logs == null || logs.isEmpty) {
        print(
          'LogSyncWorker: No logs to sync.',
        );
        return;
      }

      print(logs);

      for (int i = 0; i < logs.length; i++) {
        var x = jsonEncode(logs[i]);

        print(x);
      }

      File file = await LogCompressor.compress(logs);

      // Upload logs
      await _uploadTarGz(baseUrl, file);
      print(
        'LogSyncWorker: Logs uploaded successfully.',
      );

      await file.delete();
      print(
        'LogSyncWorker: Temporary log file deleted.',
      );

      LogPersistenceService.i.deleteLogEntries(
        logs.map((log) => log['id'] as String).toList(),
      );
      print(
        'LogSyncWorker: Logs deleted after successful upload.',
      );
    } catch (e, _) {
      print(
        'LogSyncWorker: Error during log sync.',
      );
    }
  }

  Future<void> _uploadTarGz(String baseURL, File file) async {
    final uri = Uri.parse('${baseURL}api/logs/dump');
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
