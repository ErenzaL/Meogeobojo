import '../../../core/utils/geo.dart';

/// A place returned by Kakao Local (via the `search_restaurants` Edge
/// Function). Transient: never persisted to our database.
///
/// Kakao provides no photos, ratings, prices or hours, so this model
/// deliberately has no fields for them.
class Restaurant {
  const Restaurant({
    required this.kakaoId,
    required this.name,
    required this.categoryName,
    required this.categoryGroupCode,
    required this.address,
    required this.roadAddress,
    required this.phone,
    required this.latitude,
    required this.longitude,
    required this.distanceMeters,
    required this.placeUrl,
  });

  final String kakaoId;
  final String name;

  /// Full Kakao path, e.g. "음식점 > 한식 > 국수".
  final String categoryName;

  /// "FD6" (food) or "CE7" (cafe).
  final String categoryGroupCode;
  final String address;
  final String roadAddress;
  final String phone;
  final double latitude;
  final double longitude;

  /// Straight-line meters from the university used for the query.
  final int distanceMeters;
  final String? placeUrl;

  /// A copy with the admin-managed display fields replaced; everything else
  /// (id, Kakao category path, coordinates, distance) stays as Kakao gave it.
  Restaurant copyWith({String? name, String? roadAddress, String? phone}) =>
      Restaurant(
        kakaoId: kakaoId,
        name: name ?? this.name,
        categoryName: categoryName,
        categoryGroupCode: categoryGroupCode,
        address: address,
        roadAddress: roadAddress ?? this.roadAddress,
        phone: phone ?? this.phone,
        latitude: latitude,
        longitude: longitude,
        distanceMeters: distanceMeters,
        placeUrl: placeUrl,
      );

  /// Short tag for cards: the second path segment ("한식", "카페").
  String get categoryTag {
    final parts = categoryName.split('>').map((e) => e.trim()).toList();
    if (parts.length >= 2 && parts[1].isNotEmpty) return parts[1];
    return parts.first;
  }

  String get displayAddress => roadAddress.isNotEmpty ? roadAddress : address;

  bool get isFoodPlace =>
      categoryGroupCode == 'FD6' || categoryGroupCode == 'CE7';

  /// Parses one Kakao `documents[]` entry. [originLat]/[originLng] are used
  /// to compute distance when Kakao omits it.
  static Restaurant? fromKakao(
    Map<String, dynamic> json, {
    required double originLat,
    required double originLng,
  }) {
    final id = json['id']?.toString();
    final name = json['place_name']?.toString();
    final lat = double.tryParse('${json['y']}');
    final lng = double.tryParse('${json['x']}');
    if (id == null ||
        id.isEmpty ||
        name == null ||
        lat == null ||
        lng == null) {
      return null;
    }
    final parsed = int.tryParse('${json['distance'] ?? ''}');
    return Restaurant(
      kakaoId: id,
      name: name,
      categoryName: json['category_name']?.toString() ?? '',
      categoryGroupCode: json['category_group_code']?.toString() ?? '',
      address: json['address_name']?.toString() ?? '',
      roadAddress: json['road_address_name']?.toString() ?? '',
      phone: json['phone']?.toString() ?? '',
      latitude: lat,
      longitude: lng,
      distanceMeters:
          parsed ?? haversineMeters(originLat, originLng, lat, lng).round(),
      placeUrl: _httpsUrl(json['place_url']?.toString()),
    );
  }

  static String? _httpsUrl(String? url) {
    if (url == null || url.isEmpty) return null;
    return url.startsWith('http://') ? 'https://${url.substring(7)}' : url;
  }
}
