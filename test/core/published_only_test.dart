import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Students read only PUBLISHED content. Drafts, scheduled snapshots and version
/// history live in tables the app must never touch (admins-only by RLS); the app
/// keeps reading the live tables, which change only when something is published.
void main() {
  test('the app never reads the publishing tables', () {
    const forbidden = [
      'content_drafts',
      'content_versions',
      'publication_jobs',
    ];
    final hits = <String>[];
    for (final f in Directory(
      'lib',
    ).listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.dart')) continue;
      final text = f.readAsStringSync();
      for (final name in forbidden) {
        if (text.contains(name)) hits.add('${f.path}: $name');
      }
    }
    expect(
      hits,
      isEmpty,
      reason: 'student code must not read drafts or history',
    );
  });

  test('the app has no code path that writes restaurant content', () {
    final hits = <String>[];
    for (final f in Directory(
      'lib',
    ).listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.dart')) continue;
      final text = f.readAsStringSync();
      if (RegExp(
        r"from\('restaurant_overrides'\)\s*\.\s*(insert|update|upsert|delete)",
      ).hasMatch(text)) {
        hits.add(f.path);
      }
    }
    expect(hits, isEmpty);
  });
}
