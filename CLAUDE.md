# Code Scout Flutter Package

This file provides guidance to AI coding agents when working with the `code_scout` Flutter package.

## Package Overview

`code_scout` is a Flutter SDK that captures application logs and network requests, stores them locally in SQLite, and periodically syncs them to a remote Code Scout server via compressed tar.gz uploads.

**Package name:** `code_scout`
**Version:** 1.3.0
**Dart SDK:** ^3.11.0 | **Flutter:** >=3.0.0
**Published:** [pub.dev/packages/code_scout](https://pub.dev/packages/code_scout)

### Companion Packages

Network interception is provided via separate companion packages to keep the core SDK dependency-free:

| Package | Purpose | pub.dev |
|---------|---------|---------|
| `code_scout_dio` | Dio interceptor — `CodeScoutDioInterceptor` | [pub.dev/packages/code_scout_dio](https://pub.dev/packages/code_scout_dio) |
| `code_scout_http` | HTTP client wrapper — `CodeScoutHttpClient` | [pub.dev/packages/code_scout_http](https://pub.dev/packages/code_scout_http) |

These live in `packages/code_scout_dio/` and `packages/code_scout_http/` within this repo. Their pubspecs depend on `code_scout: ^1.0.0` (hosted). The example app uses `dependency_overrides` to resolve the path dep for local development.

## Commands

```bash
flutter pub get                          # Install dependencies
cd example && flutter run                # Run example app
flutter test                             # Run tests
flutter analyze                          # Static analysis
```

CI runs `analyze` and `test` for all four packages here — the SDK, both
companions and the example — plus `pub publish --dry-run` for the three
publishable ones, and the cross-repo SDK e2e against a real dashboard.
`flutter analyze` must exit 0: it fails on info-level lints too, so a lint you
mean to break needs an `// ignore:` with a reason rather than a repo-wide
exception.

`test/e2e/` runs this SDK against a real dashboard and skips unless
`CS_E2E_BASE` points at one. Start it from the server repo, which owns the
throwaway database and port:

```bash
cd ../code_scout && make test-sdk-e2e
```

It is the only test where the wire contract is not written down on both sides:
the logs go in through the public API and come back out of the dashboard's
export endpoint. Two things about the host it runs on are worth knowing, since
both failed silently the first time. `TestWidgetsFlutterBinding` installs an
`HttpOverrides` that answers every request with 400 without opening a socket, so
the test clears it. And `getTemporaryDirectory()` is a platform channel with
nothing behind it here, so `PathProviderPlatform.instance` is replaced — left
alone, the compressor throws inside the sync worker's own catch, which reports
through `dart:developer` where the test runner never shows it.

## Architecture

```
lib/
├── code_scout.dart                      # Public barrel export
└── src/
    ├── code_scout.dart                  # Main singleton (CodeScout.instance)
    ├── code_scout_comms.dart            # Socket command/payload protocol
    ├── config/
    │   ├── config.dart                  # CodeScoutConfiguration
    │   ├── logging_behaviour.dart       # LoggingBehavior (levels, tags, console)
    │   ├── sync_behaviour.dart          # LogSyncBehavior (interval, batch size)
    │   ├── real_time.dart               # RealTimeConfig
    │   └── project_creds.dart           # ProjectCredentials (auth headers)
    ├── log/
    │   ├── log_entry.dart               # LogEntry model + processLogEntry()
    │   ├── log_level.dart               # LogLevel enum (all→off, 10 levels)
    │   ├── log_printer.dart             # CSxPrinter — console output formatting
    │   ├── ansi_color.dart              # ANSI color codes for console
    │   ├── log_persistence_service.dart # SQLite storage (code_scout.db)
    │   ├── log_sync_worker.dart         # Periodic sync timer + dart:io upload
    │   └── log_compressor.dart          # JSON → tar.gz compression (via isolate)
    ├── network/
    │   ├── network_manager.dart         # NetworkManager.i singleton (TTL-based cleanup)
    │   ├── network_request.dart         # NetworkRequestData model
    │   ├── network_response.dart        # NetworkResponseData model
    │   ├── network_error_data.dart      # NetworkErrorData model
    │   └── network_data.dart            # NetworkData union type
    ├── csx_interface/
    │   ├── overlay_manager.dart         # Floating button overlay
    │   ├── menu.dart                    # CSxInterface sheet — Logs/Network/Live/Session tabs
    │   ├── live_pane.dart               # The Live tab — pairing code entry and session state
    │   ├── log_buffer.dart              # LogBuffer — capped in-memory ring the overlay reads
    │   └── overlay_theme.dart           # The dashboard's palette, for the overlay
    ├── live/
    │   └── live_session_client.dart     # dart:io WebSocket to the dashboard, pairing + streaming
    ├── session/
    │   ├── session_record.dart      # SessionRecord — one launch, wire + row shapes
    │   └── device_profile.dart      # Device model, OS, app version via the plus plugins
    ├── utils/
    │   ├── redactor.dart               # Strips credentials at capture
    │   ├── draggable_widget.dart        # DraggableFloatingWindow
    │   └── stack_trace_parser.dart      # StackTraceParser + StackCallDetails
    └── const/
        └── global_vars.dart             # Global variables

packages/
├── code_scout_dio/
│   └── lib/code_scout_dio.dart          # CodeScoutDioInterceptor (single file)
└── code_scout_http/
    └── lib/code_scout_http.dart         # CodeScoutHttpClient (single file)
```

## Key Patterns

- **Singletons everywhere:** `CodeScout.instance`, `NetworkManager.i`, `LogPersistenceService.i`, `OverlayManager.i`, `LogSyncWorker.i`
- **Log data flow:** `CodeScout.d()` / `.log()` / `.logMessage()` → `LogEntry.processLogEntry()` → `CSxPrinter` (console) + `LogPersistenceService` (SQLite) → `LogSyncWorker` (periodic) → `LogCompressor` (tar.gz in isolate) → `dart:io` HTTP POST to server
- **Network interception:** Companion packages (`code_scout_dio`, `code_scout_http`) call `NetworkManager.i.processNetworkRequest/Response/Error()`. Each network call gets a unique `requestId` to correlate request→response→error phases. Stale requests are evicted after 2 minutes.
- **Configuration:** All behavior controlled via `CodeScoutConfiguration` passed to `CodeScout.instance.init()`. Includes `LoggingBehavior` (filtering), `LogSyncBehavior` (timing), `ProjectCredentials` (server auth), `RealTimeConfig`.
- **Zero HTTP dependency:** All server communication uses `dart:io` `HttpClient` directly — no `http` or `dio` in the core package.
- **Sync atomicity:** Logs are marked `sync_status=1` before upload, rolled back on failure, deleted on success. Concurrent syncs are prevented via a `_syncing` guard.

## Public API Surface

### Initialization
```dart
await CodeScout.instance.init(
  freshContextFetcher: () => context,
  configuration: CodeScoutConfiguration(
    logging: LoggingBehavior(minimumLevel: LogLevel.all),
    projectCredentials: ProjectCredentials(
      link: 'http://localhost:24275/',
      projectID: 'uuid',
      projectSecret: 'secret',
    ),
    sync: LogSyncBehavior(syncInterval: Duration(seconds: 10)),
  ),
);
```

### Logging
```dart
// Level-specific shorthand methods (fire-and-forget, never throws)
final scout = CodeScout.instance;
scout.v('Verbose trace data');
scout.d('Debug info');
scout.i('User signed in', tags: {'auth'});
scout.w('Cache miss', metadata: {'key': 'prefs'});
scout.e('Payment failed', error: e, stackTrace: st);
scout.f('Unrecoverable state');

// Full form (when level is dynamic)
CodeScout.instance.log(
  level: LogLevel.info,
  message: 'Something happened',
  tags: {'network', 'auth'},
  metadata: {'userId': '123'},
);

// Awaitable (propagates errors)
await CodeScout.instance.logMessage(
  level: LogLevel.error,
  message: 'Critical failure',
);
```

### Network Interception
```dart
// Dio — install code_scout_dio package
import 'package:code_scout_dio/code_scout_dio.dart';
dio.interceptors.add(CodeScoutDioInterceptor());

// HTTP — install code_scout_http package
import 'package:code_scout_http/code_scout_http.dart';
final client = CodeScoutHttpClient(client: http.Client());
```

### Overlay Controls
```dart
CodeScout.instance.showIcon();
CodeScout.instance.hideIcon();
CodeScout.instance.toggleIcon();
```

### Sync and cleanup
```dart
// Upload what is waiting now, instead of at the next scheduled cycle.
// Worth calling when the app is about to background, or on sign-out.
await CodeScout.instance.flush();

await CodeScout.instance.dispose();
```

### Browsing local storage from the dashboard

```dart
// SQLite, through the connection the app already has.
CodeScout.instance.registerDatabase('shop.db', CodeScoutSqflite(db),
    writable: kDebugMode);

// shared_preferences, Hive, get_storage — anything with a key and a value.
// Closures rather than the package's types, so none of them becomes a
// dependency of the SDK for a debug-only feature.
CodeScout.instance.registerDatabase('prefs', CodeScoutKeyValue(
  keys: () async => prefs.getKeys(),
  readKey: (k) async => prefs.get(k),
  writeKey: (k, v) async => v == null ? prefs.remove(k) : prefs.setString(k, '$v'),
), writable: kDebugMode);
```

Reachable only while the device is in a live session, because the data is on the phone and nowhere
else. Nothing on the server is written. The rules that hold the feature together:

- **Nothing is browsable until the app names it.** No scanning for `*.db` — that finds the SDK's own
  log store and eventually an encrypted file it cannot open. This is the inverse of redaction, which
  hides nothing unless you name it, and the inversion is deliberate.
- **The dashboard never sends SQL.** Five structured ops (`sources`, `namespaces`, `schema`, `rows`,
  `update`); the device builds every statement from its own schema, with identifiers checked for
  membership rather than escaped. **Adding an op that takes a statement ends the safety argument.**
- **`writable` is enforced in `DatabaseRegistry`**, not in the source, so an op cannot route round
  it. Registration is ignored in release builds unless `allowInRelease`.
- **The dashboard may only edit what it actually saw.** A blob, a truncated string and a redacted
  value are all read-only for one reason: the update carries the old value to catch a conflict, and
  a value nobody was shown cannot be compared against anything.
- **A successful write logs itself** at `system` level, which is exempt from both the level gate and
  the sampling gate — it is the SDK's own record of something it did to the device, not app volume.

## SQLite Schema (logs table)

```sql
CREATE TABLE logs (
  id TEXT PRIMARY KEY,
  session_id TEXT NOT NULL,
  level TEXT NOT NULL,
  message TEXT,
  error TEXT,
  stack_trace TEXT,          -- JSON array of StackCallDetails
  metadata TEXT,             -- JSON map
  tags TEXT,                 -- JSON array
  timestamp TEXT,            -- ISO-8601
  is_network_call INTEGER NOT NULL DEFAULT 0,
  request_id TEXT,
  call_phase TEXT,           -- request|response|error
  sync_status INTEGER NOT NULL DEFAULT 0  -- 0=pending, 1=syncing
);

CREATE TABLE sessions (
  id TEXT PRIMARY KEY,       -- the launch's session id
  installation_id TEXT,      -- stable for the life of the install
  user_id TEXT,              -- only ever set by setUser()
  device_model TEXT,
  os_name TEXT,
  os_version TEXT,
  app_version TEXT,
  build_number TEXT,
  metadata TEXT,             -- JSON map of traits
  started_at TEXT NOT NULL,
  last_seen_at TEXT NOT NULL
);

CREATE TABLE meta (          -- key/value; holds installation_id
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL
);
```

Schema version is **2**. A database created by 1.1.x has only `logs`; `onUpgrade` adds the other two.

Sessions outlive their logs by one step: a batch sends the session records its logs reference (not only the current launch, since a launch killed before syncing leaves logs behind), and `pruneSessions` drops the ones nothing refers to any more, always keeping the live one.

## Server Communication

- **Auth headers:** `X-Project-ID` and `X-Project-Secret` on every request
- **Credential validation:** `GET {link}api/validate`
- **Log upload:** `POST {link}api/logs/dump` — multipart form with `file` field containing `data.tar.gz`
- **Compression:** JSON → tar archive → gzip → `data.tar.gz` (runs in background isolate). Two entries: `data.json` holds the logs, `sessions.json` holds the sessions those logs belong to. The server reads entries by name, so `sessions.json` is omitted when there are none.
- **All HTTP via `dart:io`** — no third-party HTTP packages in core

## What's Implemented vs TODO

### Working
- Full logging pipeline (capture → console → SQLite → sync)
- Level-specific shorthand methods (`.v()`, `.d()`, `.i()`, `.w()`, `.e()`, `.f()`)
- Network request/response/error capture with request ID correlation
- Dio interceptor (`code_scout_dio` package) and HTTP client wrapper (`code_scout_http` package)
- Tag-based and level-based log filtering
- Batch compression and upload (with retry and backoff)
- Sessions: every launch recorded with device model, OS, app version/build, and a stable installation id
- `setUser(id, traits:)` — opt-in identity, re-sent with every batch so a mid-session call still lands
- Device and app context capture (`captureDeviceInfo` / `captureAppContext` are honoured)
- In-app overlay: Logs, Network and Session tabs, reading a capped in-memory buffer so it works with no server configured
- Opt-in redaction (`RedactionBehavior`) and body size caps (32 KB)
- Server backoff: 429/503 read `Retry-After` and pause without counting toward the failure counter; 413 halves the batch. `lib/src/log/sync_backoff.dart`. Five consecutive real failures buy a 5 minute pause, not a stop, and the counter resets after it
- Session sampling: `LoggingBehavior.sessionSampleRate`, lowered further by the project's server-side rate from `/api/validate`, drawn once per launch in `init()`. The gate is in `processLogEntry`, above the SQLite write and below the console and overlay
- Live sessions: `lib/src/live/live_session_client.dart`, a `dart:io` WebSocket to `{link}api/live/socket`. Pairs with a six character code typed into the overlay's Live tab, then streams every log as it happens. `publish()` sits **above** the sampling gate in `processLogEntry` — somebody watching deliberately should see everything

### Incomplete / TODO
- Nothing outstanding for 1.0 in the SDK.
- `make test-sdk-e2e` has no coverage of the database browser. The dashboard's Playwright tests use
  a stub device answering canned JSON, and the Flutter tests use a real SQLite file with no server,
  so nothing yet proves the two repos agree on that wire format. It has already bitten once: a fix
  shipped with its Go half committed and its SDK half not, and every e2e test stayed green.

### Publishing

**1.3.0 is what is on pub.dev**, so everything documented here is released and in people's apps.
The wire format is now a published contract: a tar with `data.json`, and `sessions.json` alongside
it since 1.2.0. Entries are read by name at the server, which is what lets an older SDK that sends
only `data.json` keep working.

**All three packages are published and match what is on disk** as of 2026-08-04: `code_scout`
1.3.0, `code_scout_dio` 1.0.1, `code_scout_http` 1.0.1. The last gap was `code_scout_dio`, where
pub.dev sat on 1.0.0 without the defensive try/catch around capture. Nothing is held back now.
