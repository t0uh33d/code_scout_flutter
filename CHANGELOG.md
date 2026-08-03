## 1.2.0

- **New: live sessions.** Open the overlay, tap **Live**, and type the six
  character code the dashboard shows under Live devices. From then on every log
  this launch produces arrives on the dashboard as it happens. Tap **Stop
  streaming**, close the app, or lose the network and the session ends — none
  of it is stored on the server unless somebody turns on Persist.
- Streaming is additional, never a replacement. Logs keep going to the console,
  the overlay and SQLite whether or not anyone is watching, and a live session
  that drops takes nothing with it.
- Live streaming ignores session sampling on purpose: somebody has deliberately
  paired with this device and is watching it right now, so showing them a
  sampled subset would make the feature useless exactly when it is in use.
- `CodeScout.instance.startLiveSession(code)` and `stopLiveSession()` are
  available directly if you would rather drive it from your own UI than from the
  overlay.
- Still no new dependencies: the socket is `dart:io`'s `WebSocket`.

- **New: session sampling.** `LoggingBehavior(sessionSampleRate: 0.1)` records
  one launch in ten instead of all of them. Whole sessions, not individual
  logs, so a session you keep keeps its whole timeline rather than showing
  gaps. The draw happens once at `init()`, so a launch that is left out costs
  nothing afterwards.
- **New:** the rate can also be set per project on the server, which the SDK
  picks up from the call it already makes to `/api/validate` at startup. The
  lower of the two wins, so a server can ask a noisy app to send less but can
  never make it send more than you asked for.
- Sampling gates what is stored and uploaded, never what you see while you
  work: the console and the in-app overlay show every log either way.

- **New: the SDK honours server backoff.** A `429` (or a `503` from a proxy) is
  now read as an instruction rather than a failure: the worker goes quiet for
  the `Retry-After` the server asked for and does not count it toward the
  five-failure auto-stop. Previously every non-200 was one untyped throw, so a
  server correctly saying "you are over your allowance" stopped logging for the
  rest of the process with no way back.
- **New:** a `413` halves the batch size and retries rather than failing, growing
  back toward the configured size on success.

- **New: redaction, opt-in.** Name headers or body keys in `RedactionBehavior`
  and they are replaced at capture, before anything reaches SQLite or an upload.
  Nothing is redacted unless you ask — this is a debugging tool, and a token is
  sometimes the reason a request is failing. Body keys match at any depth
  including inside lists, ignoring case and separators, so one `access_token`
  entry covers `accessToken` too. `RedactionBehavior.commonHeaders` and
  `commonBodyKeys` hold the usual suspects, and `RedactionBehavior.recommended()`
  switches them all on.
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
