import 'package:code_scout/src/csx_interface/live_pane.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The pairing panel is where somebody types a code read aloud across a desk,
/// on a phone, one-handed. Everything here is about that being forgiving.
void main() {
  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: LivePane())),
    );
  }

  testWidgets('it explains where the code comes from', (tester) async {
    await pump(tester);

    expect(find.text('Start live session'), findsOneWidget);
    // Someone holding the phone has not seen the dashboard, so the panel has
    // to say where the code appears rather than assuming they know.
    expect(find.textContaining('Live devices'), findsOneWidget);
    expect(find.textContaining('New session'), findsOneWidget);
  });

  // Typed rather than pumped: with no server configured the field is
  // deliberately disabled, so driving it through the widget would prove
  // nothing about the alphabet.
  String typed(String input) {
    var value = const TextEditingValue(text: '');
    for (final char in input.split('')) {
      final next = TextEditingValue(
        text: value.text + char,
        selection: TextSelection.collapsed(offset: value.text.length + 1),
      );
      value = pairingCodeFormatters()
          .fold(next, (v, f) => f.formatEditUpdate(value, v));
    }
    return value.text;
  }

  test('lower case is accepted and upper-cased', () {
    expect(typed('4k7q2p'), '4K7Q2P');
  });

  // The characters the server's alphabet leaves out precisely because they are
  // misread off a screen: 0/O, 1/I/L, 5/S, 8/B.
  test('ambiguous characters never land', () {
    expect(typed('01IOSB58L'), '');
  });

  test('the client alphabet matches the server', () {
    // internal/domain/live.go. If these drift the field eats a character the
    // person is trying to type and the code can never complete.
    expect(pairingAlphabet, '234679ACDEFGHJKMNPQRTUVWXYZ');
  });

  // Local-only mode is a first-class way to use Code Scout, so the Live tab has
  // to explain itself rather than looking broken.
  testWidgets('with no server configured it says so instead of failing',
      (tester) async {
    await pump(tester);

    expect(find.textContaining('No server is configured'), findsOneWidget);

    final button = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button.onPressed, isNull,
        reason: 'Connect must be unavailable when there is nothing to connect to');
  });

  testWidgets('the upper-case formatter leaves the rest of the value alone',
      (tester) async {
    final formatter = UpperCaseFormatter();
    const before = TextEditingValue(text: 'ab', selection: TextSelection.collapsed(offset: 2));
    const after = TextEditingValue(text: 'abc', selection: TextSelection.collapsed(offset: 3));

    final result = formatter.formatEditUpdate(before, after);
    expect(result.text, 'ABC');
    // The cursor has to survive, or every keystroke jumps it to the start.
    expect(result.selection.baseOffset, 3);
  });
}
