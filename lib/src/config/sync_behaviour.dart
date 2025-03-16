part of 'config.dart';

class LogSyncBehavior {
  final String syncEndpoint;
  final Duration syncInterval;
  final int maxBatchSize;
  final SyncNetworkCondition networkCondition;
  final RetryPolicy retryPolicy;
  final bool autoPurgeAfterSync;

  LogSyncBehavior({
    this.syncEndpoint = 'https://api.codescout.dev/logs',
    this.syncInterval = const Duration(minutes: 5),
    this.maxBatchSize = 100,
    this.networkCondition = SyncNetworkCondition.wifiOnly,
    this.retryPolicy = const RetryPolicy(
      maxAttempts: 3,
      backoffStrategy: BackoffStrategy.exponential(
        initialDelay: Duration(seconds: 1),
      ),
    ),
    this.autoPurgeAfterSync = true,
  });
}
