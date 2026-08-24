# Overlay screenshots

Generated, never hand-captured. A screenshot nobody can regenerate is one that
quietly goes out of date, and these are the only pictures anywhere of the half
of CodeScout that needs no server.

```bash
CS_SHOTS_OUT=.github/assets/screenshots flutter test test/overlay_shots_test.dart
```

`test/overlay_shots_test.dart` renders `CSxInterface` at each tab, at a phone
size and 3x, against a seeded launch of a shop app whose checkout fails after a
token refresh comes back 401. That is deliberately the same story the dashboard
captures tell over in the server repo, so the two sets read as one product.

Without `CS_SHOTS_OUT` the file writes nothing, so a normal `flutter test` and
CI never touch these.

The site copies them with `landing_and_docs/scripts/sync-screenshots.mjs`.
