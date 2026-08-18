import 'dart:convert';

import 'package:code_scout/code_scout.dart';
import 'package:flutter_test/flutter_test.dart';

/// Redaction is opt-in. CodeScout is a debugging tool, and the token is
/// sometimes exactly the reason a request is failing — so nothing is hidden
/// unless the app asks for it.
void main() {
  const nothing = RedactionBehavior();

  group('by default nothing is hidden', () {
    test('headers pass through untouched', () {
      final out = Redactor.headers({
        'Authorization': 'Bearer sk_live_9f21b',
        'Cookie': 'session=abc123',
      }, nothing)!;

      expect(out['Authorization'], 'Bearer sk_live_9f21b');
      expect(out['Cookie'], 'session=abc123');
    });

    test('bodies pass through untouched', () {
      final out = Redactor.body({'password': 'hunter2'}, nothing) as Map;
      expect(out['password'], 'hunter2');
    });

    test('metadata passes through untouched', () {
      final out = Redactor.metadata({'token': 'abc'}, nothing)!;
      expect(out['token'], 'abc');
    });

    test('a captured request keeps its token', () {
      final data = NetworkRequestData(
        method: 'POST',
        url: Uri.parse('https://api.test/v2/pay'),
        headers: {'Authorization': 'Bearer sk_live_9f21b'},
        requestID: 'req-1',
      );
      // The point of the tool: you can see what you actually sent.
      expect(jsonEncode(data.toMap()), contains('sk_live_9f21b'));
    });
  });

  group('what you list is what is redacted', () {
    const cfg = RedactionBehavior(
      headers: {'authorization'},
      bodyKeys: {'password'},
    );

    test('a listed header goes, an unlisted one stays', () {
      final out = Redactor.headers({
        'Authorization': 'Bearer abc',
        'Cookie': 'session=abc123',
      }, cfg)!;

      expect(out['Authorization'], Redactor.placeholder);
      // Not listed, so still visible — this is the whole point of opt-in.
      expect(out['Cookie'], 'session=abc123');
    });

    // HTTP header names are case-insensitive, so the config should not have to
    // guess which spelling the client used.
    test('header matching ignores case, both ways', () {
      for (final sent in ['authorization', 'AUTHORIZATION', 'Authorization']) {
        expect(Redactor.headers({sent: 'Bearer abc'}, cfg)![sent],
            Redactor.placeholder,
            reason: '$sent survived');
      }
      const upper = RedactionBehavior(headers: {'Authorization'});
      expect(Redactor.headers({'authorization': 'Bearer abc'}, upper)!['authorization'],
          Redactor.placeholder);
    });

    test('the header name is kept, so you can see what was sent', () {
      expect(Redactor.headers({'Authorization': 'Bearer abc'}, cfg)!.keys,
          contains('Authorization'));
    });

    test('a listed key is redacted at any depth', () {
      final out = Redactor.body({
        'email': 'someone@example.com',
        'user': {
          'password': 'hunter2',
          'sessions': [
            {'id': 1, 'password': 'hunter3'},
          ],
        },
      }, cfg) as Map<String, dynamic>;

      expect((out['user'] as Map)['password'], Redactor.placeholder);
      // Inside a list inside a map — the shape a top-level scan walks past.
      expect(((out['user'] as Map)['sessions'] as List).first['password'],
          Redactor.placeholder);
      expect(out['email'], 'someone@example.com');
    });

    // One entry should cover every spelling a codebase uses for a field.
    test('key matching ignores case and separators', () {
      const tokens = RedactionBehavior(bodyKeys: {'access_token'});
      for (final key in ['access_token', 'accessToken', 'Access-Token', 'ACCESS_TOKEN']) {
        final out = Redactor.body({key: 'at_9f21b'}, tokens) as Map<String, dynamic>;
        expect(out[key], Redactor.placeholder, reason: '$key survived');
      }
    });

    test('a near-miss key is left alone', () {
      const tokens = RedactionBehavior(bodyKeys: {'token'});
      final out = Redactor.body({'token_count': 42, 'tokenizer': 'bpe'}, tokens)
          as Map<String, dynamic>;
      expect(out['token_count'], 42, reason: 'over-redacting hides real data');
      expect(out['tokenizer'], 'bpe');
    });

    test('a null or scalar body is left alone', () {
      expect(Redactor.body(null, cfg), isNull);
      expect(Redactor.body('plain text', cfg), 'plain text');
      expect(Redactor.body(42, cfg), 42);
    });
  });

  group('the common lists are offered, not applied', () {
    test('recommended turns them all on', () {
      final cfg = RedactionBehavior.recommended();
      final out = Redactor.headers({'Authorization': 'Bearer abc'}, cfg)!;
      expect(out['Authorization'], Redactor.placeholder);
      expect(
        (Redactor.body({'refreshToken': 'rt_1'}, cfg) as Map)['refreshToken'],
        Redactor.placeholder,
      );
    });

    test('recommended takes additions', () {
      final cfg = RedactionBehavior.recommended(bodyKeys: {'order_signature'});
      final out = Redactor.body({'orderSignature': 'sig', 'password': 'p'}, cfg) as Map;
      expect(out['orderSignature'], Redactor.placeholder);
      expect(out['password'], Redactor.placeholder);
    });

    // The case the whole decision turned on: keeping the common list while
    // watching the one header you are actually debugging.
    test('a common entry can be dropped to debug it', () {
      final cfg = RedactionBehavior(
        headers: RedactionBehavior.commonHeaders.difference({'authorization'}),
      );
      final out = Redactor.headers({
        'Authorization': 'Bearer abc',
        'Cookie': 'session=abc',
      }, cfg)!;

      expect(out['Authorization'], 'Bearer abc', reason: 'the header being debugged');
      expect(out['Cookie'], Redactor.placeholder);
    });

    test('the common lists are not applied on their own', () {
      // Naming them must not switch them on — only listing them does.
      expect(nothing.headers, isEmpty);
      expect(nothing.bodyKeys, isEmpty);
      expect(nothing.enabled, isFalse);
      expect(RedactionBehavior.commonHeaders, contains('authorization'));
    });
  });

  // Not a privacy setting: a 5 MB response uploaded from a phone is a cost the
  // person holding it pays, whether or not anything in it is secret.
  group('body caps apply regardless', () {
    test('an oversized body is truncated and says so', () {
      const cfg = RedactionBehavior(maxBodyBytes: 200);
      final out = Redactor.body({'blob': 'x' * 5000}, cfg);

      expect(out, isA<String>());
      final text = out as String;
      expect(utf8.encode(text).length, lessThan(400));
      expect(text, contains('truncated by CodeScout'));
      // The note reports the size of the whole body, not the amount removed.
      // Somebody staring at it wants to know what they are missing.
      expect(text, contains('The whole body was'));
      expect(text, contains('KB'));
    });

    test('the cap still applies with nothing redacted', () {
      final out = Redactor.body({'blob': 'x' * 100000}, nothing);
      expect(out, isA<String>(), reason: 'the cap is about size, not secrets');
    });

    test('a body under the cap stays a structure', () {
      final out = Redactor.body({'qty': 2}, nothing);
      expect(out, isA<Map>());
      expect((out as Map)['qty'], 2);
    });

    test('a cap of zero disables it', () {
      const cfg = RedactionBehavior(maxBodyBytes: 0);
      expect(Redactor.body({'blob': 'x' * 100000}, cfg), isA<Map>());
    });

    // Cutting on a byte boundary mid-character produces mojibake, which reads
    // as corruption rather than truncation.
    test('truncation does not split a character', () {
      const cfg = RedactionBehavior(maxBodyBytes: 101);
      final out = Redactor.body('日' * 200, cfg) as String;
      expect(() => utf8.encode(out), returnsNormally);
      expect(out, contains('truncated by CodeScout'));
    });

    test('redaction runs before the cap', () {
      const cfg = RedactionBehavior(bodyKeys: {'password'}, maxBodyBytes: 1000000);
      final out = Redactor.body({'password': 'hunter2', 'note': 'ok'}, cfg) as Map;
      expect(out['password'], Redactor.placeholder);
    });
  });
}
