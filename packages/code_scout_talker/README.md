# code_scout_talker

[![pub.dev](https://img.shields.io/pub/v/code_scout_talker.svg)](https://pub.dev/packages/code_scout_talker)

Sends everything [Talker](https://pub.dev/packages/talker) logs to your
[CodeScout](https://codescout.tech) dashboard as well.

Part of the [CodeScout](https://pub.dev/packages/code_scout) ecosystem.

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

**One name clashes.** Talker and CodeScout both export a type called `LogLevel`, so if you
configure them in the same file Dart refuses to guess which one you meant. Hide the one you are
not using:

```dart
import 'package:talker/talker.dart' hide LogLevel;
```

Then set CodeScout up as you normally would:

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

If your app calls both Talker and CodeScout directly, you can tag everything
that came through Talker so the two are easy to tell apart:

```dart
Talker(observer: CodeScoutTalkerObserver(tags: {'talker'}))
```

## How things map

| Talker | CodeScout |
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

## Before CodeScout is set up

Nothing breaks. Every callback does its work inside a try/catch, so a CodeScout
that is not yet initialised, has no credentials, or fails for any other reason
cannot interfere with your own `talker.info()` call. A logging tool that can
throw is a logging tool that takes down the code it was meant to watch.

## The rest of CodeScout

Forwarding Talker is one part of it. Once the logs reach a dashboard you run yourself, they are
searchable across every device rather than only on the phone in your hand:

<p align="center">
  <img src="https://raw.githubusercontent.com/getcodescout/code_scout/main/.github/assets/screenshots/logs.png" alt="The CodeScout log viewer, showing logs from a Flutter app with level toggles and tag filters" width="800" />
</p>

And a few things that are harder to get anywhere else:

- **Watch a device live.** Read somebody a six character code and their logs arrive in your browser
  as they tap. No install and no account for them.
- **Read the phone's own database.** While paired, browse the app's SQLite tables,
  `shared_preferences` and Hive boxes.
- **Hand a bug to your coding agent.** The dashboard speaks MCP, so an agent can read a whole
  session timeline itself.

[Take the tour](https://codescout.tech/docs/tour/) if you want to see it before installing
anything.

## License

MIT - see [LICENSE](LICENSE) for details.
