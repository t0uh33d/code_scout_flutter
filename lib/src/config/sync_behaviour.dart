part of 'config.dart';

class LogSyncBehavior {
  final Duration syncInterval;
  final int maxBatchSize;

  LogSyncBehavior({
    this.syncInterval = const Duration(minutes: 5),
    this.maxBatchSize = 100,
  });
}
