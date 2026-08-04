import 'package:code_scout/src/db/db_source.dart';
import 'package:flutter/foundation.dart';

/// A source an app has offered up, and what may be done with it.
class RegisteredSource {
  const RegisteredSource({
    required this.name,
    required this.source,
    required this.writable,
  });

  final String name;
  final CodeScoutSource source;

  /// Whether the dashboard may change values here. False unless the app said
  /// otherwise, because someone exposing a database to look at has not thereby
  /// agreed to let it be edited.
  final bool writable;

  Map<String, dynamic> toJson() => {
        'name': name,
        'kind': source.kind.name,
        'writable': writable,
      };
}

/// Every database this app has offered to Code Scout.
///
/// Nothing is browsable until an app names it. There is deliberately no
/// scanning of the documents directory for `*.db`: that finds Code Scout's own
/// log store, some plugin's cache, and eventually an encrypted file it cannot
/// open, and it means a developer cannot tell what they exposed by reading
/// their own code.
///
/// Registration is the security model. Note that it is the opposite way round
/// from redaction, which hides nothing unless you name it — and the inversion
/// is the point. A log is something the app chose to write. A database is
/// everything the app has.
class DatabaseRegistry {
  DatabaseRegistry._();

  static final DatabaseRegistry i = DatabaseRegistry._();

  /// Insertion-ordered, which is what the dashboard's picker shows. The main
  /// database is nearly always registered first, so it should be listed first;
  /// sorting alphabetically would bury it under whatever happens to start with
  /// an "a".
  final Map<String, RegisteredSource> _sources = {};

  List<RegisteredSource> get sources => List.unmodifiable(_sources.values);

  bool get isEmpty => _sources.isEmpty;

  /// Offers a database up for browsing from the dashboard.
  ///
  /// Ignored in release builds unless [allowInRelease] is set. A browser
  /// compiled into a shipped app is a liability even when nobody uses it, and
  /// the default is what almost everybody ships.
  ///
  /// Throws if [name] is already taken. Quietly replacing it would mean
  /// browsing one database while reading another's name, and believing what
  /// you saw.
  void register(
    String name,
    CodeScoutSource source, {
    bool writable = false,
    bool allowInRelease = false,
  }) {
    if (kReleaseMode && !allowInRelease) return;

    if (name.isEmpty) {
      throw ArgumentError.value(name, 'name', 'must not be empty');
    }
    if (_sources.containsKey(name)) {
      throw ArgumentError.value(
        name,
        'name',
        'is already registered. Give each database its own name, '
            'or the dashboard cannot tell them apart',
      );
    }

    _sources[name] = RegisteredSource(
      name: name,
      source: source,
      writable: writable,
    );
  }

  RegisteredSource? find(String name) => _sources[name];

  /// Forgets everything. For tests, and for an app that tears Code Scout down.
  void clear() => _sources.clear();
}
