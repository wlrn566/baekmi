# [ISSUE-008] geolocator 스트림 구독 시 첫 이벤트로 동일 GPS 픽스 중복 수신

**발생 시점:** 2026/06/16 (실기기 위치 전송 연동 테스트 중)
**분류:** Flutter

## 증상

- 앱 실행 시 `LocationApiService`의 `POST /locations` 요청 로그가 똑같은 좌표/정확도로 거의 동시에 두 번 찍힘
- 두 요청의 `latitude`, `longitude`, `accuracy`가 완전히 동일

## 원인

- `LocationProvider.init()`이 `LocationService.getCurrentPosition()`으로 1회 조회한 직후 `LocationService.getPositionStream()`을 구독함
- Android에서는 스트림을 구독하는 순간, 마지막으로 캐시된 GPS 픽스를 첫 이벤트로 즉시 한 번 더 흘려보내는 경우가 있음 — `getCurrentPosition()`이 받은 것과 **동일한 `Position.timestamp`**를 가진 픽스가 스트림의 첫 이벤트로 다시 들어옴
- `LocationSettings.distanceFilter`는 "이전에 전달한 이벤트와의 거리"만 기준으로 걸러내므로, 이 중복은 distanceFilter로 막히지 않음

## 원인 흐름

```
getCurrentPosition() → Position(timestamp: T) 수신 → _updatePosition() → 백엔드 전송
        ↓
getPositionStream() 구독 시작
        ↓
스트림 첫 이벤트로 캐시된 동일 Position(timestamp: T) 재전달 → _updatePosition() → 백엔드 중복 전송
```

## 해결책

`Position.timestamp`로 "이미 보고한 GPS 픽스인지"를 구분해, 같은 timestamp의 위치가 다시 들어오면 백엔드 전송을 건너뛴다. 카메라 이동(`notifyListeners()`)은 중복이어도 무해하므로 그대로 둔다.

```dart
// lib/providers/location_provider.dart
DateTime? _lastReportedAt;

void _updatePosition(Position newPosition) {
  position = newPosition;
  notifyListeners();

  if (newPosition.timestamp == _lastReportedAt) return; // 중복 픽스 무시
  _lastReportedAt = newPosition.timestamp;

  _locationRepository.reportLocation(newPosition).catchError((e) => debugPrint('위치 전송 실패: $e'));
}
```
