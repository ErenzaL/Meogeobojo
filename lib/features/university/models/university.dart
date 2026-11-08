class University {
  const University({
    required this.id,
    required this.nameKo,
    this.nameEn,
    this.city,
    required this.latitude,
    required this.longitude,
  });

  final String id;
  final String nameKo;
  final String? nameEn;
  final String? city;
  final double latitude;
  final double longitude;

  factory University.fromJson(Map<String, dynamic> json) => University(
    id: json['id'] as String,
    nameKo: json['name_ko'] as String,
    nameEn: json['name_en'] as String?,
    city: json['city'] as String?,
    latitude: (json['latitude'] as num).toDouble(),
    longitude: (json['longitude'] as num).toDouble(),
  );

  @override
  bool operator ==(Object other) => other is University && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
