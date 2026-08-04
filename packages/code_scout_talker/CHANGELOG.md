## 1.0.0

* Initial release.
* `CodeScoutTalkerObserver` forwards Talker logs, errors and exceptions to Code Scout without any change to your logging code.
* Talker's log key becomes a Code Scout tag, so `talker_dio_logger`, `talker_bloc_logger` and the rest arrive already filterable.
* Capture is wrapped defensively, so a Code Scout failure can never break the `talker` call that triggered it.
