import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/nearby_user.dart';
import '../repositories/nearby_repository.dart';

/// 반경 100m 이내 사용자 목록 상태를 들고 있는 ViewModel.
/// View(MapPage)는 이 상태를 구독해 마커를 갱신하기만 하면 된다.
class NearbyProvider extends ChangeNotifier {
  final NearbyRepository _repository = NearbyRepository();
  Timer? _timer;

  List<NearbyUser> nearbyUsers = [];

  /// 즉시 1회 조회 후 5초 간격으로 폴링을 시작한다.
  /// 중복 호출 시 기존 타이머를 먼저 취소해 타이머가 누적되지 않게 한다.
  void init() {
    _timer?.cancel();
    _fetchNearby();
    _timer = Timer.periodic(const Duration(seconds: 5), (_) => _fetchNearby());
  }

  Future<void> _fetchNearby() async {
    try {
      nearbyUsers = await _repository.fetchNearby();
      notifyListeners();
    } catch (e) {
      // 조회 실패는 지도 사용을 막지 않는다. 마지막 성공 목록을 유지하고 로그만 남긴다.
      if (kDebugMode) debugPrint('[NearbyProvider] 조회 실패: $e');
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
