/// [LogLevel]s to control logging output. Logging can be enabled to include all
/// levels above certain [LogLevel].
enum LogLevel {
  all(0),
  trace(1000),
  debug(2000),
  info(3000),
  warning(4000),
  error(5000),
  fatal(6000),
  off(10000);

  final int value;

  const LogLevel(this.value);
}
