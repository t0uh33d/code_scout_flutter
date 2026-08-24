## 1.0.3

### Changed

- **The name reads CodeScout, one word.** The description published with 1.0.2
  still said "Code Scout", because the rename landed after that version went out
  and pub.dev only takes a new listing with a new version.
- **The readme says what the rest of CodeScout does.** It used to end at the
  licence, so somebody who installed this for package:http capture had no way to learn
  that live device streaming, the database browser and the agent tools exist.

No code changed in this release.

## 1.0.2

### Changed

- **The declared minimum is now Flutter 3.38 (Dart 3.10), where it used to say Flutter 3.0.**
  That old number was never true, so pub.dev advertised compatibility with releases that could
  not resolve the package. Nothing about the code changed.

## 1.0.1

- **Fix:** `CodeScoutHttpClient` returned an already-drained response stream,
  breaking every request made through it (`Stream has already been listened to`).
  The body is now buffered and an equivalent response is returned to the caller.
- **Fix:** capture is wrapped defensively. A CodeScout failure can no longer
  fail the underlying HTTP request (e.g. when used before `CodeScout.init()`).

## 1.0.0

* Initial release.
* HTTP client wrapper that automatically captures network requests, responses, and errors for CodeScout.
