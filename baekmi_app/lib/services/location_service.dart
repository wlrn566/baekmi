import 'package:geolocator/geolocator.dart';

/// 위치 권한 요청 및 위치 데이터 조회를 담당하는 서비스.
/// geolocator 패키지를 래핑해 앱 전반에서 일관된 위치 설정을 사용할 수 있도록 한다.
class LocationService {
  // distanceFilter: 10m 이상 이동했을 때만 스트림 이벤트 발생
  // 너무 작으면 미세한 GPS 오차로도 이벤트가 계속 발생해 배터리 소모
  static const _locationSettings = LocationSettings(
    accuracy: LocationAccuracy.high,
    distanceFilter: 10,
  );

  /// 위치 서비스 활성화 여부와 권한을 확인하고 필요시 권한을 요청한다.
  /// 사용 불가능한 경우 예외를 던지므로 호출 측에서 try-catch 처리가 필요하다.
  static Future<void> ensurePermission() async {
    // GPS/네트워크 위치 서비스 자체가 꺼져 있는 경우 (기기 설정 문제)
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw Exception('위치 서비스가 비활성화되어 있습니다.');
    }

    LocationPermission permission = await Geolocator.checkPermission();

    // 아직 권한 요청을 한 번도 하지 않은 상태 → 시스템 다이얼로그 표시
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        throw Exception('위치 권한이 거부되었습니다.');
      }
    }

    // 사용자가 "다시 묻지 않음"으로 거부한 경우 → 앱 내에서 재요청 불가, 설정 앱으로 유도해야 함
    if (permission == LocationPermission.deniedForever) {
      throw Exception('위치 권한이 영구적으로 거부되었습니다. 설정에서 허용해 주세요.');
    }
  }

  /// 현재 위치를 1회 반환한다.
  /// 앱 실행 시 지도 초기 카메라 위치를 설정하는 용도로 사용한다.
  static Future<Position> getCurrentPosition() {
    return Geolocator.getCurrentPosition(
      locationSettings: _locationSettings,
    );
  }

  /// 실시간 위치 변화를 스트림으로 반환한다.
  /// distanceFilter 설정에 따라 10m 이상 이동 시에만 이벤트가 발생한다.
  static Stream<Position> getPositionStream() {
    return Geolocator.getPositionStream(
      locationSettings: _locationSettings,
    );
  }
}
