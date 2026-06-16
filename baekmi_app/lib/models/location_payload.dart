// 백엔드 POST /locations에 보낼 요청 본문을 표현하는 모델.
class LocationPayload {
  final String userId;
  final double latitude;
  final double longitude;
  final double? accuracy;

  const LocationPayload({
    required this.userId,
    required this.latitude,
    required this.longitude,
    this.accuracy,
  });

  Map<String, dynamic> toJson() {
    return {
      'userId': userId,
      'latitude': latitude,
      'longitude': longitude,
      if (accuracy != null) 'accuracy': accuracy,
    };
  }
}
