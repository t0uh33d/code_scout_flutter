import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:code_scout/src/log/log_compressor.dart';
import 'package:flutter_test/flutter_test.dart';

/// The archive is the whole contract with the server: it reads entries by
/// name, so an entry named anything else is silently skipped and the upload
/// looks like it worked.
void main() {
  Archive unpack(List<int> bytes) {
    return TarDecoder().decodeBytes(GZipDecoder().decodeBytes(bytes));
  }

  Object? entry(Archive archive, String name) {
    for (final file in archive.files) {
      if (file.name == name) {
        return jsonDecode(utf8.decode(file.content as List<int>));
      }
    }
    return null;
  }

  final logs = [
    {'id': 'log-1', 'session_id': 's-1', 'level': 'error', 'message': 'boom'},
  ];
  final sessions = [
    {'id': 's-1', 'device_model': 'Pixel 7', 'user_id': 'u_8812'},
  ];

  test('logs and sessions ride in their own named entries', () {
    final archive = unpack(LogCompressor.archiveBytes(logs, sessions));

    expect(archive.files.map((f) => f.name).toList(), ['data.json', 'sessions.json']);
    expect(entry(archive, 'data.json'), logs);
    expect(entry(archive, 'sessions.json'), sessions);
  });

  // What every already-published version of this package sends, and what a
  // batch of logs with no session records still has to look like.
  test('no sessions means no second entry, not an empty one', () {
    final archive = unpack(LogCompressor.archiveBytes(logs, const []));

    expect(archive.files.map((f) => f.name).toList(), ['data.json']);
    expect(entry(archive, 'sessions.json'), isNull);
  });

  test('the archive survives a payload with unicode in it', () {
    final noisy = [
      {'id': 'log-2', 'message': 'café — 東京 — 🎯'},
    ];
    final archive = unpack(LogCompressor.archiveBytes(noisy, const []));

    // The byte length has to be the encoded length, not the string length, or
    // the entry is truncated mid-character and the server cannot parse it.
    expect(entry(archive, 'data.json'), noisy);
  });
}
