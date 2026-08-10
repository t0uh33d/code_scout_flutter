import 'package:code_scout/code_scout.dart' as cs;
import 'package:code_scout_talker/code_scout_talker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:talker/talker.dart';

void main() {
  final observer = CodeScoutTalkerObserver();

  cs.LogLevel levelOf(LogLevel? from, {cs.LogLevel fallback = cs.LogLevel.info}) =>
      observer.map(TalkerData('m', logLevel: from), fallback: fallback).level;

  group('levels', () {
    test('every Talker level reaches the Code Scout level of the same name', () {
      expect(levelOf(LogLevel.error), cs.LogLevel.error);
      expect(levelOf(LogLevel.warning), cs.LogLevel.warning);
      expect(levelOf(LogLevel.info), cs.LogLevel.info);
      expect(levelOf(LogLevel.debug), cs.LogLevel.debug);
      expect(levelOf(LogLevel.verbose), cs.LogLevel.verbose);
    });

    test('critical becomes fatal, because neither side has the other word', () {
      // The one mapping that is not a rename. Talker's worst level is
      // critical and Code Scout's is fatal, so an app's most serious log has
      // to land on the dashboard's most serious level or it reads as ordinary.
      expect(levelOf(LogLevel.critical), cs.LogLevel.fatal);
    });

    test('no level at all falls back to what the caller asked for', () {
      // An untyped log is info. An untyped *error* is not, which is why the
      // fallback belongs to the caller rather than to the mapping.
      expect(levelOf(null), cs.LogLevel.info);
      expect(levelOf(null, fallback: cs.LogLevel.error), cs.LogLevel.error);
    });

    test('a level Talker did set always wins over the fallback', () {
      expect(levelOf(LogLevel.debug, fallback: cs.LogLevel.error), cs.LogLevel.debug);
    });
  });

  group('message', () {
    test('the message is carried through unchanged', () {
      expect(observer.map(TalkerData('cart emptied'), fallback: cs.LogLevel.info).message,
          'cart emptied');
    });

    test('an error logged with no message uses the error itself', () {
      // talker.handle(e) with no message is normal, and Talker's message is
      // nullable. Without this the dashboard shows a blank row where the most
      // useful thing on screen should be.
      final m = observer.map(
        TalkerException(Exception('card declined')),
        fallback: cs.LogLevel.error,
      );
      expect(m.message, contains('card declined'));
    });

    test('an empty message is treated as no message', () {
      final m = observer.map(
        TalkerData('', exception: Exception('timeout')),
        fallback: cs.LogLevel.error,
      );
      expect(m.message, contains('timeout'));
    });

    test('with neither a message nor a cause, the title is better than blank', () {
      expect(observer.map(TalkerData(null, title: 'route'), fallback: cs.LogLevel.info).message,
          'route');
    });
  });

  group('the cause', () {
    test('an exception is carried as the error', () {
      final boom = Exception('boom');
      expect(observer.map(TalkerException(boom), fallback: cs.LogLevel.error).error, boom);
    });

    test('a stack trace survives', () {
      final st = StackTrace.current;
      expect(
        observer.map(TalkerData('m', stackTrace: st), fallback: cs.LogLevel.info).stackTrace,
        st,
      );
    });
  });

  group('tags', () {
    test("Talker's log key becomes a tag", () {
      // The point of this: talker_dio_logger sets keys like 'http-request',
      // and those are what make the dashboard's tag filter worth using.
      expect(observer.map(TalkerData('m', key: 'http-request'), fallback: cs.LogLevel.info).tags,
          {'http-request'});
    });

    test('configured tags are added to the key', () {
      final tagged = CodeScoutTalkerObserver(tags: {'talker'});
      expect(tagged.map(TalkerData('m', key: 'bloc-event'), fallback: cs.LogLevel.info).tags,
          {'talker', 'bloc-event'});
    });

    test('no key and no configured tags means no tags, not an empty set', () {
      expect(observer.map(TalkerData('m'), fallback: cs.LogLevel.info).tags, isNull);
    });

    test('configured tags apply even when Talker sets no key', () {
      final tagged = CodeScoutTalkerObserver(tags: {'talker'});
      expect(tagged.map(TalkerData('m'), fallback: cs.LogLevel.info).tags, {'talker'});
    });
  });

  group('metadata', () {
    test('a real title is kept', () {
      expect(
        observer.map(TalkerData('m', title: 'HTTP Request'), fallback: cs.LogLevel.info).metadata,
        {'talker_title': 'HTTP Request'},
      );
    });

    test("Talker's default title of 'log' is dropped", () {
      // It is on every ordinary log and says nothing, so carrying it would put
      // a useless key on every row in the viewer.
      expect(observer.map(TalkerData('m'), fallback: cs.LogLevel.info).metadata, isNull);
    });
  });

  group('it never breaks the app it observes', () {
    test('forwarding before CodeScout.init does not throw', () {
      // The whole point of the try/catch. An app wires the observer up in
      // main() and may well log before init() has finished; a throw here would
      // take out the app's own talker.info() call.
      expect(() => observer.onLog(TalkerData('early')), returnsNormally);
      expect(() => observer.onError(TalkerError(ArgumentError('x'))), returnsNormally);
      expect(() => observer.onException(TalkerException(Exception('y'))), returnsNormally);
    });

    test('a real Talker with the observer attached logs normally', () {
      final talker = Talker(observer: observer);
      expect(() {
        talker.info('hello');
        talker.error('bad', ArgumentError('x'));
        talker.handle(Exception('unhandled'));
      }, returnsNormally);
    });
  });

  group('each event is forwarded exactly once', () {
    test('handle() reaches one callback, not two', () {
      // Talker dispatches errors to onError/onException and returns before the
      // log path, so all three callbacks can forward unconditionally. If that
      // ever changes upstream, every error would appear twice on the dashboard
      // and this is what says so.
      final counts = _CountingObserver();
      final talker = Talker(observer: counts);

      talker.info('one');
      expect(counts.total, 1);

      talker.handle(Exception('two'));
      expect(counts.total, 2);

      talker.handle(ArgumentError('three'));
      expect(counts.total, 3);
    });
  });
}

class _CountingObserver extends TalkerObserver {
  int onLogs = 0;
  int onErrors = 0;
  int onExceptions = 0;

  int get total => onLogs + onErrors + onExceptions;

  @override
  void onLog(TalkerData log) => onLogs++;

  @override
  void onError(TalkerError err) => onErrors++;

  @override
  void onException(TalkerException err) => onExceptions++;
}
