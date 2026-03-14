import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

class LogCompressor {
  static Future<File> compress(List<Map<String, dynamic>> logs) async {
    final Uint8List gzipped = await compute(_compressInIsolate, logs);
    final dir = await getTemporaryDirectory();
    if (!dir.existsSync()) {
      await dir.create(recursive: true);
    }
    final file = File(p.join(dir.path, 'cs_sync_${DateTime.now().millisecondsSinceEpoch}.tar.gz'));
    await file.writeAsBytes(gzipped);
    return file;
  }

  static Uint8List _compressInIsolate(List<Map<String, dynamic>> logs) {
    final jsonString = jsonEncode(logs);
    final jsonBytes = utf8.encode(jsonString);
    final archive = Archive();
    archive.addFile(ArchiveFile('data.json', jsonBytes.length, jsonBytes));
    final tarData = TarEncoder().encode(archive);
    return Uint8List.fromList(GZipEncoder().encode(tarData));
  }
}
