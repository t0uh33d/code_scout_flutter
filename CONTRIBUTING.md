# Contributing to the Code Scout Flutter SDK

Thanks for looking. Pull requests are genuinely welcome.

## Before you start something big

Open an issue first. A short note saying what you want to do usually gets an answer the same day,
and it saves you building something that does not fit. Small fixes need no ceremony.

## What lives here

Four packages, each with its own pubspec:

| Path | Package |
|------|---------|
| `.` | `code_scout`, the SDK itself |
| `packages/code_scout_dio` | the Dio interceptor |
| `packages/code_scout_http` | the `package:http` client wrapper |
| `example` | a runnable app that exercises all of it |

The two companion packages live in this repository on purpose rather than in their own. They call
the core's `NetworkManager` API, so they change with it, and splitting them would turn one commit
into a coordinated release across three repositories with a window where they disagree.

## Getting set up

```bash
flutter pub get
cd example && flutter run
```

The example runs with no configuration at all, using the console and the on-device overlay. To
point it at a dashboard, copy `example/local.example.json` to `example/local.json`, fill in the two
values, and run `flutter run --dart-define-from-file=local.json`. `local.json` is gitignored, so
your project secret cannot end up in a commit.

## Running the tests

```bash
flutter analyze          # must exit 0, including info level lints
flutter test
```

CI runs `analyze` and `test` for all four packages, plus `pub publish --dry-run` for the three
publishable ones. Two things to know, because both have caught people out:

**`flutter analyze` at the root also analyses `packages/`.** Run `flutter pub get` in each package
first, or you will get a screen of "undefined" errors about code that is perfectly fine.

**`flutter analyze` fails on info level lints too.** If you genuinely need to break one, use a
scoped `// ignore:` with a comment saying why, rather than switching the rule off for everyone.

### The end to end test

`test/e2e/` runs this SDK against a real dashboard and skips unless `CS_E2E_BASE` is set. Start it
from the server repository, which owns the throwaway database and port:

```bash
cd ../code_scout && make test-sdk-e2e
```

This is the only test anywhere that proves the SDK and the dashboard still agree. Everything else
checks each side against its own copy of the contract, and two copies drift without anything going
red. Worth running if you touch the wire format, the compressor or the sync worker.

## What a good pull request looks like

**It comes with a test, and the test fails without the fix.** Undo your change and watch it go red.
If it stays green the test is not testing what you think, which is better to find out now.

**It explains why, not what.** The comments people are grateful for are the ones explaining why
something surprising is written the way it is.

## House rules worth knowing

**An observability library must never break the app it observes.** Every capture path is wrapped so
that a failure inside Code Scout cannot fail the caller's request or crash their app. If you add a
path that can throw into user code, that is a bug even if the feature works.

**Nothing is redacted unless the app asks.** Redaction is opt in, because the token is often exactly
why a request is failing. What the app names is stripped at capture, before SQLite and before any
upload.

**No third party HTTP dependencies in the core.** Everything talks to the server through `dart:io`
`HttpClient`. That is what keeps the core package light and free of version conflicts with whatever
the host app already uses.

**Compression happens in an isolate**, so a large batch never janks the UI of the app it is
sitting inside.

## Reporting a bug

Please include the SDK version, the platform, and what the console printed. If the dashboard is
involved, the server's own log around the failure is usually the whole answer.

For security issues, see [SECURITY.md](SECURITY.md) and please do not open a public issue.

## Licence

By contributing you agree that your contribution is licensed under the MIT licence, the same as the
rest of the project.
