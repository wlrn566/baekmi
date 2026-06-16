import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import '../repositories/location_repository.dart';
import '../services/location_service.dart';

/// 위치 권한/조회/추적 상태를 들고 있는 ViewModel.
/// View(MapPage)는 이 상태를 구독해 카메라를 움직이고 에러를 보여주기만 하면 된다.
class LocationProvider extends ChangeNotifier {
  final LocationRepository _locationRepository = LocationRepository();
  StreamSubscription<Position>? _positionSubscription;

  Position? position;
  String? errorMessage;

  // getCurrentPosition()으로 1회 조회한 직후 getPositionStream()을 구독하면,
  // Android에서는 스트림의 첫 이벤트로 같은 GPS 픽스(동일 timestamp)를 한 번 더 흘려보내는 경우가 있다.
  // distanceFilter는 "이전 이벤트와의 거리"만 보기 때문에 이 중복은 걸러지지 않으므로 별도로 막는다.
  DateTime? _lastReportedAt;

  /// 권한 확인 → 현재 위치로 1회 갱신 → 실시간 추적 시작 순으로 초기화한다.
  /// iOS는 Info.plist 설정이 없어 위치 기능 미지원 — Android에서만 실행한다.
  Future<void> init() async {
    if (!Platform.isAndroid) return;
    try {
      await LocationService.ensurePermission();

      final current = await LocationService.getCurrentPosition();
      _updatePosition(current);

      _positionSubscription = LocationService.getPositionStream().listen(_updatePosition);
    } catch (e) {
      // e.toString()은 "Exception: ..." 형태이므로 프리픽스를 제거해 View에 노출
      errorMessage = e.toString().replaceFirst('Exception: ', '');
      notifyListeners();
    }
  }

  void _updatePosition(Position newPosition) {
    position = newPosition;
    notifyListeners();

    // 같은 GPS 픽스(timestamp 동일)가 중복으로 들어온 경우 전송을 건너뛴다.
    if (newPosition.timestamp == _lastReportedAt) {
      debugPrint('[LocationProvider] 중복 위치 이벤트 무시: ${newPosition.timestamp}');
      return;
    }
    _lastReportedAt = newPosition.timestamp;

    // 위치 전송은 백그라운드 동기화 성격이라 실패해도 지도 사용을 막지 않는다.
    // 권한 오류 같은 사용자 조치가 필요한 에러가 아니므로 errorMessage로 노출하지 않고 로그만 남긴다.
    _locationRepository
      .reportLocation(newPosition)
      .catchError((e) => debugPrint('위치 전송 실패: $e'));
  }

  @override
  void dispose() {
    _positionSubscription?.cancel();
    super.dispose();
  }
}
