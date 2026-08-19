import 'dart:convert';

import 'package:code_scout/code_scout.dart';
import 'package:flutter_test/flutter_test.dart';

/// Redaction has to happen where the value is captured, not where it is
/// serialised.
///
/// Stripping it in toJson() left SQLite and the upload clean, so the dashboard
/// showed `[redacted]` and the configuration looked like it was working. Every
/// reader that touches the entry directly still had the real value: the
/// overlay's detail screen, the console printer, and the copy button whose
/// output goes into bug reports and chat threads.
void main() {
  setUp(() {
    CodeScout.instance.configuration = CodeScoutConfiguration(
      redaction: const RedactionBehavior(bodyKeys: {'password', 'api_key'}),
    );
  });

  tearDown(() {
    CodeScout.instance.configuration = CodeScoutConfiguration();
  });

  test('the entry itself carries no secret', () {
    final entry = LogEntry(
      level: LogLevel.error,
      message: 'login failed',
      sessionID: 's-1',
      metadata: {'user': 'ada', 'password': 'hunter2'},
    );

    expect(entry.metadata!['password'], Redactor.placeholder,
        reason: 'the overlay, the console and the clipboard all read this map');
    expect(entry.metadata!['user'], 'ada',
        reason: 'only the named keys go; the rest is the evidence');
  });

  test('it is gone at depth too', () {
    final entry = LogEntry(
      level: LogLevel.info,
      message: 'call',
      sessionID: 's-1',
      metadata: {
        'request': {'api_key': 'ak_9f21b'},
      },
    );

    expect(jsonEncode(entry.metadata), isNot(contains('ak_9f21b')));
  });

  test('the serialised form is still clean', () {
    final entry = LogEntry(
      level: LogLevel.error,
      message: 'login failed',
      sessionID: 's-1',
      metadata: {'password': 'hunter2'},
    );

    expect(entry.toJson()['metadata'], isNot(contains('hunter2')),
        reason: 'what reaches SQLite and the upload must not regress');
  });

  test('with nothing configured the value is untouched', () {
    CodeScout.instance.configuration = CodeScoutConfiguration();

    final entry = LogEntry(
      level: LogLevel.error,
      message: 'login failed',
      sessionID: 's-1',
      metadata: {'password': 'hunter2'},
    );

    expect(entry.metadata!['password'], 'hunter2',
        reason: 'redaction is opt-in: the token is sometimes the bug');
  });

  test('a network entry is left alone, having been redacted when built', () {
    final entry = LogEntry(
      level: LogLevel.info,
      message: 'Network Request',
      sessionID: 's-1',
      isNetworkCall: true,
      metadata: {'password': 'already handled upstream'},
    );

    expect(entry.metadata!['password'], 'already handled upstream',
        reason: 'network metadata is redacted where it is assembled; doing it '
            'again here would say something untrue about whose job it is');
  });
}
