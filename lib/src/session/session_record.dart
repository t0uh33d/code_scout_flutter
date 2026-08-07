import 'dart:convert';

import 'package:code_scout/src/session/device_profile.dart';
import 'package:code_scout/src/version.dart';

/// One app launch, as the SDK knows it.
///
/// Stored locally alongside the logs and re-sent with every batch. Re-sending
/// is deliberate: the server keys on the id and upserts, so no batch has to be
/// the first one, and a launch whose first upload failed still gets a proper
/// row when a later batch lands. It also means [setUser] called ten minutes in
/// reaches the dashboard on the next sync without any special path.
class SessionRecord {
  const SessionRecord({
    required this.id,
    required this.startedAt,
    required this.lastSeenAt,
    this.installationId,
    this.userId,
    this.deviceModel,
    this.osName,
    this.osVersion,
    this.appVersion,
    this.buildNumber,
    this.metadata,
  });

  final String id;

  /// Stable across launches of the same install and carries nothing personal —
  /// a random value written once. It is what lets the dashboard say "this
  /// phone" without knowing whose phone it is.
  final String? installationId;

  /// Only ever set by setUser(). Never inferred from anything.
  final String? userId;

  final String? deviceModel;
  final String? osName;
  final String? osVersion;
  final String? appVersion;
  final String? buildNumber;

  /// Traits, and whatever else the app attached. Per session rather than per
  /// user on purpose: what matters when debugging is what was true when it
  /// broke, not what is true now.
  final Map<String, dynamic>? metadata;

  final DateTime startedAt;
  final DateTime lastSeenAt;

  SessionRecord copyWith({
    String? installationId,
    String? userId,
    bool clearUser = false,
    DeviceProfile? profile,
    Map<String, dynamic>? metadata,
    bool clearMetadata = false,
    DateTime? lastSeenAt,
  }) {
    return SessionRecord(
      id: id,
      installationId: installationId ?? this.installationId,
      userId: clearUser ? null : (userId ?? this.userId),
      deviceModel: profile?.model ?? deviceModel,
      osName: profile?.osName ?? osName,
      osVersion: profile?.osVersion ?? osVersion,
      appVersion: profile?.appVersion ?? appVersion,
      buildNumber: profile?.buildNumber ?? buildNumber,
      metadata: clearMetadata ? null : (metadata ?? this.metadata),
      startedAt: startedAt,
      lastSeenAt: lastSeenAt ?? this.lastSeenAt,
    );
  }

  /// The wire shape, which is what goes into sessions.json.
  ///
  /// [sdk_version] is stamped from the constant rather than stored on the
  /// record, so it needs no column and no on-device migration. It also means an
  /// app that upgraded the SDK mid-session reports the version it is running
  /// now, which is the more useful answer than the one it launched with.
  Map<String, dynamic> toJson() => {
        ...toRow(),
        'metadata': metadata,
        'sdk_version': codeScoutSdkVersion,
      };

  /// The SQLite row.
  ///
  /// This is the base shape and [toJson] builds on it, not the other way round.
  /// It used to be the reverse, which made the wire shape unextendable: any key
  /// added to [toJson] landed in the INSERT as well, hit a column that does not
  /// exist, and failed every session write on the device. Metadata is a JSON
  /// string here and a real object on the wire, which is the other difference.
  Map<String, dynamic> toRow() => {
        'id': id,
        'installation_id': installationId,
        'user_id': userId,
        'device_model': deviceModel,
        'os_name': osName,
        'os_version': osVersion,
        'app_version': appVersion,
        'build_number': buildNumber,
        'metadata': metadata == null ? null : jsonEncode(metadata),
        'started_at': startedAt.toUtc().toIso8601String(),
        'last_seen_at': lastSeenAt.toUtc().toIso8601String(),
      };

  factory SessionRecord.fromRow(Map<String, dynamic> row) {
    Map<String, dynamic>? metadata;
    final raw = row['metadata'];
    if (raw is String && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) metadata = decoded;
      } catch (_) {
        // A row we cannot read is still a session worth reporting.
      }
    }

    return SessionRecord(
      id: row['id'] as String,
      installationId: row['installation_id'] as String?,
      userId: row['user_id'] as String?,
      deviceModel: row['device_model'] as String?,
      osName: row['os_name'] as String?,
      osVersion: row['os_version'] as String?,
      appVersion: row['app_version'] as String?,
      buildNumber: row['build_number'] as String?,
      metadata: metadata,
      startedAt: _parseTime(row['started_at']),
      lastSeenAt: _parseTime(row['last_seen_at']),
    );
  }

  static DateTime _parseTime(dynamic value) {
    if (value is String) {
      final parsed = DateTime.tryParse(value);
      if (parsed != null) return parsed;
    }
    return DateTime.now().toUtc();
  }
}
