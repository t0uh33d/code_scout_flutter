import 'package:code_scout/src/db/db_registry.dart';
import 'package:code_scout/src/db/db_source.dart';

/// Answers the database questions the dashboard asks over a live session.
///
/// The ops are the whole vocabulary. There is no op that takes SQL, so there is
/// no statement the dashboard can compose: it names a table and a page, and the
/// device builds the query. Read-only is a property of what can be expressed
/// here rather than a rule somebody has to remember to enforce.
class DatabaseDispatcher {
  const DatabaseDispatcher._();

  /// Runs one command and returns the body of the reply.
  ///
  /// Never throws. Everything that can go wrong — an unknown op, an
  /// unregistered database, a column that is not in the schema — comes back as
  /// `ok: false` with something a person can read, because the alternative is a
  /// dashboard that waits out the full timeout for an answer that was never
  /// coming.
  static Future<Map<String, dynamic>> handle(
    String op,
    Map<String, dynamic> args,
  ) async {
    try {
      return await _run(op, args);
    } on ArgumentError catch (e) {
      return {'ok': false, 'error': e.message?.toString() ?? 'That is not something I can read.'};
    } catch (e) {
      return {'ok': false, 'error': e.toString()};
    }
  }

  static Future<Map<String, dynamic>> _run(String op, Map<String, dynamic> args) async {
    // Listing what is on offer needs no database named, and is how the
    // dashboard's picker gets filled.
    if (op == 'sources') {
      return {
        'ok': true,
        'sources': DatabaseRegistry.i.sources.map((s) => s.toJson()).toList(),
      };
    }

    final dbName = args['db'] as String?;
    if (dbName == null) {
      return {'ok': false, 'error': 'No database was named.'};
    }
    final entry = DatabaseRegistry.i.find(dbName);
    if (entry == null) {
      // The same answer whether it was never registered or was registered under
      // a different name. There is nothing to probe for here, but there is also
      // nothing useful to say beyond this.
      return {'ok': false, 'error': 'No database is registered as "$dbName".'};
    }

    switch (op) {
      case 'namespaces':
        final found = await entry.source.namespaces();
        return {'ok': true, 'namespaces': found.map((n) => n.toJson()).toList()};

      case 'schema':
        final schema = await entry.source.describe(args['namespace'] as String);
        return {'ok': true, 'schema': schema.toJson(), 'writable': entry.writable};

      case 'rows':
        final page = await DatabaseRegistry.i.read(
          dbName,
          CodeScoutReadRequest.fromJson(args),
        );
        return {'ok': true, 'page': page.toJson()};

      case 'update':
        // Straight to the registry, never to the source: the registry is where
        // writable is enforced, and routing round it would make that flag a
        // suggestion.
        final result = await DatabaseRegistry.i.write(
          dbName,
          CodeScoutWriteRequest.fromJson(args),
        );
        return {...result.toJson()};

      default:
        return {'ok': false, 'error': 'Unknown command "$op".'};
    }
  }
}
