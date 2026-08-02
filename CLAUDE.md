# Code Scout Flutter Package

This file provides guidance to AI coding agents when working with the `code_scout` Flutter package.

## Package Overview

`code_scout` is a Flutter SDK that captures application logs and network requests, stores them locally in SQLite, and periodically syncs them to a remote Code Scout server via compressed tar.gz uploads.

**Package name:** `code_scout`
**Version:** 1.2.0
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
    │   ├── menu.dart                    # CSxInterface sheet — Logs/Network/Session tabs
    │   ├── log_buffer.dart              # LogBuffer — capped in-memory ring the overlay reads
    │   └── overlay_theme.dart           # The dashboard's palette, for the overlay
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

### Cleanup
```dart
await CodeScout.instance.dispose();
```

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
- Published on pub.dev

### Incomplete / TODO
- Real-time log streaming and the overlay's pairing-code screen (the socket protocol is defined; there is no server for it yet)
- Opt-in redaction (`RedactionBehavior`) and body size caps (32 KB, on by default)
- Server backoff: 429/503 read `Retry-After` and pause without counting toward the auto-stop; 413 halves the batch. `lib/src/log/sync_backoff.dart`
- Tests
