import 'dart:convert';
import 'dart:typed_data';

import 'package:code_scout/src/utils/redactor.dart';

/// SQLite's five type affinities.
///
/// A column's declared type is a hint, not a constraint. SQLite converts text
/// that looks like a number on its way in — binding "42" to an INTEGER column
/// really does store the integer 42 — but text that does not is stored as text,
/// so binding "banana" to that same column leaves a String sitting where the app
/// expects an int, and the app crashes reading data the debugger wrote.
///
/// So the job here is mostly **refusal** rather than conversion: work out what
/// the column holds, and reject anything SQLite would silently store as the
/// wrong type.
enum SqliteAffinity { integer, text, blob, real, numeric }

/// Works out a column's affinity from its declared type, following SQLite's own
/// five rules in their own order.
///
/// Order matters and is not alphabetical: "POINT" contains "INT" and is
/// therefore INTEGER, and "VARCHAR" is checked for CHAR only after INT has been
/// ruled out. Reimplementing this loosely is how a column ends up coerced to
/// something the app cannot read back.
SqliteAffinity affinityOf(String declaredType) {
  final t = declaredType.toUpperCase();
  if (t.contains('INT')) return SqliteAffinity.integer;
  if (t.contains('CHAR') || t.contains('CLOB') || t.contains('TEXT')) {
    return SqliteAffinity.text;
  }
  if (t.isEmpty || t.contains('BLOB')) return SqliteAffinity.blob;
  if (t.contains('REAL') || t.contains('FLOA') || t.contains('DOUB')) {
    return SqliteAffinity.real;
  }
  return SqliteAffinity.numeric;
}

/// The largest a single cell may be before it is shown as a summary. Past this
/// the dashboard is not being shown the value, so it may not edit it either.
const int maxCellChars = 4096;

/// A rough ceiling on one page of rows, so a table of large text columns cannot
/// build a frame the socket will refuse. The server drops a device message over
/// one megabyte, and a dropped frame kills the stream rather than the query.
const int maxPageBytes = 512 * 1024;

/// One cell on its way to the dashboard: what to show, and whether the
/// dashboard is seeing enough of it to be allowed to change it.
class CellValue {
  const CellValue(this.display, {this.editable = true, this.because});

  /// JSON-safe: a string, a number, a bool, or null.
  final Object? display;

  /// False when what the dashboard has is a summary rather than the value.
  ///
  /// The rule across the whole feature is that **the dashboard may only edit
  /// what it actually saw**. A blob, a truncated string and a redacted value
  /// all fail that test for different reasons, and all three are read-only for
  /// the same one: an update carries the old value to detect a conflict, and a
  /// value nobody was shown cannot be compared against anything.
  final bool editable;

  /// Why, in words meant for a person. Null when [editable].
  final String? because;

  Map<String, dynamic> toJson() => {
        'v': display,
        if (!editable) 'ro': because,
      };
}

/// Turns one value out of SQLite into something that can be sent and shown.
CellValue encodeCell(Object? raw, {bool redacted = false}) {
  if (redacted) {
    // The real value never leaves the device. The flag on the column is a
    // rendering hint; this is the part that actually protects anything.
    return CellValue(
      Redactor.placeholder,
      editable: false,
      because: 'This column is redacted, so its value never left the device.',
    );
  }

  if (raw == null) return const CellValue(null);

  if (raw is Uint8List || raw is List<int>) {
    final bytes = raw is Uint8List ? raw : Uint8List.fromList(raw as List<int>);
    return CellValue(
      '<blob · ${Redactor.formatSize(bytes.length)}>',
      editable: false,
      because: 'Binary data is shown as a size rather than as text.',
    );
  }

  if (raw is String && raw.length > maxCellChars) {
    return CellValue(
      '${raw.substring(0, maxCellChars)}…',
      editable: false,
      because: 'Too long to show in full, so it cannot be edited from here.',
    );
  }

  // int, double, bool and ordinary strings travel as themselves.
  return CellValue(raw);
}

/// Why a value could not be coerced to what its column expects.
class CoercionError implements Exception {
  const CoercionError(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Turns the string the dashboard typed into what the column can hold.
///
/// Null means the caller asked for SQL NULL, which is a real thing to want and
/// is why the dashboard has its own control for it rather than treating an
/// empty field as one.
Object? coerceForColumn(String? typed, String declaredType) {
  if (typed == null) return null;

  switch (affinityOf(declaredType)) {
    case SqliteAffinity.integer:
      final n = int.tryParse(typed.trim());
      if (n == null) {
        throw CoercionError('"$typed" is not a whole number, '
            'and this column holds $declaredType.');
      }
      return n;

    case SqliteAffinity.real:
      final d = double.tryParse(typed.trim());
      if (d == null) {
        throw CoercionError('"$typed" is not a number, '
            'and this column holds $declaredType.');
      }
      return d;

    case SqliteAffinity.text:
      return typed;

    case SqliteAffinity.blob:
      // BLOB affinity means "store whatever you are given", not "this holds
      // bytes". A column declared with no type at all lands here by SQLite's
      // own rule 3, and `CREATE TABLE t (a, b)` is legal and common — so is
      // anything from CREATE TABLE ... AS SELECT. Refusing the whole affinity
      // made every untyped column permanently uneditable, with a message about
      // binary data that had nothing to do with it.
      //
      // A cell actually holding bytes never reaches here: encodeCell renders a
      // blob as its size and marks it read-only, so the dashboard offers no
      // editor for one.
      return typed;

    case SqliteAffinity.numeric:
      // SQLite's NUMERIC does exactly this: a value that looks like a number is
      // stored as one, and anything else is stored as text.
      return int.tryParse(typed.trim()) ?? double.tryParse(typed.trim()) ?? typed;
  }
}

/// How many bytes a row will take on the wire. Used to stop building a page
/// before it grows into a frame the socket will refuse.
///
/// Measured in encoded UTF-8, not in `String.length`. Dart strings are UTF-16
/// code units, so `length` undercounts every non-ASCII character: CJK is three
/// bytes to one unit, and an emoji is four bytes to two. A page of Japanese
/// text passed a budget it was three times over, and the frame that reached
/// the server was refused by its read limit — which does not fail the query,
/// it drops the socket and ends the live session for everyone watching.
///
/// JSON escaping is charged too. A string full of quotes or backslashes very
/// nearly doubles on the wire, and a table holding stringified JSON is the
/// common case for that.
int approximateBytes(List<CellValue> cells) {
  var total = 0;
  for (final c in cells) {
    final v = c.display;
    total += switch (v) {
      null => 4,
      String s => _wireCost(s),
      _ => 8,
    };
  }
  // Punctuation and keys, near enough for a budget that only has to be in the
  // right order of magnitude.
  return total + 16;
}

/// What one string costs as a JSON value: its UTF-8 bytes, plus the escaping
/// JSON will add, plus the two quotes around it.
int _wireCost(String s) {
  var bytes = utf8.encode(s).length;
  for (final unit in s.codeUnits) {
    // The characters jsonEncode expands. Quote and backslash become two bytes;
    // a control character becomes the six of \u00XX.
    if (unit == 0x22 || unit == 0x5C) {
      bytes += 1;
    } else if (unit < 0x20) {
      bytes += 5;
    }
  }
  return bytes + 2;
}

/// JSON encoding used for the size estimate in tests and for the wire.
String encodePage(Object? page) => jsonEncode(page);
