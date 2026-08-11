## 1.0.1

- **Fix:** `CodeScoutHttpClient` returned an already-drained response stream,
  breaking every request made through it (`Stream has already been listened to`).
  The body is now buffered and an equivalent response is returned to the caller.
- **Fix:** capture is wrapped defensively. A Code Scout failure can no longer
  fail the underlying HTTP request (e.g. when used before `CodeScout.init()`).

## 1.0.0

* Initial release.
* HTTP client wrapper that automatically captures network requests, responses, and errors for Code Scout.
