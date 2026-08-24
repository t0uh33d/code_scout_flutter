## 1.0.2

### Changed

- **The name reads CodeScout, one word.** The description published with 1.0.1
  still said "Code Scout", because the rename landed after that version went out
  and pub.dev only takes a new listing with a new version.
- **The readme says what the rest of CodeScout does.** It used to end at the
  licence, so somebody who installed this for Talker capture had no way to learn
  that live device streaming, the database browser and the agent tools exist.

No code changed in this release.

## 1.0.1

### Changed

- **The declared minimum is now Flutter 3.38 (Dart 3.10), where it used to say Flutter 3.0.**
  That old number was never true, so pub.dev advertised compatibility with releases that could
  not resolve the package. Nothing about the code changed.

## 1.0.0

* Initial release.
* `CodeScoutTalkerObserver` forwards Talker logs, errors and exceptions to CodeScout without any change to your logging code.
* Talker's log key becomes a CodeScout tag, so `talker_dio_logger`, `talker_bloc_logger` and the rest arrive already filterable.
* Capture is wrapped defensively, so a CodeScout failure can never break the `talker` call that triggered it.
