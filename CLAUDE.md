# Code Scout Flutter Package

This file provides guidance to AI coding agents when working with the `code_scout` Flutter package.

## Package Overview

`code_scout` is a Flutter SDK that captures application logs and network requests, stores them locally in SQLite, and periodically syncs them to a remote Code Scout server via compressed tar.gz uploads.

**Package name:** `code_scout`
**Version:** 1.0.0
**Dart SDK:** ^3.11.0 | **Flutter:** >=3.0.0

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
```

## Key Patterns

- **Singletons everywhere:** `CodeScout.instance`, `NetworkManager.i`, `LogPersistenceService.i`, `OverlayManager.i`, `LogSyncWorker.i`
- **Log data flow:** `CodeScout.log()` (fire-and-forget) or `CodeScout.logMessage()` (awaitable) → `LogEntry.processLogEntry()` → `CSxPrinter` (console) + `LogPersistenceService` (SQLite) → `LogSyncWorker` (periodic) → `LogCompressor` (tar.gz in isolate) → `dart:io` HTTP POST to server
- **Network interception:** Users create interceptors (Dio/HTTP) in their own code that call `NetworkManager.i.processNetworkRequest/Response/Error()`. Each network call gets a unique `requestId` to correlate request→response→error phases. Stale requests are evicted after 2 minutes.
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
// Fire-and-forget (never throws)
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
// Dio — add interceptor (defined in your app, not in package)
dio.interceptors.add(CodeScoutDioInterceptor());

// HTTP — wrap client (defined in your app, not in package)
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
- Network request/response/error capture with request ID correlation
- Dio interceptor and HTTP client wrapper (in example/)
- Tag-based and level-based log filtering
- Batch compression and upload (with retry and backoff)
- Floating overlay button
- Socket connection establishment

### Incomplete / TODO
- Socket-based real-time log streaming (connection works, no data transmission)
- Device info capture (`captureDeviceInfo` config exists but not implemented)
- App context capture (`captureAppContext` config exists but not implemented)
- Menu UI controls for log type toggling (checkboxes commented out)
- Built-in interceptors (Dio/HTTP interceptors are only in example/, not in package)
- Tests
- pub.dev documentation and example cleanup
