import 'dart:convert';

import 'package:code_scout/code_scout.dart';
import 'package:flutter_test/flutter_test.dart';

/// The body a `package:http` call actually produces.
///
/// `code_scout_http` reads `request.body`, which is a String, and decodes the
/// response with `utf8.decode`, which is also a String. Dio hands over a
/// decoded Map for a JSON response, which is why this only ever went wrong on
/// one of the two companions and why nobody noticed.
void main() {
  const cfg = RedactionBehavior(bodyKeys: {'password', 'access_token'});

  group('a JSON body that arrives as a string', () {
    test('is redacted, not passed through whole', () {
      final sent = jsonEncode({'email': 'a@b.c', 'password': 'hunter2'});

      final out = Redactor.body(sent, cfg);

      expect(out, isNot(contains('hunter2')),
          reason: 'the password reached SQLite and the upload in cleartext');
      expect(out.toString(), contains(Redactor.placeholder));
      expect(out.toString(), contains('a@b.c'),
          reason: 'only the named keys go, everything else is the evidence');
    });

    test('is redacted at depth, the same as a map body', () {
      final sent = jsonEncode({
        'user': {
          'name': 'ada',
          'credentials': {'password': 'hunter2'},
        },
      });

      final out = Redactor.body(sent, cfg);

      expect(out, isNot(contains('hunter2')));
      expect(out.toString(), contains('ada'));
    });

    test('is redacted inside a list', () {
      final sent = jsonEncode([
        {'access_token': 'at_9f21b'},
      ]);

      expect(Redactor.body(sent, cfg), isNot(contains('at_9f21b')));
    });

    test('comes back as a string, so the shape on the wire is unchanged', () {
      final sent = jsonEncode({'password': 'hunter2'});

      expect(Redactor.body(sent, cfg), isA<String>(),
          reason: 'a string body must stay a string, or the dashboard renders '
              'an http call differently from a dio one');
    });

    test('survives a round trip as JSON', () {
      final sent = jsonEncode({'email': 'a@b.c', 'password': 'hunter2'});

      final decoded = jsonDecode(Redactor.body(sent, cfg)! as String);

      expect(decoded, isA<Map>());
      expect((decoded as Map)['password'], Redactor.placeholder);
      expect(decoded['email'], 'a@b.c');
    });
  });

  group('a string that is not JSON', () {
    test('is left exactly as it is', () {
      // There are no keys to match, and mangling a log line or an HTML error
      // page would lose the evidence for nothing.
      expect(Redactor.body('plain text', cfg), 'plain text');
      expect(Redactor.body('<html>nope</html>', cfg), '<html>nope</html>');
      expect(Redactor.body('', cfg), '');
    });

    test('that merely starts like JSON is still left alone', () {
      expect(Redactor.body('{not json at all', cfg), '{not json at all');
    });

    test('holding a bare JSON scalar is left alone', () {
      // jsonDecode("42") succeeds, but there is nothing keyed to redact.
      expect(Redactor.body('42', cfg), '42');
      expect(Redactor.body('"just a string"', cfg), '"just a string"');
    });
  });

  test('with nothing configured a string body is untouched', () {
    const nothing = RedactionBehavior();
    final sent = jsonEncode({'password': 'hunter2'});

    expect(Redactor.body(sent, nothing), sent,
        reason: 'redaction is opt-in; the token is sometimes the bug');
  });
}
