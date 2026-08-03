# Code Scout example

A small app that exercises the SDK: every log level, tags and metadata, errors
with real stack traces, redaction, identity, and network capture through both
companion packages.

## Run it

```bash
flutter run
```

No configuration, and nothing is uploaded. Logs go to the console and to the
floating button, which opens an on-device viewer with Logs, Network, Live and
Session tabs. This is a real way to use Code Scout, not a limited trial of it.

## Point it at a dashboard

Create a project in your Code Scout instance, copy the id and secret from the
last step of the wizard, and pass them in:

```bash
flutter run \
  --dart-define=CS_URL=http://localhost:24275/ \
  --dart-define=CS_PROJECT_ID=your-project-id \
  --dart-define=CS_PROJECT_SECRET=your-project-secret
```

Passed in rather than written down, so nothing here has to hold a secret. The
bar under the app title tells you which mode you are in.

Logs upload every 15 seconds. **Upload now** on the Logs tab sends the batch
immediately and waits for it, which saves waiting when you are checking that
the connection works.

## What each screen shows

**Logs.** The six level shorthands. A log carrying tags and metadata. An error
thrown and caught, so the stack trace is genuine and the dashboard can parse
it frame by frame. A log whose `authorization` and `password` values never
reach disk, because `RedactionBehavior.recommended()` strips them at capture.
`setUser`, which attributes the whole launch and not just what follows it.

**Network.** The same requests through Dio and through `http`. Neither package
asks you to change the call sites: `CodeScoutDioInterceptor` goes on the Dio you
already have, and `CodeScoutHttpClient` wraps the client you already have. Each
call is captured in three phases correlated by one request id, and the dashboard
pairs them back into one row. The last button calls a host that does not resolve,
so you can see the error phase next to the successes.

## Testing an app that uses Code Scout

`test/widget_test.dart` boots the whole example under `flutter_test`. Two things
are worth copying:

- `pumpAndSettle()` rather than a single `pump()`. `init()` runs in a post-frame
  callback and the overlay places itself a turn of the event loop later, so a
  single pump leaves a timer pending and the test fails on that instead of on
  anything real.
- Nothing is mocked. With no credentials the SDK never opens a socket, and a
  database it cannot open is handled rather than thrown, so the app under test
  behaves exactly as it does on a device.
