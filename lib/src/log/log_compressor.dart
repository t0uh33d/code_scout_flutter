import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

class LogCompressor {
  /// Packs a batch into the tar.gz the server ingests.
  ///
  /// Two entries, read by name at the other end: `data.json` is the logs and
  /// `sessions.json` is the launches they belong to. Sessions are omitted
  /// entirely when there are none, which is also what every already-published
  /// version of this package sends.
  static Future<File> compress(
    List<Map<String, dynamic>> logs, [
    List<Map<String, dynamic>> sessions = const [],
  ]) async {
    final Uint8List gzipped = await compute(
      _compressInIsolate,
      {'logs': logs, 'sessions': sessions},
    );
    final dir = await getTemporaryDirectory();
    if (!dir.existsSync()) {
      await dir.create(recursive: true);
    }
    final file = File(p.join(
        dir.path, 'cs_sync_${DateTime.now().millisecondsSinceEpoch}.tar.gz'));
    await file.writeAsBytes(gzipped);
    return file;
  }

  static Uint8List _compressInIsolate(Map<String, dynamic> payload) {
    return archiveBytes(
      (payload['logs'] as List).cast<Map<String, dynamic>>(),
      (payload['sessions'] as List).cast<Map<String, dynamic>>(),
    );
  }

  /// The archive itself, separated from the file it gets written to so the
  /// wire format can be asserted on without a temp directory or an isolate.
  /// This shape is the contract with the server, so it is worth pinning.
  static Uint8List archiveBytes(
    List<Map<String, dynamic>> logs,
    List<Map<String, dynamic>> sessions,
  ) {
    final archive = Archive();
    archive.addFile(_entry('data.json', logs));
    if (sessions.isNotEmpty) {
      archive.addFile(_entry('sessions.json', sessions));
    }

    final tarData = TarEncoder().encode(archive);
    return Uint8List.fromList(GZipEncoder().encode(tarData));
  }

  static ArchiveFile _entry(String name, Object? contents) {
    final bytes = utf8.encode(jsonEncode(contents));
    return ArchiveFile(name, bytes.length, bytes);
  }
}
