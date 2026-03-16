# code_scout_dio

Dio interceptor for [Code Scout](https://codescout.tech). Automatically captures network requests, responses, and errors.

## Getting Started

```bash
flutter pub add code_scout_dio
```

This package depends on [`code_scout`](https://pub.dev/packages/code_scout) and [`dio`](https://pub.dev/packages/dio).

## Usage

```dart
import 'package:code_scout_dio/code_scout_dio.dart';

final dio = Dio();
dio.interceptors.add(CodeScoutDioInterceptor());
```

Every request, response, and error flowing through the Dio instance will be automatically captured, correlated by request ID, and synced to your Code Scout server.

## License

MIT - see [LICENSE](LICENSE) for details.
