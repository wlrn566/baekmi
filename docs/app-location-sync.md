# 플러터 위치 데이터 연동 설계

앱(`baekmi_app`)이 추적 중인 위치를 백엔드 API(`POST /locations`)로 전송하기 위한 설계와 구현 내용을 정리한다.

## 구현 상태: 완료 (실기기 동작 검증 완료)

| 파일 | 역할 |
|------|------|
| `lib/models/location_payload.dart` | Model — `POST /locations` 요청 본문 데이터 클래스 |
| `lib/services/dio_client.dart` | Model(Service) — 앱 전체가 공유하는 Dio 싱글톤 (앱 시작 시 명시적으로 생성) |
| `lib/services/user_id_service.dart` | Model(Service) — `shared_preferences`로 userId(UUID) 발급/보관 |
| `lib/services/location_api_service.dart` | Model(Service) — `DioClient.instance`로 `POST /locations` 호출 |
| `lib/repositories/location_repository.dart` | Model(Repository) — userId + 좌표를 조합해 전송하는 도메인 로직 |
| `lib/providers/location_provider.dart` | ViewModel — 권한/위치 상태 보유, Repository 호출, 변경 통지 |
| `lib/pages/map_page.dart` | View — ViewModel을 구독해 카메라 이동/SnackBar만 처리 |
| `lib/main.dart` | `DioClient.init()` 명시적 호출 + `ChangeNotifierProvider`로 `LocationProvider` 등록 |

## 배경

- 앱은 이미 `LocationService`(`lib/services/location_service.dart`)로 현재 위치 조회/실시간 추적을 구현해뒀지만, 그 좌표를 백엔드로 보내는 코드는 없다.
- 백엔드는 `POST /locations`(Postgres+Redis dual-write), `GET /locations/:userId`(Redis 조회)를 이미 제공한다 ([docs/api-location-endpoint.md](./api-location-endpoint.md), [docs/redis-location-store.md](./redis-location-store.md)).
- 이번 범위는 **위치 전송(POST)**까지다. `GET /locations/:userId`는 "주변 사람 조회" 같은 다른 기능에서 쓰일 것이므로 앱에서 지금 호출하지 않는다 (YAGNI).

## 조사 — userId를 기기 고유 식별자로 대체할 수 있는가? → 아니다

현재 앱은 Android만 지원한다(`map_page.dart`의 `if (!Platform.isAndroid) return;`). 검토한 식별자들:

- **IMEI/시리얼번호**: Android 10(API 29) 이후 일반 앱은 접근 차단. 사용 불가.
- **광고 ID(GAID)**: 사용자가 언제든 재설정 가능하고, Google Play 정책상 광고 목적이 아닌 다른 영구 식별자와 결합 금지. 위치 추적 용도로 쓰면 정책 위반 소지.
- **`Settings.Secure.ANDROID_ID`**: 앱 재설치 후에도 유지되지만 공장 초기화 시 바뀌고 멀티유저 프로필마다 다르다. `device_info_plus`가 기본 노출하는 `id`는 이 값이 아니라 빌드 핑거프린트라 별도 패키지가 필요하다.

결론: ANDROID_ID도 "재설치/초기화 시 끊긴다"는 한계가 클라이언트 생성 UUID와 동일해서, 추가 패키지·Android 전용 분기를 감수할 이득이 없다. → **클라이언트 생성 UUID를 `shared_preferences`에 저장하는 방식을 유지한다.** 같은 이유로 `User` 테이블도 지금은 만들지 않는다 (자세한 내용은 [docs/api-location-endpoint.md](./api-location-endpoint.md)의 "사용자 식별" 섹션 참고).

## 설계 결정

### 1. 아키텍처: MVVM (Provider + ChangeNotifier)

기존 앱은 상태관리 라이브러리 없이 `StatefulWidget` + 정적 서비스 클래스로만 구성되어 있었다. 이번 기능부터 **Model / ViewModel / View**로 레이어를 분리했다.

```
lib/
├── models/        # Model — 데이터 구조
├── services/      # Model — 외부 시스템(OS API, 로컬 저장소, HTTP) 저수준 래퍼. 서로의 존재를 모름
├── repositories/  # Model — 여러 service를 조합하는 도메인 로직
├── providers/     # ViewModel — 상태 보유(ChangeNotifier), Model 호출, 변경 통지
└── pages/         # View — ViewModel을 구독해 화면만 갱신, 비즈니스 로직 없음
```

의존 방향은 항상 한쪽으로만 흐른다: `View → ViewModel → Model(Repository → Service)`. ViewModel은 `Widget`/`BuildContext`를 모르고, Service들은 서로를 모르며 Repository를 통해서만 조합된다.

### 2. HTTP 클라이언트: `dio`, 인스턴스는 `DioClient`로 분리해 앱 시작 시 명시적으로 생성

`LocationApiService`가 직접 `Dio`를 만들면, 앞으로 다른 API 서비스가 추가될 때마다 `LocationApiService`를 거쳐가거나 각자 새 `Dio`를 만들어야 해서 레이어가 어색해진다. 그래서 `lib/services/dio_client.dart`에 앱 전체가 공유하는 Dio 싱글톤을 따로 뺐다.

```dart
class DioClient {
  static late final Dio instance;

  static void init() {
    instance = Dio(BaseOptions(baseUrl: dotenv.get('API_BASE_URL')));
  }
}
```

`static final`로 첫 참조 시점에 지연 생성하지 않고, `static late final` + `init()`으로 **생성 시점을 앱 시작 시점으로 명시적으로 고정**했다. `main()`에서 `dotenv.load()` 직후 `DioClient.init()`을 호출한다 — `API_BASE_URL`을 읽기 전에 `.env`가 로드되어 있어야 하기 때문에 순서가 중요하다.

### 3. userId 저장: `shared_preferences`

앱 최초 실행 시 `uuid` 패키지로 v4 UUID를 생성해 저장하고, 이후로는 저장된 값을 재사용한다 (`UserIdService`). 인증 토큰처럼 보호가 필요한 값이 아니라 단순 익명 식별자라 암호화 저장소(`flutter_secure_storage`)까지는 필요 없다고 판단했다.

### 4. 전송 시점: 최초 1회 + 위치 스트림 이벤트마다

- 최초 위치 조회(`getCurrentPosition`) 직후 1회 전송
- 위치 스트림 이벤트가 들어올 때마다(`LocationProvider._updatePosition`) 매번 전송
- `LocationService`의 `distanceFilter: 10m`로 이벤트 자체가 이미 걸러져 있어 앱 쪽에 별도 스로틀링을 추가하지 않는다.
- **중복 전송 방지**: Android에서는 `getPositionStream()` 구독 시 첫 이벤트로 `getCurrentPosition()`과 동일한 GPS 픽스(동일 `Position.timestamp`)를 한 번 더 흘려보내는 경우가 있다(실기기 테스트에서 발견, [ISSUE-008](./issues/ISSUE-008-geolocator-stream-duplicate-first-event.md)). `distanceFilter`는 이걸 걸러내지 못해서, `LocationProvider`가 마지막으로 전송한 `timestamp`를 기억해 같은 픽스는 재전송하지 않도록 막았다.

### 5. 네트워크 실패 처리: 조용히 로그만 남김

위치 전송은 백그라운드 동기화 성격이라, 실패해도 지도 사용 자체를 막을 이유가 없다. 권한 오류(`errorMessage`로 노출해 `SnackBar` 표시)와 달리, 전송 실패는 `debugPrint`로만 로그를 남긴다.

## 구현 흐름

```
main.dart
  ├─ dotenv.load() → DioClient.init()  (Dio 싱글톤을 앱 시작 시 명시적으로 생성)
  └─ ChangeNotifierProvider(create: (_) => LocationProvider())로 앱 전체에서 공유

MapPage.initState()
  └─ context.read<LocationProvider>()로 가져와 리스너 등록 + provider.init() 호출

LocationProvider.init()                                  ← ViewModel
  ├─ LocationService.ensurePermission()                  ← Model(Service)
  ├─ LocationService.getCurrentPosition() → _updatePosition()
  └─ LocationService.getPositionStream().listen(_updatePosition)

_updatePosition(position)
  ├─ position = position; notifyListeners()               → ① View에 통지
  └─ LocationRepository.reportLocation(position)          → ② 백엔드 전송 (fire-and-forget)
        ├─ UserIdService.getOrCreate()                     ← Model(Service)
        └─ LocationApiService.sendLocation(payload)         ← Model(Service)
              └─ DioClient.instance.post(...)               ← 앱 시작 시 만들어둔 Dio 싱글톤 사용

MapPage._onLocationChanged()  (①의 notifyListeners()로 트리거)  ← View
  ├─ provider.position → _moveCamera() (지도 카메라 이동/오버레이 갱신)
  └─ provider.errorMessage → SnackBar 표시
```

화면 갱신(①)과 백엔드 전송(②)이 분리되어 있어, 전송이 느리거나 실패해도 지도 카메라 이동에는 영향이 없다.

## 핵심 코드

**`services/location_api_service.dart`** — Dio는 직접 만들지 않고 `DioClient.instance`만 사용
```dart
class LocationApiService {
  static Future<void> sendLocation(LocationPayload payload) async {
    final response = await DioClient.instance.post('/locations', data: payload.toJson());
    debugPrint('[LocationApiService] 응답(${response.statusCode}): ${response.data}');
  }
}
```

**`repositories/location_repository.dart`** — userId와 좌표를 조합하는 도메인 로직
```dart
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
```

**`providers/location_provider.dart`** — 상태 보유 + 변경 통지
```dart
class LocationProvider extends ChangeNotifier {
  final LocationRepository _locationRepository = LocationRepository();
  Position? position;
  String? errorMessage;

  void _updatePosition(Position newPosition) {
    position = newPosition;
    notifyListeners();
    _locationRepository
        .reportLocation(newPosition)
        .catchError((e) => debugPrint('위치 전송 실패: $e'));
  }
}
```

## 환경변수: `API_BASE_URL`

`.env.example`/`.env`에 추가한다.

```
API_BASE_URL=http://10.0.2.2:4001
```

**Android 에뮬레이터에서는 `localhost`가 호스트 PC를 가리키지 않는다.** `10.0.2.2`는 에뮬레이터가 호스트 PC의 로컬호스트로 접근할 때 쓰는 전용 별칭이다. 실제 기기로 테스트할 때는 PC의 LAN IP로 바꿔야 한다. 처음 겪으면 "왜 연결이 안 되지" 하고 헷갈리기 쉬운 지점이라 `docs/issues/`에 별도 이슈로도 기록할 가치가 있다.

## 다음 단계 (이번 범위 아님)

- 인증(JWT) 도입 시 `userId`를 인증된 `User.id`로 교체 ([docs/api-location-endpoint.md](./api-location-endpoint.md) 참고)
- `GET /locations/:userId` 또는 반경 검색 API를 쓰는 "주변 사람 조회" 화면
