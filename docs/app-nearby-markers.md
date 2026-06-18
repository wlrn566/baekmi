# 앱 주변 사람 마커 표시 설계

지도 위에 반경 100m 이내 사용자의 위치를 마커로 표시하기 위한 설계와 구현 내용을 정리한다.

## 구현 상태: 미구현

## 배경

- 앱은 이미 `LocationProvider` → `LocationRepository` → `POST /locations` 흐름으로 내 위치를 백엔드에 실시간 전송하고 있다 ([docs/app-location-sync.md](./app-location-sync.md)).
- 백엔드는 `GET /locations/nearby?userId=...&radius=...`로 반경 N미터 내 사용자 목록을 반환한다 ([docs/api-nearby-search.md](./api-nearby-search.md)).
- 지금까지 앱은 내 위치(파란 점, `NLocationOverlay`)만 지도에 표시했다. 이번 기능이 "주변 사람"을 처음으로 화면에 보여주는 단계다.

## 설계 결정

### 1. 폴링 기반 갱신

주변 사람 목록을 갱신하는 방법으로 두 가지를 검토했다.

| 방식 | 설명 | 단점 |
|------|------|------|
| 위치 변경 이벤트 기반 | `LocationProvider`의 위치가 바뀔 때마다 조회 | 내가 정지해 있어도 주변인이 이동해 들어오거나 나갈 수 있음 → 갱신 안 됨 |
| `Timer.periodic` | 고정 주기로 독립적으로 조회 | 없음 (단순하고 예측 가능) |

**`Timer.periodic(5초)`를 선택한다.** 내 위치 변경 여부와 무관하게 주변 상태를 능동적으로 갱신할 수 있고, Redis Cron이 30초마다 만료된 위치를 정리하므로 5초면 충분히 실시간에 가깝다.

### 2. 마커 관리: 전체 교체 방식

갱신마다 마커를 관리하는 방법으로 두 가지를 검토했다.

| 방식 | 설명 | 단점 |
|------|------|------|
| diff 방식 | 이전 목록과 비교해 추가/수정/삭제를 선별 | 구현 복잡도가 높음 |
| 전체 교체 | 기존 마커 전체 삭제 후 새 목록으로 재생성 | 없음 (반경 100m 내 인원이 많지 않아 비용 무시 가능) |

**전체 교체를 선택한다.** `controller.clearOverlays(type: NOverlayType.marker)`는 `NMarker` 타입만 제거하므로 내 위치를 표시하는 `NLocationOverlay`(`locationOverlay` 타입)는 영향받지 않는다.

### 3. NearbyProvider는 LocationProvider와 독립

`NearbyProvider`는 `LocationProvider`를 직접 의존하지 않는다. userId는 `NearbyRepository` 내부에서 `UserIdService.getOrCreate()`로 직접 가져온다. 두 Provider가 서로를 모르는 구조가 단방향 의존성을 유지한다.

### 4. 에러 처리: 조용히 로그만

주변 사람 조회 실패는 지도 사용 자체를 막을 이유가 없다. 위치 전송 실패(`LocationProvider._updatePosition`)와 동일하게 `debugPrint`로만 로그를 남기고, 마지막으로 조회 성공한 목록을 그대로 유지한다.

## 구현 구조

```
lib/
├── models/
│   └── nearby_user.dart            # (신규) NearbyUser 데이터 클래스
├── services/
│   └── nearby_api_service.dart     # (신규) GET /locations/nearby 호출
├── repositories/
│   └── nearby_repository.dart      # (신규) UserIdService + NearbyApiService 조합
├── providers/
│   └── nearby_provider.dart        # (신규) 주변 사람 상태 보유 + 폴링
├── pages/
│   └── map_page.dart               # (수정) NearbyProvider 구독 + 마커 렌더링
└── main.dart                       # (수정) MultiProvider로 NearbyProvider 등록
```

## 구현 흐름

```
main.dart
  └─ MultiProvider
       ├─ LocationProvider          (기존)
       └─ NearbyProvider            (신규)

MapPage.initState()
  ├─ context.read<LocationProvider>()..addListener(_onLocationChanged)  (기존)
  └─ context.read<NearbyProvider>()..addListener(_onNearbyUsersChanged) (신규)
       └─ provider.init()

NearbyProvider.init()                                ← ViewModel
  ├─ fetchNearby() 즉시 1회 호출
  └─ Timer.periodic(5초) 시작 → 매 5초마다 fetchNearby()

NearbyProvider.fetchNearby()
  └─ NearbyRepository.fetchNearby()                 ← Model
       ├─ UserIdService.getOrCreate()                ← Model(Service)
       └─ NearbyApiService.fetchNearby(userId)       ← Model(Service)
            └─ DioClient.instance.get('/locations/nearby?userId=...&radius=100')
  ├─ 성공: nearbyUsers = result; notifyListeners()   → View에 통지
  └─ 실패: debugPrint만 (마지막 성공 목록 유지)

MapPage._onNearbyUsersChanged()  (notifyListeners()로 트리거)  ← View
  ├─ _mapController == null → return (지도 미준비, 다음 폴링에서 처리)
  ├─ controller.clearOverlays(type: NOverlayType.marker)
  └─ controller.addOverlayAll(
         nearbyUsers.map((u) => NMarker(
           id: u.userId,
           position: NLatLng(u.latitude, u.longitude),
         )).toSet()
       )
```

## 핵심 코드 스케치

**`models/nearby_user.dart`**
```dart
class NearbyUser {
  final String userId;
  final double latitude;
  final double longitude;
  final double distance;

  const NearbyUser({
    required this.userId,
    required this.latitude,
    required this.longitude,
    required this.distance,
  });

  factory NearbyUser.fromJson(Map<String, dynamic> json) => NearbyUser(
        userId: json['userId'] as String,
        latitude: (json['latitude'] as num).toDouble(),
        longitude: (json['longitude'] as num).toDouble(),
        distance: (json['distance'] as num).toDouble(),
      );
}
```

**`services/nearby_api_service.dart`**
```dart
class NearbyApiService {
  static Future<List<NearbyUser>> fetchNearby(String userId, {int radius = 100}) async {
    final response = await DioClient.instance.get(
      '/locations/nearby',
      queryParameters: {'userId': userId, 'radius': radius},
    );
    final List<dynamic> data = response.data['data'] as List<dynamic>;
    return data.map((e) => NearbyUser.fromJson(e as Map<String, dynamic>)).toList();
  }
}
```

**`providers/nearby_provider.dart`**
```dart
class NearbyProvider extends ChangeNotifier {
  final NearbyRepository _repository = NearbyRepository();
  Timer? _timer;

  List<NearbyUser> nearbyUsers = [];

  void init() {
    _fetchNearby();
    _timer = Timer.periodic(const Duration(seconds: 5), (_) => _fetchNearby());
  }

  Future<void> _fetchNearby() async {
    try {
      nearbyUsers = await _repository.fetchNearby();
      notifyListeners();
    } catch (e) {
      if (kDebugMode) debugPrint('[NearbyProvider] 조회 실패: $e');
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
```

**`pages/map_page.dart` — 추가되는 부분**
```dart
// initState에서 추가
_nearbyProvider = context.read<NearbyProvider>()..addListener(_onNearbyUsersChanged);
_nearbyProvider.init();

// 새 콜백
void _onNearbyUsersChanged() {
  if (_mapController == null) return;
  _mapController!.clearOverlays(type: NOverlayType.marker);
  final markers = _nearbyProvider.nearbyUsers.map((u) =>
    NMarker(id: u.userId, position: NLatLng(u.latitude, u.longitude))
  ).toSet();
  if (markers.isNotEmpty) _mapController!.addOverlayAll(markers);
}

// dispose에서 추가
_nearbyProvider.removeListener(_onNearbyUsersChanged);
```

## 다음 단계 (이번 범위 아님)

- 마커 탭 시 거리·userId 등 정보 표시 (말풍선/BottomSheet)
- 마커 커스텀 이미지 (기본 빨간 핀 → 사람 아이콘 등)
- 인증 도입 시 userId를 인증된 식별자로 교체 ([docs/api-location-endpoint.md](./api-location-endpoint.md) 참고)
