import 'dart:io';

import 'package:code_scout/code_scout.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Dart cannot read its own pubspec at runtime, so the version exists twice:
  // once where pub.dev reads it and once where the code does. Two copies of a
  // number drift, and this one drifts silently, because nothing else in the SDK
  // ever compares them. The dashboard would go on reporting the version of
  // whatever release last remembered to update the constant.
  test('codeScoutSdkVersion matches pubspec.yaml', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();

    final match = RegExp(r'^version:\s*(\S+)\s*$', multiLine: true)
        .firstMatch(pubspec);
    expect(match, isNotNull, reason: 'pubspec.yaml has no version: line');

    expect(
      codeScoutSdkVersion,
      match!.group(1),
      reason: 'bump lib/src/version.dart in the same commit as pubspec.yaml',
    );
  });

  // It goes on the wire, where the server stores it in a varchar(64) and the
  // dashboard puts it in a table column. Something shaped like a version keeps
  // both of those honest.
  test('codeScoutSdkVersion looks like a version', () {
    expect(codeScoutSdkVersion, matches(RegExp(r'^\d+\.\d+\.\d+')));
    expect(codeScoutSdkVersion.length, lessThan(64));
  });
}
