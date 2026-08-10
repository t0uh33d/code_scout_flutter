# code_scout_dio

[![pub.dev](https://img.shields.io/pub/v/code_scout_dio.svg)](https://pub.dev/packages/code_scout_dio)

Captures every HTTP call your Dio client makes and shows it to you, either on the phone itself or
on a [Code Scout](https://codescout.tech) dashboard you run.

This is the Dio half of Code Scout. The core package,
[`code_scout`](https://pub.dev/packages/code_scout), does the logging and has no HTTP dependency
of its own, which is why network capture lives out here. Installing Code Scout never drags Dio
into an app that does not already use it.

## Getting started

```bash
flutter pub add code_scout_dio
```

Then attach the interceptor to the client you already have:

```dart
import 'package:dio/dio.dart';
import 'package:code_scout_dio/code_scout_dio.dart';

final dio = Dio();
dio.interceptors.add(CodeScoutDioInterceptor());
```

That is the whole setup. Code Scout itself still needs `init()` called somewhere, which is
covered in the [core package's readme](https://pub.dev/packages/code_scout).

## What you get

Every call writes one log when the request goes out and a second when it comes back. The two
share a request id, so the in-app panel and the dashboard show them as one row rather than two
unrelated entries, with the status, the duration, and the headers and bodies on both sides.

You can read all of this on the device with no server configured at all. Tap the floating button
and open the Network tab.

## Two things worth knowing

Dio treats a 4xx or 5xx as an error rather than a response, because that is what its default
`validateStatus` does. Those calls therefore arrive through the error path and are logged at
error level, which is usually what you want, but it does mean a plain 404 shows up under Errors
as well as under Network.

Nothing is redacted unless you ask for it. Out of the box the `Authorization` header and every
request body are recorded as sent, which is deliberate, since the token is sometimes the bug you
are chasing. Before you point this at real users, set `RedactionBehavior.recommended()` in your
Code Scout configuration.

## Checking it is working

If the Network tab stays empty, open the panel and tap the info icon. The interceptor announces
itself to Code Scout the moment you construct it, so the Info screen can tell you whether it is
genuinely missing or simply installed and has not seen a call yet.

## License

MIT. See [LICENSE](LICENSE).
