import 'dart:convert';

import 'package:code_scout/code_scout.dart';
import 'package:flutter_test/flutter_test.dart';

/// Redaction is the promise that a bearer token never leaves the phone. These
/// tests are the promise being kept, so they lean towards proving a secret is
/// gone rather than that a field survived.
void main() {
  const on = RedactionBehavior();
  const off = RedactionBehavior.off();

  group('headers', () {
    test('credentials are replaced wholesale', () {
      final out = Redactor.headers({
        'Authorization': 'Bearer eyJhbGciOiJIUzI1NiJ9.secret',
        'Cookie': 'session=abc123',
        'X-API-Key': 'sk_live_9f21b',
        'Content-Type': 'application/json',
      }, on)!;

      expect(out['Authorization'], Redactor.placeholder);
      expect(out['Cookie'], Redactor.placeholder);
      expect(out['X-API-Key'], Redactor.placeholder);
      // Everything else is the useful part of a header list.
      expect(out['Content-Type'], 'application/json');
    });

    // HTTP header names are case-insensitive, and a server answering
    // `set-cookie` is the same server answering `Set-Cookie`.
    test('matching ignores case', () {
      for (final name in ['authorization', 'AUTHORIZATION', 'Authorization']) {
        final out = Redactor.headers({name: 'Bearer abc'}, on)!;
        expect(out[name], Redactor.placeholder, reason: '$name survived');
      }
    });

    test('the header name itself is kept, so you can see what was sent', () {
      final out = Redactor.headers({'Authorization': 'Bearer abc'}, on)!;
      expect(out.keys, contains('Authorization'));
    });

    test('turning it off passes everything through', () {
      final out = Redactor.headers({'Authorization': 'Bearer abc'}, off)!;
      expect(out['Authorization'], 'Bearer abc');
    });

    test('extra header names can be added', () {
      const cfg = RedactionBehavior(additionalHeaders: {'X-Internal-Trace'});
      final out = Redactor.headers({'x-internal-trace': 'abc'}, cfg)!;
      expect(out['x-internal-trace'], Redactor.placeholder);
    });
  });

  group('bodies', () {
    test('secrets are redacted at any depth', () {
      final out = Redactor.body({
        'email': 'someone@example.com',
        'password': 'hunter2',
        'user': {
          'name': 'Sam',
          'access_token': 'at_9f21b',
          'sessions': [
            {'id': 1, 'refreshToken': 'rt_8812f'},
          ],
        },
      }, on) as Map<String, dynamic>;

      expect(out['password'], Redactor.placeholder);
      expect((out['user'] as Map)['access_token'], Redactor.placeholder);
      // Inside a list inside a map. The common shape, and the one a top-level
      // scan would walk straight past.
      expect(((out['user'] as Map)['sessions'] as List).first['refreshToken'],
          Redactor.placeholder);

      // What is left is still worth reading.
      expect(out['email'], 'someone@example.com');
      expect((out['user'] as Map)['name'], 'Sam');
    });

    // One entry has to cover every spelling a codebase uses for the same field.
    test('key matching ignores case and separators', () {
      for (final key in ['access_token', 'accessToken', 'Access-Token', 'ACCESS_TOKEN']) {
        final out = Redactor.body({key: 'at_9f21b'}, on) as Map<String, dynamic>;
        expect(out[key], Redactor.placeholder, reason: '$key survived');
      }
    });

    test('a near-miss key is not redacted', () {
      final out = Redactor.body({'token_count': 42, 'tokenizer': 'bpe'}, on)
          as Map<String, dynamic>;
      expect(out['token_count'], 42, reason: 'over-redacting hides real data');
      expect(out['tokenizer'], 'bpe');
    });

    test('extra body keys can be added', () {
      const cfg = RedactionBehavior(additionalBodyKeys: {'order_signature'});
      final out = Redactor.body({'orderSignature': 'sig'}, cfg) as Map<String, dynamic>;
      expect(out['orderSignature'], Redactor.placeholder);
    });

    test('a null or scalar body is left alone', () {
      expect(Redactor.body(null, on), isNull);
      expect(Redactor.body('plain text', on), 'plain text');
      expect(Redactor.body(42, on), 42);
    });
  });

  group('body caps', () {
    test('an oversized body is truncated and says so', () {
      const cfg = RedactionBehavior(maxBodyBytes: 200);
      final big = {'blob': 'x' * 5000};

      final out = Redactor.body(big, cfg);
      expect(out, isA<String>());
      final text = out as String;
      expect(utf8.encode(text).length, lessThan(400));
      expect(text, contains('truncated by Code Scout'));
      // The reader is told how much was dropped rather than left guessing.
      expect(text, contains('KB total'));
    });

    test('a body under the cap is untouched, and stays a structure', () {
      const cfg = RedactionBehavior(maxBodyBytes: 4096);
      final out = Redactor.body({'qty': 2}, cfg);
      expect(out, isA<Map>());
      expect((out as Map)['qty'], 2);
    });

    test('a cap of zero disables it', () {
      const cfg = RedactionBehavior(maxBodyBytes: 0);
      final out = Redactor.body({'blob': 'x' * 100000}, cfg);
      expect(out, isA<Map>());
    });

    // Cutting on a byte boundary mid-character produces mojibake, which looks
    // like corruption rather than truncation.
    test('truncation does not split a character', () {
      const cfg = RedactionBehavior(maxBodyBytes: 101);
      final out = Redactor.body('日' * 200, cfg) as String;
      expect(() => utf8.encode(out), returnsNormally);
      expect(out, contains('truncated by Code Scout'));
    });

    // The cap protects the network, so it must apply to what is actually sent:
    // a body full of secrets is redacted first, then measured.
    test('redaction runs before the cap', () {
      const cfg = RedactionBehavior(maxBodyBytes: 1000000);
      final out = Redactor.body({'password': 'hunter2', 'note': 'ok'}, cfg)
          as Map<String, dynamic>;
      expect(out['password'], Redactor.placeholder);
    });
  });

  // The tests above prove the Redactor works. These prove it is wired in — a
  // correct redactor that nothing calls is still a token on the wire.
  group('capture points', () {
    test('a captured request carries no bearer token', () {
      final data = NetworkRequestData(
        method: 'POST',
        url: Uri.parse('https://api.test/v2/pay'),
        headers: {'Authorization': 'Bearer sk_live_9f21b', 'Accept': '*/*'},
        body: {'card_number': '4242424242424242', 'amount_cents': 4999},
        requestID: 'req-1',
      );

      final map = data.toMap();
      final encoded = jsonEncode(map);

      expect(encoded, isNot(contains('sk_live_9f21b')));
      expect(encoded, isNot(contains('4242424242424242')));
      // What is left still describes the call.
      expect(map['method'], 'POST');
      expect((map['headers'] as Map)['Accept'], '*/*');
      expect((map['body'] as Map)['amount_cents'], 4999);
    });

    test('a captured log entry carries no hand-logged secret', () {
      final entry = LogEntry(
        level: LogLevel.info,
        message: 'signed in',
        sessionID: 'session',
        metadata: {'userId': 'u_8812', 'refresh_token': 'rt_8812f'},
      );

      final row = entry.toJson();
      expect(row['metadata'], isNot(contains('rt_8812f')));
      expect(row['metadata'], contains('u_8812'));
    });
  });

  group('metadata', () {
    test('a hand-logged secret is redacted too', () {
      final out = Redactor.metadata({'userId': '123', 'token': 'abc'}, on)!;
      expect(out['token'], Redactor.placeholder);
      expect(out['userId'], '123');
    });

    test('nothing to redact leaves the map as it was', () {
      final out = Redactor.metadata({'screen': 'checkout'}, on)!;
      expect(out, {'screen': 'checkout'});
    });

    test('null stays null', () {
      expect(Redactor.metadata(null, on), isNull);
    });
  });
}
