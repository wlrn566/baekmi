import 'package:flutter/foundation.dart';

import '../models/location_payload.dart';
import 'dio_client.dart';

/// 백엔드 POST /locations 호출만 담당하는 저수준 API 클라이언트.
/// userId 발급/조합 같은 도메인 로직은 LocationRepository에서 처리한다.
/// Dio 인스턴스는 직접 만들지 않고 DioClient(앱 전체 공유 싱글톤)에서 가져온다.
class LocationApiService {
  static Future<void> sendLocation(LocationPayload payload) async {
    final body = payload.toJson();
    debugPrint('[LocationApiService] POST /locations 요청: $body');

    final response = await DioClient.instance.post('/locations', data: body);
    debugPrint('[LocationApiService] 응답(${response.statusCode}): ${response.data}');
  }
}
