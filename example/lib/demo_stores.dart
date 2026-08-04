import 'package:code_scout/code_scout.dart';
import 'package:flutter/foundation.dart';
import 'package:hive_ce/hive.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

/// Every kind of local storage Code Scout can browse, opened and registered.
///
/// Three shapes, and only two adapters, which is the point worth taking away:
/// SQLite gets [CodeScoutSqflite], and everything with a key and a value gets
/// [CodeScoutKeyValue] — the same class serves `shared_preferences` and Hive
/// because it takes functions rather than either package's types.
class DemoStores {
  DemoStores._({required this.db, required this.prefs, required this.notes, required this.drafts});

  final Database db;
  final SharedPreferences prefs;
  final Box<String> notes;
  final Box<String> drafts;

  /// Opens everything and offers it to Code Scout.
  ///
  /// Anything that fails to open is logged and skipped rather than thrown: an
  /// app that treats opening storage as a certainty crashes on startup when it
  /// is not, and under `flutter test` none of these have a platform
  /// implementation at all.
  static Future<DemoStores?> openAndRegister() async {
    try {
      final db = await _openDatabase();
      final prefs = await SharedPreferences.getInstance();

      final dir = await getApplicationDocumentsDirectory();
      Hive.init(p.join(dir.path, 'hive'));
      final notes = await Hive.openBox<String>('notes');
      final drafts = await Hive.openBox<String>('drafts');

      // 1. SQLite, through the connection the app already has. WAL, SQLCipher
      //    and attached databases all keep working because this is the same
      //    connection the app itself reads through.
      CodeScout.instance.registerDatabase(
        'example_app.db',
        CodeScoutSqflite(db),
        writable: kDebugMode,
      );

      // 2. shared_preferences. Four closures, no dependency added to the SDK.
      CodeScout.instance.registerDatabase(
        'prefs',
        CodeScoutKeyValue(
          namespace: 'prefs',
          keys: () async => prefs.getKeys(),
          readKey: (k) async => prefs.get(k),
          writeKey: (k, v) async =>
              v == null ? await prefs.remove(k) : await prefs.setString(k, '$v'),
        ),
        writable: kDebugMode,
      );

      // 3. Hive, with a box per namespace so each is listed like its own table.
      CodeScout.instance.registerDatabase(
        'hive',
        CodeScoutKeyValue.namespaces({
          'notes': _box(notes),
          'drafts': _box(drafts),
        }),
        writable: kDebugMode,
      );

      return DemoStores._(db: db, prefs: prefs, notes: notes, drafts: drafts);
    } catch (e, stack) {
      CodeScout.instance.e(
        'Local storage could not be opened',
        error: e,
        stackTrace: stack,
        tags: {'startup'},
      );
      return null;
    }
  }

  static CodeScoutKeyValue _box(Box<String> box) => CodeScoutKeyValue(
        keys: () async => box.keys.map((k) => '$k'),
        readKey: (k) async => box.get(k),
        writeKey: (k, v) async => v == null ? await box.delete(k) : await box.put(k, '$v'),
      );

  static Future<Database> _openDatabase() async {
    final path = p.join(await getDatabasesPath(), 'example_app.db');
    return openDatabase(
      path,
      version: 1,
      onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE feature_flags (
            key TEXT NOT NULL PRIMARY KEY,
            enabled INTEGER NOT NULL,
            rollout_pct INTEGER,
            note TEXT
          )
        ''');
        await db.execute('''
          CREATE TABLE cart_items (
            product_id INTEGER NOT NULL,
            title TEXT NOT NULL,
            qty INTEGER NOT NULL,
            price_cents INTEGER NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE account (
            id INTEGER PRIMARY KEY,
            email TEXT,
            auth_token TEXT,
            plan TEXT
          )
        ''');
        // A view, so the dashboard has something it can show but not edit.
        await db.execute(
          'CREATE VIEW open_orders AS SELECT title, qty FROM cart_items WHERE qty > 0',
        );

        for (final flag in const [
          {'key': 'checkout_v2', 'enabled': 0, 'rollout_pct': 25, 'note': 'staged'},
          {'key': 'one_tap_pay', 'enabled': 1, 'rollout_pct': 100, 'note': null},
          {'key': 'dark_mode', 'enabled': 1, 'rollout_pct': 100, 'note': null},
          {'key': 'search_beta', 'enabled': 0, 'rollout_pct': 0, 'note': 'off'},
        ]) {
          await db.insert('feature_flags', flag);
        }
        await db.insert('cart_items',
            {'product_id': 8812, 'title': 'Running shoes', 'qty': 1, 'price_cents': 8999});
        // auth_token is here on purpose: RedactionBehavior.recommended() names
        // it, so the dashboard shows [redacted] and the value never leaves the
        // phone. Worth seeing rather than reading about.
        await db.insert('account', {
          'id': 1,
          'email': 'ada@example.com',
          'auth_token': 'tok_live_51H8xQ2eZvKYlo2C',
          'plan': 'pro',
        });
      },
    );
  }

  // --- What the Data screen writes, so the dashboard has something to watch ---

  static const _products = [
    ['Wool socks', 1250],
    ['Rain jacket', 12999],
    ['Water bottle', 1899],
    ['Head torch', 3450],
  ];

  Future<void> addCartItem() async {
    final count = Sqflite.firstIntValue(
          await db.rawQuery('SELECT count(*) FROM cart_items'),
        ) ??
        0;
    final pick = _products[count % _products.length];
    await db.insert('cart_items', {
      'product_id': 1000 + count,
      'title': pick[0],
      'qty': 1 + (count % 3),
      'price_cents': pick[1],
    });
  }

  Future<void> toggleFlag(String key) async {
    final rows = await db.query('feature_flags', where: 'key = ?', whereArgs: [key]);
    if (rows.isEmpty) return;
    final now = (rows.first['enabled'] as int? ?? 0) == 0 ? 1 : 0;
    await db.update('feature_flags', {'enabled': now}, where: 'key = ?', whereArgs: [key]);
  }

  Future<void> bumpLaunchCount() async {
    final now = int.tryParse(prefs.getString('launch_count') ?? '') ?? 0;
    await prefs.setString('launch_count', '${now + 1}');
  }

  Future<void> touchPrefs() async {
    await prefs.setString('last_touched', DateTime.now().toIso8601String());
    await prefs.setString('locale', prefs.getString('locale') == 'en_GB' ? 'fr_FR' : 'en_GB');
  }

  Future<void> addNote() async {
    // Keyed on the time rather than the count: deleting a note and adding
    // another would otherwise reuse a key and overwrite one that is still there.
    final stamp = DateTime.now();
    await notes.put(
      'note_${stamp.millisecondsSinceEpoch}',
      'Written on the device at ${stamp.toIso8601String()}',
    );
  }

  Future<List<Map<String, Object?>>> flags() => db.query('feature_flags', orderBy: 'key');
  Future<List<Map<String, Object?>>> cart() => db.query('cart_items');
}
