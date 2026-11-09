import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/l10n/l10n.dart';
import '../models/restaurant.dart';

/// Opens Kakao Map walking directions from ([fromName], [fromLat], [fromLng])
/// to [to]. Uses Kakao's public `map.kakao.com/link/by/walk` URL, which hands
/// off to the Kakao Map app when it is installed and the web map otherwise.
Future<void> openDirections(
  BuildContext context, {
  required Restaurant to,
  required String fromName,
  required double fromLat,
  required double fromLng,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final failed = context.l10n.restaurantLinkOpenFailed;
  String enc(String s) => Uri.encodeComponent(s.replaceAll(',', ' '));
  final uri = Uri.parse(
    'https://map.kakao.com/link/by/walk/'
    '${enc(fromName)},$fromLat,$fromLng/'
    '${enc(to.name)},${to.latitude},${to.longitude}',
  );
  try {
    if (await launchUrl(uri, mode: LaunchMode.externalApplication)) return;
  } catch (_) {}
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(failed)));
}
