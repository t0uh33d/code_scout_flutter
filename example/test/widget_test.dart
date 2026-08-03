import 'package:example/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('the example runs with no dashboard configured', (tester) async {
    await tester.pumpWidget(const ExampleApp());
    // init() runs in a post-frame callback and the overlay places itself a
    // turn of the event loop later, so the fake clock has to be advanced past
    // both or the test ends with that timer still pending.
    await tester.pumpAndSettle();

    // Running with no --dart-define is the default and has to keep working:
    // the console printer and the on-device overlay need no server.
    expect(hasDashboard, isFalse);
    expect(
      find.text('On device only. Tap the floating button to read your logs.'),
      findsOneWidget,
    );

    expect(find.text('Levels'), findsOneWidget);
    expect(find.text('Network'), findsOneWidget);
  });
}
