# code_scout_http

[![pub.dev](https://img.shields.io/pub/v/code_scout_http.svg)](https://pub.dev/packages/code_scout_http)

HTTP client wrapper for [Code Scout](https://codescout.tech). Automatically captures network requests, responses, and errors.

Part of the [Code Scout](https://pub.dev/packages/code_scout) ecosystem.

## Getting Started

```bash
flutter pub add code_scout_http
```

This package depends on [`code_scout`](https://pub.dev/packages/code_scout) and [`http`](https://pub.dev/packages/http).

## Usage

```dart
import 'package:code_scout_http/code_scout_http.dart';
import 'package:http/http.dart' as http;

final client = CodeScoutHttpClient(client: http.Client());

// Use it like a normal http.Client — it's a drop-in replacement
final response = await client.get(Uri.parse('https://api.example.com/data'));
```

Every request, response, and error will be automatically captured, correlated by request ID, and synced to your Code Scout server.

## License

MIT - see [LICENSE](LICENSE) for details.
