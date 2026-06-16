import 'package:geolocator/geolocator.dart';

import '../models/location_payload.dart';
import '../services/location_api_service.dart';
import '../services/user_id_service.dart';

/// Position(geolocator)을 받아 userId를 붙여 백엔드로 보내는 도메인 로직.
/// ViewModel(LocationProvider)이 "이 위치를 보고한다"는 의도만 표현하면 되도록,
/// userId 조회/조합 같은 세부사항을 여기서 감춘다.
class LocationRepository {
  Future<void> reportLocation(Position position) async {
    final userId = await UserIdService.getOrCreate();

    final payload = LocationPayload(
      userId: userId,
      latitude: position.latitude,
      longitude: position.longitude,
      accuracy: position.accuracy,
    );

    await LocationApiService.sendLocation(payload);
  }
}
