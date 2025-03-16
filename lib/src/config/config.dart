import 'dart:convert';

import 'package:code_scout/src/log/log_entry.dart' show LogEntry;
import 'package:convert/convert.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

part 'logging_behaviour.dart';
part 'sync_behaviour.dart';

class CodeScoutConfiguration {
  final LoggingBehavior logging;
  final LogSyncBehavior sync;
  final RealTimeConfig realTime;

  CodeScoutConfiguration({
    required this.logging,
    required this.sync,
    required this.realTime,
  });

  factory CodeScoutConfiguration.defaults() => CodeScoutConfiguration(
        logging: LoggingBehavior(),
        sync: LogSyncBehavior(),
        realTime: RealTimeConfig(),
      );
}

class RealTimeConfig {
  final bool enableLiveStreaming;

  RealTimeConfig({
    this.enableLiveStreaming = true,
  });
}

// Supporting enums and classes
enum LogLevel { verbose, debug, info, warning, error, critical }

enum SyncNetworkCondition { any, wifiOnly, unmeteredOnly }

class RetryPolicy {
  final int maxAttempts;
  final BackoffStrategy backoffStrategy;

  const RetryPolicy({
    required this.maxAttempts,
    required this.backoffStrategy,
  });
}

class BackoffStrategy {
  final Duration initialDelay;
  final double factor;

  const BackoffStrategy.exponential({
    this.initialDelay = const Duration(seconds: 1),
    this.factor = 2.0,
  });
}

class ProjectCredentials {
  final String projectKey;
  final String? projectSecret; // For enhanced security scenarios
  final String? environment; // e.g., 'prod', 'staging'

  ProjectCredentials({
    required this.projectKey,
    this.projectSecret,
    this.environment,
  }) {
    if (projectKey.isEmpty) {
      throw ArgumentError('Project key cannot be empty');
    }
  }

  Map<String, String> get authHeaders {
    final headers = {'X-Project-Key': projectKey};
    if (projectSecret != null) {
      headers['X-Project-Secret'] = _hashSecret(projectSecret!);
    }
    return headers;
  }

  String _hashSecret(String secret) {
    // Implement HMAC-based hashing

    final hmac = Hmac(sha256, utf8.encode(projectKey));
    return hex.encode(hmac.convert(utf8.encode(secret)).bytes);
  }
}
