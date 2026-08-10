import 'package:code_scout/code_scout.dart';
import 'package:code_scout/src/const/global_vars.dart';
import 'package:code_scout/src/csx_interface/log_buffer.dart';
import 'package:code_scout/src/csx_interface/overlay_button.dart';
import 'package:code_scout/src/utils/draggable_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The floating button is the only Code Scout pixel on screen while somebody is
/// using the app, so it has to say something and it has to stay reachable.
void main() {
  setUp(LogBuffer.i.clear);
  tearDown(LogBuffer.i.clear);

  const size = GlobalVars.buttonSize;
  const key = Key('fab');

  Future<void> pumpButton(
    WidgetTester tester, {
    EdgeInsets safeArea = EdgeInsets.zero,
    VoidCallback? onTap,
  }) async {
    // Derived from the ambient MediaQuery rather than built once, so a change
    // to the view actually reaches the widget. Hardcoding the size here made
    // the rotation test pass against a value that never moved.
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(padding: safeArea),
          child: Stack(
            children: [
              DraggableFloatingWindow(
                key: key,
                size: size,
                onTap: onTap ?? () {},
                child: Container(width: size, height: size, color: Colors.red),
              ),
            ],
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  Rect fabRect(WidgetTester tester) => tester.getRect(find.byKey(key));

  Size screen(WidgetTester tester) => tester.view.physicalSize / tester.view.devicePixelRatio;

  group('bounds', () {
    testWidgets('starts bottom right, not over the back button', (tester) async {
      await pumpButton(tester);
      final rect = fabRect(tester);
      final view = screen(tester);

      expect(rect.left, greaterThan(view.width / 2), reason: 'right half');
      expect(rect.top, greaterThan(view.height / 2), reason: 'bottom half');
    });

    // The clamp used to be against half the button's size, so 26px could hang
    // off any edge and be left there.
    testWidgets('dragging hard right leaves the whole button on screen', (tester) async {
      await pumpButton(tester);
      final view = screen(tester);

      await tester.drag(find.byKey(key), const Offset(4000, 0));
      await tester.pumpAndSettle();

      final rect = fabRect(tester);
      expect(rect.right, lessThanOrEqualTo(view.width),
          reason: 'the whole button has to stay on screen, not half of it');
      expect(rect.width, size, reason: 'nothing was clipped away instead');
    });

    testWidgets('dragging hard left, up and down all stay on screen', (tester) async {
      await pumpButton(tester);
      final view = screen(tester);

      for (final push in [
        const Offset(-4000, 0),
        const Offset(0, -4000),
        const Offset(0, 4000),
        const Offset(4000, 4000),
      ]) {
        await tester.drag(find.byKey(key), push);
        await tester.pumpAndSettle();
        final rect = fabRect(tester);
        expect(rect.left, greaterThanOrEqualTo(0));
        expect(rect.top, greaterThanOrEqualTo(0));
        expect(rect.right, lessThanOrEqualTo(view.width));
        expect(rect.bottom, lessThanOrEqualTo(view.height));
      }
    });

    // The safe area used to be respected top and bottom only.
    testWidgets('the safe area is respected on all four sides', (tester) async {
      const safe = EdgeInsets.fromLTRB(40, 60, 40, 30);
      await pumpButton(tester, safeArea: safe);
      final view = screen(tester);

      await tester.drag(find.byKey(key), const Offset(4000, 4000));
      await tester.pumpAndSettle();
      var rect = fabRect(tester);
      expect(rect.right, lessThanOrEqualTo(view.width - safe.right));
      expect(rect.bottom, lessThanOrEqualTo(view.height - safe.bottom));

      await tester.drag(find.byKey(key), const Offset(-4000, -4000));
      await tester.pumpAndSettle();
      rect = fabRect(tester);
      expect(rect.left, greaterThanOrEqualTo(safe.left));
      expect(rect.top, greaterThanOrEqualTo(safe.top));
    });

    // The position was stored once and never recomputed, so rotating to
    // landscape left the button off the screen with no way back.
    testWidgets('a screen that shrinks pulls the button back with it', (tester) async {
      await pumpButton(tester);

      // Park it at the bottom right of the tall screen.
      await tester.drag(find.byKey(key), const Offset(4000, 4000));
      await tester.pumpAndSettle();
      expect(fabRect(tester).bottom, greaterThan(400));

      // Now rotate: same width, much shorter.
      addTearDown(tester.view.resetPhysicalSize);
      tester.view.physicalSize = Size(
        tester.view.physicalSize.width,
        300 * tester.view.devicePixelRatio,
      );
      await tester.pumpAndSettle();

      expect(fabRect(tester).bottom, lessThanOrEqualTo(300),
          reason: 'the button has to come back onto the shorter screen');
    });

    // onPanStart used to recentre the button under the finger, so grabbing it
    // by a corner threw it half its own width the instant the drag began.
    //
    // The invariant that catches it: the button never travels further than the
    // finger did. Recentring adds the grab offset on top of the drag, so it
    // always overshoots. Asserting an exact landing spot instead would be
    // asserting kPanSlop, which is the framework's number and not ours.
    testWidgets('the button never moves further than your finger', (tester) async {
      await pumpButton(tester);
      final before = fabRect(tester);

      // Grabbed by the corner, which is the worst case for recentring.
      final grab = before.topLeft + const Offset(3, 3);
      const travel = Offset(-90, -90);

      // Three moves rather than one: the pan recogniser has to clear kPanSlop
      // and win the arena against the tap recogniser on the same detector
      // before it reports anything, and it does that on a later event.
      final gesture = await tester.startGesture(grab);
      for (var i = 0; i < 3; i++) {
        await gesture.moveBy(travel / 3);
        await tester.pump();
      }
      await gesture.up();
      await tester.pumpAndSettle();

      final after = fabRect(tester);
      expect((before.left - after.left).abs(), lessThanOrEqualTo(travel.dx.abs() + 1));
      expect((before.top - after.top).abs(), lessThanOrEqualTo(travel.dy.abs() + 1));
      // And it did move, so the bound above is not passing by doing nothing.
      expect(after.left, lessThan(before.left));
    });
  });

  group('what it says', () {
    Future<void> pumpFab(WidgetTester tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: Center(child: OverlayButton(size: size))),
      ));
      await tester.pumpAndSettle();
    }

    void addError(int n) {
      for (var i = 0; i < n; i++) {
        LogBuffer.i.add(LogEntry(level: LogLevel.error, message: 'boom $i', sessionID: 's'));
      }
    }

    testWidgets('no badge when nothing has gone wrong', (tester) async {
      LogBuffer.i.add(LogEntry(level: LogLevel.info, message: 'fine', sessionID: 's'));
      await pumpFab(tester);

      expect(find.textContaining(RegExp(r'^\d')), findsNothing,
          reason: 'an info log is not a reason to draw a badge');
    });

    testWidgets('the badge counts errors and fatals only', (tester) async {
      addError(2);
      for (var i = 0; i < 5; i++) {
        LogBuffer.i.add(LogEntry(level: LogLevel.info, message: 'noise $i', sessionID: 's'));
      }
      LogBuffer.i.add(LogEntry(level: LogLevel.fatal, message: 'worse', sessionID: 's'));

      await pumpFab(tester);

      // A badge that counted every log would say 8.
      expect(find.text('3'), findsOneWidget);
    });

    testWidgets('the badge stops being a number past three digits', (tester) async {
      addError(120);
      await pumpFab(tester);
      expect(find.text('99+'), findsOneWidget);
    });

    testWidgets('looking at the errors clears the badge', (tester) async {
      addError(3);
      await pumpFab(tester);
      expect(find.text('3'), findsOneWidget);

      LogBuffer.i.markErrorsSeen();
      await tester.pumpAndSettle();
      expect(find.text('3'), findsNothing);
    });
  });
}
