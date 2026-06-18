import '../models/nearby_user.dart';
import '../services/nearby_api_service.dart';
import '../services/user_id_service.dart';

/// userId를 발급받아 주변 사람 조회를 요청하는 도메인 로직.
/// ViewModel(NearbyProvider)이 "주변 사람 목록을 가져온다"는 의도만 표현하면 되도록,
/// userId 조회/조합 같은 세부사항을 여기서 감춘다.
class NearbyRepository {
  Future<List<NearbyUser>> fetchNearby({int radius = 100}) async {
    final userId = await UserIdService.getOrCreate();
    return NearbyApiService.fetchNearby(userId, radius: radius);
  }
}
