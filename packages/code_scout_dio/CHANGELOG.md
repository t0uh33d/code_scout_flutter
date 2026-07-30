## 1.0.1

- **Fix:** capture is wrapped defensively — a Code Scout failure can no longer
  fail the underlying request (previously a request made before
  `CodeScout.init()` surfaced as a `DioException` for a request that was never
  attempted). A null `statusCode` no longer throws in `onResponse`.

## 1.0.0

* Initial release.
* Dio interceptor that automatically captures network requests, responses, and errors for Code Scout.
