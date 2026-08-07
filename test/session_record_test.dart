import 'dart:convert';

import 'package:code_scout/code_scout.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final started = DateTime.utc(2026, 7, 30, 14, 16, 2);
  final seen = DateTime.utc(2026, 7, 30, 14, 22, 43);

  SessionRecord record({String? userId, Map<String, dynamic>? metadata}) {
    return SessionRecord(
      id: '4f2a81b0-0000-4000-8000-000000000001',
      installationId: 'e7c1b8a2-40aa-4f12-9c07-3d5581bb40aa',
      userId: userId,
      deviceModel: 'Pixel 7',
      osName: 'Android',
      osVersion: '14',
      appVersion: '3.11.2',
      buildNumber: '418',
      metadata: metadata,
      startedAt: started,
      lastSeenAt: seen,
    );
  }

  // These key names are the contract with the server. A rename here is a
  // silently ignored field there, so the session arrives with a blank device.
  test('the wire shape matches what the server reads', () {
    final json = record(userId: 'u_8812').toJson();

    expect(json.keys.toSet(), {
      'id',
      'installation_id',
      'user_id',
      'device_model',
      'os_name',
      'os_version',
      'app_version',
      'build_number',
      'metadata',
      'started_at',
      'last_seen_at',
      'sdk_version',
    });
    expect(json['device_model'], 'Pixel 7');
    expect(json['user_id'], 'u_8812');
    expect(json['sdk_version'], codeScoutSdkVersion);
    // The server parses ISO-8601 in UTC. A local timestamp would put every
    // session hours away from when it happened.
    expect(json['started_at'], '2026-07-30T14:16:02.000Z');
  });

  // The two shapes are not the same and must not be built from each other in
  // the direction that lets the wire leak into the database. toRow used to be
  // `{...toJson(), ...}`, so any key added for the server also went into the
  // INSERT, hit a column that does not exist, and failed every session write.
  test('the row shape has no wire-only fields', () {
    final row = record(userId: 'u_8812').toRow();

    expect(
      row.containsKey('sdk_version'),
      isFalse,
      reason: 'sdk_version has no column; including it fails the INSERT',
    );
    expect(row.keys.toSet(), {
      'id',
      'installation_id',
      'user_id',
      'device_model',
      'os_name',
      'os_version',
      'app_version',
      'build_number',
      'metadata',
      'started_at',
      'last_seen_at',
    });
  });

  test('metadata is an object on the wire and a string in the row', () {
    final traits = {'plan': 'free', 'beta': true};
    final r = record(userId: 'u_8812', metadata: traits);

    expect(r.toJson()['metadata'], traits);
    expect(r.toRow()['metadata'], jsonEncode(traits));
  });

  test('a row survives the round trip', () {
    final r = record(userId: 'u_8812', metadata: {'plan': 'free'});
    final back = SessionRecord.fromRow(r.toRow());

    expect(back.id, r.id);
    expect(back.installationId, r.installationId);
    expect(back.userId, 'u_8812');
    expect(back.deviceModel, 'Pixel 7');
    expect(back.metadata, {'plan': 'free'});
    expect(back.startedAt, started);
    expect(back.lastSeenAt, seen);
  });

  // A record written by a version that stored something else, or a row that
  // got corrupted, is still a session worth reporting.
  test('unreadable metadata does not lose the session', () {
    final back = SessionRecord.fromRow({
      'id': 'abc',
      'metadata': 'not json at all',
      'started_at': started.toIso8601String(),
      'last_seen_at': seen.toIso8601String(),
    });

    expect(back.id, 'abc');
    expect(back.metadata, isNull);
  });

  test('setUser can name someone and take it back', () {
    final anonymous = record();
    expect(anonymous.userId, isNull);

    final named = anonymous.copyWith(userId: 'u_8812');
    expect(named.userId, 'u_8812');

    // Signing out has to actually clear it, not fall through to the old value.
    final signedOut = named.copyWith(clearUser: true);
    expect(signedOut.userId, isNull);
  });

  // started_at is the truth about when the app launched. copyWith is used on
  // every sync, and moving it would make every session look like it began at
  // its most recent upload.
  test('nothing can move the start time', () {
    final moved = record().copyWith(lastSeenAt: DateTime.utc(2030));
    expect(moved.startedAt, started);
    expect(moved.lastSeenAt, DateTime.utc(2030));
  });
}
