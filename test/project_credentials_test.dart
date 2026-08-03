import 'package:code_scout/code_scout.dart';
import 'package:flutter_test/flutter_test.dart';

/// The link is the one setting where a typo used to cost an hour. Nothing
/// downstream complains: the sync worker just never starts, and the only
/// symptom is a dashboard that stays empty.
void main() {
  ProjectCredentials creds(String link) => ProjectCredentials(
        link: link,
        projectID: 'a-project',
        projectSecret: 'a-secret',
      );

  test('a missing scheme is rejected where the mistake is', () {
    // The regression. Dart parses this as scheme "localhost" with an empty
    // host, so it satisfies Uri.isAbsolute and used to be accepted.
    expect(() => creds('localhost:24275/'), throwsArgumentError);
  });

  test('a scheme nothing can open is rejected', () {
    expect(() => creds('ftp://logs.example.com/'), throwsArgumentError);
    expect(() => creds('ws://logs.example.com/'), throwsArgumentError);
  });

  test('http and https with a host are accepted', () {
    expect(creds('http://localhost:24275/').link, 'http://localhost:24275/');
    expect(creds('https://logs.example.com/').link, 'https://logs.example.com/');
    // The Android emulator's route back to the host machine.
    expect(creds('http://10.0.2.2:24275/').link, 'http://10.0.2.2:24275/');
  });

  test('the trailing slash is still required', () {
    // Every path is built as '${link}api/...', so without it the request goes
    // to /apiapi/validate.
    expect(() => creds('http://localhost:24275'), throwsArgumentError);
  });

  test('an empty id or secret is still rejected', () {
    expect(
      () => ProjectCredentials(
          link: 'http://localhost:24275/', projectID: '', projectSecret: 'x'),
      throwsArgumentError,
    );
  });
}
