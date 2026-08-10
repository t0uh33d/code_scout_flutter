# code_scout_talker

[![pub.dev](https://img.shields.io/pub/v/code_scout_talker.svg)](https://pub.dev/packages/code_scout_talker)

Sends everything [Talker](https://pub.dev/packages/talker) logs to your
[Code Scout](https://codescout.tech) dashboard as well.

Part of the [Code Scout](https://pub.dev/packages/code_scout) ecosystem.

## Why

Talker is good at showing you what happened on the phone in your hand. It is not
built to tell you what happened on a tester's phone yesterday, or on the one
device out of two hundred where checkout keeps failing, because nothing it
records leaves the device.

This adds a second reader. Your logging code does not change, the console output
does not change, `TalkerScreen` keeps working, and every `talker_*` logger you
already use keeps working. The same logs simply also arrive somewhere you can
search across every device, filter by session, and share as a link.

## Getting started

```bash
flutter pub add code_scout_talker
```

This depends on [`code_scout`](https://pub.dev/packages/code_scout) and
[`talker`](https://pub.dev/packages/talker).

## Usage

Pass the observer when you create your Talker:

```dart
import 'package:talker/talker.dart';
import 'package:code_scout_talker/code_scout_talker.dart';

final talker = Talker(observer: CodeScoutTalkerObserver());
```

**One name clashes.** Talker and Code Scout both export a type called `LogLevel`, so if you
configure them in the same file Dart refuses to guess which one you meant. Hide the one you are
not using:

```dart
import 'package:talker/talker.dart' hide LogLevel;
```

Then set Code Scout up as you normally would:

```dart
await CodeScout.instance.init(
  configuration: CodeScoutConfiguration(
    projectCredentials: ProjectCredentials(
      link: 'https://your-dashboard.example.com/',
      projectID: '...',
      projectSecret: '...',
    ),
  ),
);
```

That is the whole setup. Everything through `talker.info()`, `talker.error()`,
`talker.handle()` and the companion loggers now reaches the dashboard too.

### Tagging forwarded logs

If your app calls both Talker and Code Scout directly, you can tag everything
that came through Talker so the two are easy to tell apart:

```dart
Talker(observer: CodeScoutTalkerObserver(tags: {'talker'}))
```

## How things map

| Talker | Code Scout |
|--------|-----------|
| `critical` | `fatal` |
| `error` | `error` |
| `warning` | `warning` |
| `info` | `info` |
| `debug` | `debug` |
| `verbose` | `verbose` |
| no level set | `info`, or `error` for a handled error |

Talker's log key becomes a **tag**, which is where this earns its keep: the
companion loggers set keys like `http-request` and `bloc-event`, so the
dashboard's tag filters are useful the moment you connect. Talker's title is
display text rather than an identifier, so it goes into the log's metadata as
`talker_title` instead of becoming a messy tag.

An error logged with no message uses the error itself as the message, because
`talker.handle(e)` is a normal thing to write and a blank row helps nobody.

## Before Code Scout is set up

Nothing breaks. Every callback does its work inside a try/catch, so a Code Scout
that is not yet initialised, has no credentials, or fails for any other reason
cannot interfere with your own `talker.info()` call. A logging tool that can
throw is a logging tool that takes down the code it was meant to watch.

## License

MIT - see [LICENSE](LICENSE) for details.
