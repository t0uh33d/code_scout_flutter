<p align="center">
  <img src="assets/pim_code_scout.svg" alt="Code Scout" width="320" />
</p>

<p align="center">
  A lightweight, open-source logging and network inspection SDK for Flutter.
</p>

<p align="center">
  <a href="https://pub.dev/packages/code_scout"><img src="https://img.shields.io/pub/v/code_scout.svg" alt="pub.dev"></a>
  <a href="https://pub.dev/packages/code_scout_dio"><img src="https://img.shields.io/pub/v/code_scout_dio.svg?label=code_scout_dio" alt="code_scout_dio"></a>
  <a href="https://pub.dev/packages/code_scout_http"><img src="https://img.shields.io/pub/v/code_scout_http.svg?label=code_scout_http" alt="code_scout_http"></a>
</p>

<p align="center">
  <a href="https://codescout.tech">Website</a> &middot;
  <a href="https://pub.dev/packages/code_scout">pub.dev</a> &middot;
  <a href="https://github.com/t0uh33d/code_scout_flutter">GitHub</a> &middot;
  <a href="https://github.com/t0uh33d/code_scout">Server</a>
</p>

---

Capture logs and network calls locally, then sync them to a self-hosted [Code Scout dashboard](https://github.com/t0uh33d/code_scout) for browsing, filtering, and real-time monitoring.

## Features

- **Structured logging** with levels (debug, info, warning, error, fatal), tags, and metadata
- **Network interception** for Dio and `http` — correlates request, response, and error by request ID
- **Local persistence** in SQLite so logs survive app restarts
- **Automatic batch sync** — compresses logs to tar.gz and uploads on a configurable interval
- **Zero third-party HTTP deps** — all server communication uses `dart:io`
- **Floating overlay** for quick access to connection controls during development
- **Lightweight** — designed to add minimal overhead to your app

## Packages

| Package | Description | pub.dev |
|---------|-------------|---------|
| [code_scout](https://pub.dev/packages/code_scout) | Core logging SDK | [![pub.dev](https://img.shields.io/pub/v/code_scout.svg)](https://pub.dev/packages/code_scout) |
| [code_scout_dio](https://pub.dev/packages/code_scout_dio) | Dio interceptor | [![pub.dev](https://img.shields.io/pub/v/code_scout_dio.svg)](https://pub.dev/packages/code_scout_dio) |
| [code_scout_http](https://pub.dev/packages/code_scout_http) | HTTP client wrapper | [![pub.dev](https://img.shields.io/pub/v/code_scout_http.svg)](https://pub.dev/packages/code_scout_http) |

## Getting Started

Install the core package:

```bash
flutter pub add code_scout
```

For network interception, add the companion package for your HTTP client:

```bash
# For Dio users
flutter pub add code_scout_dio

# For http users
flutter pub add code_scout_http
```

## Usage

### Initialize

Call `init()` early in your app (e.g. after the first frame):

```dart
import 'package:code_scout/code_scout.dart';

await CodeScout.instance.init(
  freshContextFetcher: () => context,
  configuration: CodeScoutConfiguration(
    logging: LoggingBehavior(minimumLevel: LogLevel.all),
    projectCredentials: ProjectCredentials(
      link: 'http://your-server:24275/',
      projectID: 'your-project-id',
      projectSecret: 'your-project-secret',
    ),
    sync: LogSyncBehavior(
      syncInterval: Duration(seconds: 30),
      maxBatchSize: 100,
    ),
  ),
);
```

### Log messages

Use the shorthand methods for quick logging:

```dart
final scout = CodeScout.instance;

scout.d('Fetching user profile');                       // debug
scout.i('User signed in', tags: {'auth'});              // info
scout.w('Cache miss', metadata: {'key': 'user_prefs'}); // warning
scout.e('Payment failed', error: e, stackTrace: st);    // error
scout.f('Unrecoverable state');                          // fatal
scout.v('Detailed trace data');                          // verbose
```

You can also use the full form when you need to specify the level dynamically:

```dart
CodeScout.instance.log(
  level: LogLevel.info,
  message: 'User signed in',
  tags: {'auth'},
  metadata: {'userId': '123'},
);

// Awaitable (if you need to confirm persistence)
await CodeScout.instance.logMessage(
  level: LogLevel.error,
  message: 'Payment failed',
  error: exception,
  stackTrace: stackTrace,
);
```

### Capture network calls

Network interception is provided through separate companion packages so the core SDK stays dependency-free. Each package is a one-liner to set up.

#### Dio

Add `code_scout_dio` to your dependencies, then attach the interceptor:

```dart
import 'package:code_scout_dio/code_scout_dio.dart';

final dio = Dio();
dio.interceptors.add(CodeScoutDioInterceptor());
```

Every request, response, and error flowing through this Dio instance will be automatically captured.

#### http

Add `code_scout_http` to your dependencies, then wrap your client:

```dart
import 'package:code_scout_http/code_scout_http.dart';
import 'package:http/http.dart' as http;

final client = CodeScoutHttpClient(client: http.Client());

// Use it like a normal http.Client
final response = await client.get(Uri.parse('https://api.example.com/data'));
```

`CodeScoutHttpClient` extends `http.BaseClient`, so it's a drop-in replacement anywhere you use `http.Client`.

#### How it works

Both interceptors call `NetworkManager.i.processNetworkRequest/Response/Error()` under the hood. Each network call gets a unique `requestId` that correlates the request, response, and error phases together, giving you a complete picture of every API call.

### Overlay controls

```dart
CodeScout.instance.showIcon();   // Show floating button
CodeScout.instance.hideIcon();   // Hide it
CodeScout.instance.toggleIcon(); // Toggle
```

### Cleanup

```dart
await CodeScout.instance.dispose();
```

## How It Works

```
Flutter App                                Code Scout Server
┌─────────────────────────┐               ┌─────────────────────────┐
│ CodeScout.log()         │               │                         │
│ NetworkManager          │               │  POST /api/logs/dump    │
│         |               │               │    (multipart tar.gz)   │
│ LogPersistenceService   │  periodic     │         |               │
│   (SQLite)              │──sync───────> │  Log ingestion          │
│         |               │  tar.gz       │         |               │
│ LogSyncWorker           │  X-Project-ID │  MySQL storage          │
│ LogCompressor (isolate) │               │         |               │
└─────────────────────────┘               │  Web Dashboard          │
                                          └─────────────────────────┘
```

1. Logs are written to a local SQLite database
2. A periodic timer picks up unsync'd logs, marks them as syncing, compresses them in a background isolate, and uploads via `dart:io`
3. On success, logs are deleted locally. On failure, they're rolled back and retried next cycle
4. After 5 consecutive failures the sync worker stops automatically to avoid battery drain

## Configuration

| Option | Default | Description |
|--------|---------|-------------|
| `LoggingBehavior.minimumLevel` | `LogLevel.info` | Minimum level to capture |
| `LoggingBehavior.enabledTags` | `{'*'}` | Tags to capture (`*` = all) |
| `LoggingBehavior.printToConsole` | `true` in debug | Print logs to console |
| `LoggingBehavior.includeCurrentStackTrace` | `false` | Attach stack trace to every log |
| `LogSyncBehavior.syncInterval` | 5 minutes | How often to sync |
| `LogSyncBehavior.maxBatchSize` | 100 | Max logs per upload |

## Server Setup

Code Scout needs a self-hosted server to receive logs. See the [code-scout](https://github.com/t0uh33d/code_scout) repo for setup instructions.

```bash
# Create a project (returns project_id and secret)
curl -X POST http://localhost:24275/api/project \
  -H "Content-Type: application/json" \
  -d '{"name": "My App", "description": "Production logs"}'
```

Use the returned `project_id` and `secret_key` in your `ProjectCredentials`.

## Contributing

Contributions are welcome! This is a free and open-source project.

1. Fork the repo
2. Create a feature branch (`git checkout -b feature/my-feature`)
3. Make your changes and run `flutter analyze` to ensure there are no issues
4. Submit a pull request

## License

This project is open source. See the [LICENSE](LICENSE) file for details.
