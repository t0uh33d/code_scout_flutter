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
