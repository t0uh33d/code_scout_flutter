import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

class LogCompressor {
  static Future<File> compress(List<Map<String, dynamic>> logs) async {
    String jsonString = jsonEncode(logs);
    final tarArchive = TarEncoder();
    final archive = Archive();
    archive.addFile(
        ArchiveFile('data.json', jsonString.length, utf8.encode(jsonString)));
    final tarData = tarArchive.encode(archive);
    final gzipped = GZipEncoder().encode(tarData)!;
    final dir = await getTemporaryDirectory();
    final file = File(p.join(dir.path, 'data.tar.gz'));
    await file.writeAsBytes(gzipped);

    print("File saved to: ${file.path}");
    return file;
  }
}
