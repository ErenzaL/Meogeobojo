import 'package:flutter/foundation.dart' show kIsWeb;

import '../models/restaurant.dart';

/// Where the website lives, for links shared from the phone apps.
const kSiteUrl = 'https://meogeobojo.onrender.com/';

/// A restaurant's own address in the app: `/restaurant/<kakao id>?name=…`.
/// The name only helps find the place again; nothing about the sender (their
/// start point, their account) is ever in it.
String restaurantPath(Restaurant r) => Uri(
  path: '/restaurant/${r.kakaoId}',
  queryParameters: {'name': r.name},
).toString();

/// The place a route names, or null when it is not a restaurant link.
({String id, String? name})? restaurantLinkOf(String? route) {
  if (route == null) return null;
  final uri = Uri.tryParse(route);
  if (uri == null) return null;
  final parts = uri.pathSegments.where((s) => s.isNotEmpty).toList();
  if (parts.length != 2 || parts.first != 'restaurant') return null;
  final id = parts[1];
  if (!RegExp(r'^\d{1,20}$').hasMatch(id)) return null; // Kakao ids are digits
  final name = uri.queryParameters['name']?.trim();
  return (id: id, name: (name == null || name.isEmpty) ? null : name);
}

/// The place on Naver Map. Naver knows no Kakao place ids, so it is a search
/// for the name near the city in its address ("충남 아산시 국수집").
Uri naverMapUrl(Restaurant r) {
  final area = (r.roadAddress.isNotEmpty ? r.roadAddress : r.address)
      .split(' ')
      .take(2)
      .join(' ');
  return Uri.https('map.naver.com', '/p/search/${'$area ${r.name}'.trim()}');
}

/// The full link to share: this site's address (on the phone apps, the
/// public website) with the restaurant's path after `#`.
String restaurantShareUrl(Restaurant r) {
  final base = kIsWeb
      ? '${Uri.base.scheme}://${Uri.base.authority}${Uri.base.path}'
      : kSiteUrl;
  return '$base#${restaurantPath(r)}';
}
