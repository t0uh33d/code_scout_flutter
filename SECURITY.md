# Security

## Reporting a vulnerability

Please do not open a public issue.

Use GitHub's [private vulnerability reporting](https://github.com/getcodescout/code_scout_flutter/security/advisories/new)
on this repository, or email **touheedkhan1408@gmail.com**.

Tell us what you found and how to reproduce it. You will get a reply within a few days.

## What is in scope

This SDK runs inside other people's apps, so the things worth reporting are:

- **Anything that leaks data the app did not intend to send.** The SDK captures logs and HTTP
  traffic, so a bug that sends more than was asked for, or sends it somewhere unexpected, matters a
  lot.
- **Redaction not actually redacting.** What an app names in `RedactionBehavior` must be stripped
  at capture, before it reaches SQLite or the network. A path that stores or uploads the original is
  a real bug.
- **The project secret leaking**, for example into a log line, an exception message or a crash
  report.
- **Anything that lets Code Scout crash or hang the host app.** An observability library that takes
  the app down with it is a serious failure, and every capture path is wrapped to prevent that.

## Things that are deliberate, and are not bugs

**Nothing is redacted unless the app asks for it.** Out of the box the SDK records what your app
sent, including headers. That is a product decision, not an oversight: the auth header is often
exactly why a request is failing. Use `RedactionBehavior.recommended()` to turn on the usual
suspects in one line.

**Logs are stored unencrypted in the app's own SQLite database.** They live in your app's private
storage, protected by the same OS sandbox as the rest of your app data. If your threat model
includes a rooted or jailbroken device, do not log secrets.

**The project secret ships inside the app binary.** Anyone who can read your app can read it. It
authorises writing logs into one project and nothing else, which is why the ingest credential is
separate from any dashboard account. Rotate it in the dashboard's settings if you need to.

## If you are shipping this to production

Decide about redaction before you ship, not after. Read
[the redaction guide](https://codescout.tech/docs/guides/redaction/), and consider
`RedactionBehavior.recommended()` as a starting point rather than a finished answer, since only you
know what your app puts in its own log lines.
