import 'package:code_scout/code_scout.dart';
import 'package:code_scout/src/csx_interface/log_buffer.dart';
import 'package:code_scout/src/csx_interface/menu.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The overlay is the only part of Code Scout someone uses without a server,
/// so its filters have to work on their own.
void main() {
  setUp(LogBuffer.i.clear);
  tearDown(LogBuffer.i.clear);

  void add(String message, {LogLevel level = LogLevel.info, Set<String> tags = const {}}) {
    LogBuffer.i.add(LogEntry(
      level: level,
      message: message,
      sessionID: 'session',
      tags: tags,
    ));
  }

  Future<void> pumpSheet(WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: CSxInterface()),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('logs list newest first', (tester) async {
    add('older');
    add('newer');

    await pumpSheet(tester);

    expect(find.text('older'), findsOneWidget);
    expect(find.text('newer'), findsOneWidget);

    final newer = tester.getTopLeft(find.text('newer')).dy;
    final older = tester.getTopLeft(find.text('older')).dy;
    expect(newer, lessThan(older), reason: 'the newest log should be at the top');
  });

  testWidgets('a tag chip narrows, then hides, then clears', (tester) async {
    add('checkout log', tags: {'checkout'});
    add('heartbeat log', tags: {'heartbeat'});
    add('untagged log');

    await pumpSheet(tester);
    expect(find.text('checkout log'), findsOneWidget);
    expect(find.text('heartbeat log'), findsOneWidget);

    // First tap: only this tag.
    await tester.tap(find.text('checkout'));
    await tester.pumpAndSettle();
    expect(find.text('checkout log'), findsOneWidget);
    expect(find.text('heartbeat log'), findsNothing);
    expect(find.text('untagged log'), findsNothing);

    // Second tap: hide this tag. The untagged log comes back — it does not
    // carry the tag, so excluding it must not take the log with it.
    await tester.tap(find.text('checkout'));
    await tester.pumpAndSettle();
    expect(find.text('checkout log'), findsNothing);
    expect(find.text('heartbeat log'), findsOneWidget);
    expect(find.text('untagged log'), findsOneWidget);

    // Third tap: back to neutral.
    await tester.tap(find.text('checkout'));
    await tester.pumpAndSettle();
    expect(find.text('checkout log'), findsOneWidget);
    expect(find.text('heartbeat log'), findsOneWidget);
    expect(find.text('untagged log'), findsOneWidget);
  });

  testWidgets('the level filter hides everything quieter', (tester) async {
    add('a debug line', level: LogLevel.debug);
    add('an info line');
    add('a warning', level: LogLevel.warning);
    add('it broke', level: LogLevel.error);

    await pumpSheet(tester);
    expect(find.text('a debug line'), findsOneWidget);

    await tester.tap(find.text('warning'));
    await tester.pumpAndSettle();

    expect(find.text('a debug line'), findsNothing);
    expect(find.text('an info line'), findsNothing);
    expect(find.text('a warning'), findsOneWidget);
    // A level filter is a floor, not an equals: an error is louder than a
    // warning and must not be filtered out by asking for warnings.
    expect(find.text('it broke'), findsOneWidget);
  });

  testWidgets('the network tab shows calls, not phases', (tester) async {
    LogBuffer.i.add(LogEntry(
      level: LogLevel.debug,
      message: 'Network Request',
      sessionID: 'session',
      isNetworkCall: true,
      requestId: 'req-1',
      callPhase: NetworkCallPhase.request,
      metadata: const {'method': 'POST', 'url': 'https://api.test/v2/pay'},
    ));
    LogBuffer.i.add(LogEntry(
      level: LogLevel.debug,
      message: 'Network Response',
      sessionID: 'session',
      isNetworkCall: true,
      requestId: 'req-1',
      callPhase: NetworkCallPhase.response,
      metadata: const {'status_code': 201},
    ));

    await pumpSheet(tester);
    await tester.tap(find.text('Network'));
    await tester.pumpAndSettle();

    // One row for the call, not one per phase.
    expect(find.text('/v2/pay'), findsOneWidget);
    expect(find.text('POST'), findsOneWidget);
    expect(find.text('201'), findsOneWidget);
  });

  testWidgets('the session tab says when nothing is being uploaded', (tester) async {
    await pumpSheet(tester);
    await tester.tap(find.text('Session'));
    await tester.pumpAndSettle();

    // No credentials configured in a test, which is local mode — and the pane
    // has to say so rather than implying logs are going somewhere.
    expect(find.text('local only — no server configured'), findsOneWidget);
    // Identity is opt-in, so an unnamed session says so plainly.
    expect(find.text('anonymous'), findsOneWidget);
  });

  // The sheet is something you tab across constantly while chasing one bug.
  // Sizing it to whichever tab is open means it jumps every time, and the tab
  // row moves out from under your thumb.
  testWidgets('the sheet keeps its height across tabs', (tester) async {
    add('one log');
    await pumpSheet(tester);

    double height() => tester.getSize(find.byType(CSxInterface)).height;
    final onLogs = height();

    for (final tab in ['Network', 'Live', 'Session', 'Logs']) {
      await tester.tap(find.text(tab));
      await tester.pumpAndSettle();
      expect(height(), onLogs, reason: 'the sheet resized on the $tab tab');
    }
  });

  testWidgets('an empty buffer explains itself', (tester) async {
    await pumpSheet(tester);
    expect(find.text('Nothing to show'), findsOneWidget);

    await tester.tap(find.text('Network'));
    await tester.pumpAndSettle();
    expect(find.text('No network calls'), findsOneWidget);
  });
}
