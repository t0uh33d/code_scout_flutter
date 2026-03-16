# Code Scout Flutter Package

This file provides guidance to AI coding agents when working with the `code_scout` Flutter package.

## Package Overview

`code_scout` is a Flutter SDK that captures application logs and network requests, stores them locally in SQLite, and periodically syncs them to a remote Code Scout server via compressed tar.gz uploads.

**Package name:** `code_scout`
**Version:** 1.1.0
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
    │   ├── menu.dart                    # CSxInterface bottom sheet widget
    │   └── controller.dart              # CSxInterfaceController (socket connection)
    ├── utils/
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
```

## Server Communication

- **Auth headers:** `X-Project-ID` and `X-Project-Secret` on every request
- **Credential validation:** `GET {link}api/validate`
- **Log upload:** `POST {link}api/logs/dump` — multipart form with `file` field containing `data.tar.gz`
- **Compression:** JSON array → tar archive (`data.json`) → gzip → `data.tar.gz` (runs in background isolate)
- **All HTTP via `dart:io`** — no third-party HTTP packages in core

## What's Implemented vs TODO

### Working
- Full logging pipeline (capture → console → SQLite → sync)
- Level-specific shorthand methods (`.v()`, `.d()`, `.i()`, `.w()`, `.e()`, `.f()`)
- Network request/response/error capture with request ID correlation
- Dio interceptor (`code_scout_dio` package) and HTTP client wrapper (`code_scout_http` package)
- Tag-based and level-based log filtering
- Batch compression and upload (with retry and backoff)
- Floating overlay button
- Socket connection establishment
- Published on pub.dev

### Incomplete / TODO
- Socket-based real-time log streaming (connection works, no data transmission)
- Device info capture (`captureDeviceInfo` config exists but not implemented)
- App context capture (`captureAppContext` config exists but not implemented)
- Menu UI controls for log type toggling (checkboxes commented out)
- Tests
