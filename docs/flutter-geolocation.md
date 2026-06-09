# Flutter Geolocation 구현 가이드

## 패키지

- [geolocator](https://pub.dev/packages/geolocator) ^14.0.2

**요구사항**
- Android: minSdk 23 이상 (`android/app/build.gradle.kts`에서 `minSdk = 23` 명시 필요)
- iOS: 추후 지원 예정

> 현재 Android 전용으로 구현하며 iOS 설정은 추후 진행 예정이다.

---

## 구현 목표

1. **앱 실행 시 현재 위치 1회 수신** — 지도 카메라를 현재 위치로 이동
2. **실시간 위치 추적** — 이동 시 지도 카메라가 따라감

---

## 1. 패키지 설치

`pubspec.yaml`에 `geolocator` 추가 후 `flutter pub get`

---

## 2. Android 권한 설정

`android/app/src/main/AndroidManifest.xml`에 추가:

- `ACCESS_FINE_LOCATION` — GPS 기반 정밀 위치 (100m 이내 서비스에 필요)
- `ACCESS_COARSE_LOCATION` — 네트워크 기반 대략적 위치

---

## 3. 구현 구조

```
lib/
├── main.dart
├── pages/
│   └── map_page.dart         # StatefulWidget으로 변경, 위치 로직 포함
└── services/
    └── location_service.dart  # 위치 권한 요청 및 위치 조회 담당
```

---

## 4. LocationService

`lib/services/location_service.dart`에 아래 기능을 구현한다:

- 위치 서비스 활성화 여부 확인
- 위치 권한 요청 (거부 / 영구 거부 케이스 처리)
- 현재 위치 1회 반환 (`getCurrentPosition`)
- 실시간 위치 스트림 반환 (`getPositionStream`, `distanceFilter: 10m`)

---

## 5. MapPage

`StatelessWidget` → `StatefulWidget`으로 변경 후:

- `initState`: `LocationService`로 권한 확인 → 현재 위치로 카메라 이동 → 실시간 스트림 구독
- 위치 업데이트 시 `NaverMapController`로 카메라 이동
- `dispose`: 스트림 구독 해제

권한 거부 등 에러 발생 시 `SnackBar`로 사용자에게 안내한다.

---

## 6. 실행 확인

1. 권한 요청 다이얼로그 노출 확인
2. 지도가 현재 위치로 카메라 이동하는지 확인
3. 이동 시 지도 카메라가 따라가는지 확인
   - 에뮬레이터: Extended Controls → Location에서 위치 변경으로 테스트
