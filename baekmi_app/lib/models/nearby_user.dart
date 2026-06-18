// 백엔드 GET /locations/nearby 응답의 개별 사용자 항목을 표현하는 모델.
class NearbyUser {
  final String userId;
  final double latitude;
  final double longitude;
  final double distance;

  const NearbyUser({
    required this.userId,
    required this.latitude,
    required this.longitude,
    required this.distance,
  });

  factory NearbyUser.fromJson(Map<String, dynamic> json) => NearbyUser(
    userId: json['userId'] as String,
    latitude: (json['latitude'] as num).toDouble(),
    longitude: (json['longitude'] as num).toDouble(),
    distance: (json['distance'] as num).toDouble(),
  );
}
