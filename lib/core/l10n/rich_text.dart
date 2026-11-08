import 'package:flutter/painting.dart';

/// Splits a localized sentence around a single dynamic value so that the
/// value can be styled (e.g. the university name in the Home hero) without
/// concatenating strings: word order stays the translator's decision.
///
/// [template] is the ARB message formatted with [marker] in place of the value.
List<InlineSpan> highlightPlaceholder(
  String Function(String marker) template,
  String value,
  TextStyle style,
) {
  const marker = '\u0001';
  final parts = template(marker).split(marker);
  if (parts.length != 2) return [TextSpan(text: template(value))];
  return [
    if (parts[0].isNotEmpty) TextSpan(text: parts[0]),
    TextSpan(text: value, style: style),
    if (parts[1].isNotEmpty) TextSpan(text: parts[1]),
  ];
}
