## 1.2.0

- **New, and on by default: redaction.** Credentials are stripped at capture,
  before anything reaches SQLite or an upload. Covers the usual credential
  headers and body keys (`password`, `access_token`, `secret`, `cvv` and the
  rest) at any depth, matching case- and separator-insensitively so
  `access_token` and `accessToken` are the same key. Configure with
  `RedactionBehavior`, or `RedactionBehavior.off()` if you own every endpoint.
- **New:** bodies over `maxBodyBytes` (32 KB by default) are truncated with a
  note saying how much was dropped, so one large response cannot turn into a
  large upload on someone's mobile connection.

- **New:** the in-app overlay is now a real log viewer. Tapping the floating
  button opens a sheet with **Logs**, **Network** and **Session** tabs: level
  and tag filters, rows that expand to their error, stack trace and metadata,
  network phases paired into one row per call, and the session details you get
  asked for in a bug report. It reads an in-memory buffer of the current launch,
  so it works identically with no server configured.
- **Removed:** the overlay's raw IP/port/identifier socket form, and with it the
  `provider` dependency. It was superseded by the pairing-code flow coming with
  live streaming, and nothing referenced it any more.
- **New:** every app launch is now recorded as a session, carrying the device
  model, OS name and version, your app's version and build number, and a random
  installation id that is stable for the life of the install. The dashboard uses
  these for its Sessions and Devices screens.
- **New:** `CodeScout.instance.setUser(id, traits: {...})` names the person using
  the app. Identity is opt-in and never inferred — a session is anonymous until
  you call it. Pass `null` on sign out. Safe to call at any point in a launch.
- **Behaviour change:** `captureDeviceInfo` and `captureAppContext` now do
  something. Both have always defaulted to `true` and been ignored; they now
  control whether those fields are collected.
- **New dependencies:** `device_info_plus` and `package_info_plus`, for the
  device model and app version respectively.
- Uploads now carry a second `sessions.json` entry alongside `data.json`. Older
  servers read entries by name and skip what they do not recognise.

## 1.1.1

- **Fix:** logging or network capture before `CodeScout.instance.init()` no longer
  throws `LateInitializationError` into the caller — configuration and session id
  now have safe defaults, and `NetworkManager` capture is a no-op until init.
- **Fix:** network error logs now carry the `network` tag, matching the request and
  response phases. Previously `enabledTags: {'network'}` silently dropped them.
- **Behaviour change:** narrowing `enabledTags` no longer discards untagged logs.
  The allowlist now narrows tagged logs only; set `allowUntagged: false` for the
  previous behaviour. Use `minimumLevel` to control overall volume.

## 1.1.0

* Added level-specific shorthand methods (`.v()`, `.d()`, `.i()`, `.w()`, `.e()`, `.f()`)
* Changed `message` parameter type from `dynamic` to `String` for a cleaner API contract
* Added companion packages for network interception: `code_scout_dio` and `code_scout_http`

## 1.0.0

* Initial release
* Structured logging with 8 levels (all, system, verbose, debug, info, warning, error, fatal)
* Tag-based and level-based log filtering
* SQLite local persistence with WAL mode
* Automatic batch sync to self-hosted Code Scout server (tar.gz compression)
* Background isolate compression to avoid UI jank
* Network request/response/error interception with request ID correlation
* Atomic sync pipeline with retry and automatic backoff
* Floating overlay button for development controls
* Socket connection scaffolding for real-time streaming
* Zero third-party HTTP dependencies — all server communication via dart:io
