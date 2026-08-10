import 'package:code_scout/code_scout.dart';
import 'package:code_scout/src/csx_interface/log_clipboard.dart';
import 'package:code_scout/src/csx_interface/menu.dart';
import 'package:code_scout/src/csx_interface/overlay_theme.dart';
import 'package:code_scout/src/csx_interface/overlay_widgets.dart';
import 'package:code_scout/src/utils/stack_trace_parser.dart';
import 'package:flutter/material.dart';

/// One log, opened.
///
/// What shipped before printed `metadata.toString()`, a raw Dart map on one
/// unwrapped line, and the stack trace as a single joined string. Both are
/// structured here, and every section copies on its own.
class LogDetail extends StatelessWidget {
  const LogDetail({super.key, required this.entry});

  final LogEntry entry;

  @override
  Widget build(BuildContext context) {
    final colour = levelColor(entry.level.name);
    final metadata = entry.metadata;
    final frames = entry.stackCallDetails ?? const <StackCallDetails>[];
    final tags = entry.tags ?? const <String>{};

    return Column(
      children: [
        PushedHeader(
          title: _title(entry.level.name),
          actions: [
            CSxIconButton(
              icon: Icons.copy_all_outlined,
              tooltip: 'Copy everything',
              onPressed: () => copyAndTell(
                context,
                formatLogForClipboard(
                  entry,
                  session: CodeScout.instance.currentSession,
                  sessionId: CodeScout.instance.currentSessionId,
                ),
                _title(entry.level.name),
              ),
            ),
            CSxIconButton(
              icon: Icons.close,
              tooltip: 'Close',
              onPressed: () => Navigator.of(context).maybePop(),
            ),
          ],
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.only(bottom: 20),
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        CSxBadge(text: entry.level.name, colour: colour),
                        const SizedBox(width: 8),
                        Text(
                          _stamp(entry.timestamp),
                          style: mono.copyWith(color: CSxColors.muted, fontSize: 10.5),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    SelectableText(
                      entry.message,
                      style: TextStyle(
                        color: entry.level.value >= LogLevel.error.value
                            ? CSxColors.error
                            : CSxColors.white,
                        fontSize: 13.5,
                        height: 1.45,
                      ),
                    ),
                  ],
                ),
              ),
              if (entry.error != null) ...[
                CSxSectionHeader(
                  title: 'Error',
                  trailing: CSxSmallButton(
                    label: 'Copy',
                    onTap: () => copyAndTell(context, entry.error.toString(), 'Error'),
                  ),
                ),
                CSxCode(text: entry.error.toString()),
              ],
              if (frames.isNotEmpty) ...[
                CSxSectionHeader(
                  title: 'Stack trace',
                  trailing: CSxSmallButton(
                    label: 'Copy',
                    onTap: () => copyAndTell(
                      context,
                      (entry.formattedStackTrace ?? const []).join('\n'),
                      'Stack trace',
                    ),
                  ),
                ),
                _Frames(frames: frames),
              ],
              if (metadata != null && metadata.isNotEmpty) ...[
                CSxSectionHeader(
                  title: 'Metadata',
                  trailing: CSxSmallButton(
                    label: isFlatMap(metadata) ? 'Copy' : 'Copy JSON',
                    onTap: () => copyAndTell(context, prettyJson(metadata), 'Metadata'),
                  ),
                ),
                // Rows when every value is a scalar, indented JSON otherwise.
                if (isFlatMap(metadata))
                  CSxKeyValue(
                    rows: [
                      for (final e in metadata.entries)
                        (e.key, _scalar(e.value), _scalarColour(e.value)),
                    ],
                  )
                else
                  CSxCode(text: prettyJson(metadata)),
              ],
              if (tags.isNotEmpty) ...[
                const CSxSectionHeader(title: 'Tags'),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final tag in tags)
                        CSxChip(label: tag, state: ChipState.neutral, onTap: () {}),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  static String _title(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  static String _scalar(Object? v) => v == null
      ? 'null'
      : v is String
          ? '"$v"'
          : '$v';

  static Color? _scalarColour(Object? v) => v == null
      ? CSxColors.muted
      : v is num
          ? CSxColors.info
          : v is String
              ? CSxColors.debug
              : null;

  static String _stamp(DateTime? at) {
    if (at == null) return '';
    final local = at.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    final ms = local.millisecond.toString().padLeft(3, '0');
    return '${two(local.hour)}:${two(local.minute)}:${two(local.second)}.$ms';
  }
}

/// Frames, with the app's own tinted and listed first.
///
/// The one you want is never the top one: four frames in five in a Flutter
/// trace are the framework. Tinting is not the only cue, since the app frames
/// are also the ones with a path you recognise.
class _Frames extends StatelessWidget {
  const _Frames({required this.frames});

  final List<StackCallDetails> frames;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: CSxColors.card,
        border: Border.all(color: CSxColors.border),
        borderRadius: BorderRadius.circular(8),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < frames.length; i++) _frame(frames[i], last: i == frames.length - 1),
        ],
      ),
    );
  }

  Widget _frame(StackCallDetails frame, {required bool last}) {
    final path = frame.path ?? '';
    // Paths arrive with `package:` already stripped by the parser, and a
    // `dart:` frame never matches its regex, so Flutter's own prefix is the
    // only one left to recognise.
    final isApp = path.isNotEmpty && !path.startsWith('flutter/');

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: isApp ? CSxColors.primary.withValues(alpha: 0.07) : null,
        border: last ? null : const Border(bottom: BorderSide(color: CSxColors.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            frame.method ?? '?',
            style: mono.copyWith(
              color: CSxColors.white,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (path.isNotEmpty)
            Text(
              '$path:${frame.line ?? 0}:${frame.column ?? 0}',
              style: mono.copyWith(color: CSxColors.muted, fontSize: 11),
            ),
        ],
      ),
    );
  }
}
