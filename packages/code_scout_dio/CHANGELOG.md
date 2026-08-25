## 1.0.4

### Fixed

- **The declared dio range was wrong.** It claimed `>=5.0.0`, but the interceptor
  uses `DioException` and `DioExceptionType`, which do not exist before dio 5.2.0.
  Anyone on an earlier 5.x got seven compile errors on install. The lower bound is
  5.2.0 now, found by bisecting: 5.1.2 fails and 5.2.0 passes.

### Added

- An example showing the interceptor wired into an app.

## 1.0.3

### Changed

- **The name reads CodeScout, one word.** The description published with 1.0.2
  still said "Code Scout", because the rename landed after that version went out
  and pub.dev only takes a new listing with a new version.
- **The readme says what the rest of CodeScout does.** It used to end at the
  licence, so somebody who installed this for Dio capture had no way to learn
  that live device streaming, the database browser and the agent tools exist.

No code changed in this release.

## 1.0.2

### Changed

- **The declared minimum is now Flutter 3.38 (Dart 3.10), where it used to say Flutter 3.0.**
  That old number was never true, so pub.dev advertised compatibility with releases that could
  not resolve the package. Nothing about the code changed.

## 1.0.1

- **Fix:** capture is wrapped defensively. A CodeScout failure can no longer
  fail the underlying request (previously a request made before
  `CodeScout.init()` surfaced as a `DioException` for a request that was never
  attempted). A null `statusCode` no longer throws in `onResponse`.

## 1.0.0

* Initial release.
* Dio interceptor that automatically captures network requests, responses, and errors for CodeScout.
