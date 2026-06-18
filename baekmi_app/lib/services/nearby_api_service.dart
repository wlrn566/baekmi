import 'package:flutter/foundation.dart';

import '../models/nearby_user.dart';
import 'dio_client.dart';

/// 백엔드 GET /locations/nearby 호출만 담당하는 저수준 API 클라이언트.
/// userId 발급 같은 도메인 로직은 NearbyRepository에서 처리한다.
class NearbyApiService {
  static Future<List<NearbyUser>> fetchNearby(String userId, { int radius = 100 }) async {
    if (kDebugMode) {
      debugPrint('[NearbyApiService] GET /locations/nearby userId=$userId radius=$radius');
    }

    final response = await DioClient.instance.get(
      '/locations/nearby',
      queryParameters: {'userId': userId, 'radius': radius},
    );

    if (kDebugMode) {
      debugPrint('[NearbyApiService] 응답(${response.statusCode}): ${response.data}');
    }

    final List<dynamic> data = response.data['data'] as List<dynamic>;
    return data.map((e) => NearbyUser.fromJson(e as Map<String, dynamic>)).toList();
  }
}
