# 앱 주변 사람 마커 표시 설계

지도 위에 반경 100m 이내 사용자의 위치를 마커로 표시하기 위한 설계와 구현 내용을 정리한다.

## 구현 상태: 완료

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
  ├─ context.read<LocationProvider>()..addListener(_onLocationChanged)   (기존)
  └─ context.read<NearbyProvider>()..addListener(_nearbyUsersListener)   (신규)
       └─ provider.init()

NearbyProvider.init()                                ← ViewModel
  ├─ 기존 타이머 취소 (중복 호출 방어)
  ├─ fetchNearby() 즉시 1회 호출
  └─ Timer.periodic(5초) 시작 → 매 5초마다 fetchNearby()

NearbyProvider.fetchNearby()
  ├─ _isFetching == true → return (동시 요청 차단, 응답 순서 역전 방지)
  └─ NearbyRepository.fetchNearby()                 ← Model
       ├─ UserIdService.getOrCreate()                ← Model(Service)
       └─ NearbyApiService.fetchNearby(userId)       ← Model(Service)
            └─ DioClient.instance.get('/locations/nearby?userId=...&radius=100')
  ├─ 성공: nearbyUsers = result; notifyListeners()   → View에 통지
  └─ 실패: debugPrint만 (마지막 성공 목록 유지)

MapPage._nearbyUsersListener()  (VoidCallback 래퍼 — addListener 타입 요구사항)
  └─ _onNearbyUsersChanged() 호출

MapPage._onNearbyUsersChanged()  (notifyListeners()로 트리거)  ← View
  ├─ _mapController == null → return (지도 미준비, 다음 폴링에서 처리)
  ├─ nearbyUsers 비어있으면 → clearOverlays 후 return
  ├─ _markerIcon ??= NOverlayImage.fromWidget(...) await  (최초 1회만 래스터라이즈, 이후 캐시 재사용)
  ├─ controller.clearOverlays(type: NOverlayType.marker)  (await 이후에 clear → 깜빡임 방지)
  └─ controller.addOverlayAll(
         nearbyUsers.map((u) => NMarker(...)..setIcon(_markerIcon!)).toSet()
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
  bool _isFetching = false;

  List<NearbyUser> nearbyUsers = [];

  void init() {
    _timer?.cancel(); // 중복 호출 시 기존 타이머 취소
    _fetchNearby();
    _timer = Timer.periodic(const Duration(seconds: 5), (_) => _fetchNearby());
  }

  Future<void> _fetchNearby() async {
    if (_isFetching) return; // 동시 요청 차단
    _isFetching = true;
    try {
      nearbyUsers = await _repository.fetchNearby();
      notifyListeners();
    } catch (e) {
      if (kDebugMode) debugPrint('[NearbyProvider] 조회 실패: $e');
    } finally {
      _isFetching = false;
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
NOverlayImage? _markerIcon; // 최초 1회만 래스터라이즈, 이후 재사용

// initState에서 추가
// addListener는 VoidCallback을 기대하므로 async 메서드를 직접 넘기지 않는다.
_nearbyProvider = context.read<NearbyProvider>()..addListener(_nearbyUsersListener);
_nearbyProvider.init();

// VoidCallback 래퍼
void _nearbyUsersListener() => _onNearbyUsersChanged();

// 새 콜백
Future<void> _onNearbyUsersChanged() async {
  if (_mapController == null) return;
  if (_nearbyProvider.nearbyUsers.isEmpty) {
    _mapController!.clearOverlays(type: NOverlayType.marker);
    return;
  }
  _markerIcon ??= await NOverlayImage.fromWidget(...);
  if (!mounted) return;
  final markers = _nearbyProvider.nearbyUsers
      .map((u) => NMarker(id: u.userId, position: NLatLng(u.latitude, u.longitude))..setIcon(_markerIcon!))
      .toSet();
  _mapController!.clearOverlays(type: NOverlayType.marker); // await 이후 clear → 깜빡임 방지
  _mapController!.addOverlayAll(markers);
}

// dispose에서 추가
_nearbyProvider.removeListener(_nearbyUsersListener);
```

## 테스트 데이터 삽입

실제로 주변에 다른 사용자가 없을 때 `POST /locations`로 가짜 데이터를 직접 삽입해 마커를 확인할 수 있다.

### 100m 이내 좌표 계산법

위도/경도 1도가 실제 거리로 환산되는 값을 이용한다.

```
위도 1° ≈ 111,000m  →  1m ≈ 0.000009°
경도 1° ≈ 111,000 × cos(위도) m
         (위도 37.5° 기준: 1° ≈ 88,000m)  →  1m ≈ 0.0000114°
```

**오프셋 기준표 (위도 37.5° 근처)**

| 거리 | 위도 오프셋 | 경도 오프셋 |
|------|------------|------------|
| 50m  | ±0.00045° | ±0.00057° |
| 100m | ±0.00090° | ±0.00114° |
| 200m | ±0.00180° | ±0.00228° |

100m 이내로 넣으려면 위도 오프셋을 `±0.00090` 미만, 경도 오프셋을 `±0.00114` 미만으로 설정한다.

### 주의사항

`GET /locations/nearby`는 `GEOSEARCH FROMMEMBER`를 사용하므로 **내 userId도 Redis에 있어야** 조회가 동작한다. 앱이 5분 이상 정지 상태이면 내 위치가 Redis TTL(300초)로 만료된다. 이 경우 내 위치도 함께 삽입해야 한다.

### 삽입 예시

내 위치가 `latitude: 37.5235634, longitude: 126.8992467`일 때:

```bash
# Git Bash / macOS Terminal 에서 실행

# 내 위치 (앱이 전송 중이면 생략 가능)
curl -X POST http://localhost:4001/locations \
  -H "Content-Type: application/json" \
  -d '{"userId":"<내-userId>","latitude":37.5235634,"longitude":126.8992467,"accuracy":20.0}'

# 100m 이내 — 북쪽 약 44m (위도 +0.00040)
curl -X POST http://localhost:4001/locations \
  -H "Content-Type: application/json" \
  -d '{"userId":"aaaaaaaa-aaaa-4aaa-aaaa-aaaaaaaaaaaa","latitude":37.5239634,"longitude":126.8992467,"accuracy":5.0}'

# 100m 이내 — 동쪽 약 44m (경도 +0.00050)
curl -X POST http://localhost:4001/locations \
  -H "Content-Type: application/json" \
  -d '{"userId":"bbbbbbbb-bbbb-4bbb-bbbb-bbbbbbbbbbbb","latitude":37.5235634,"longitude":126.8997467,"accuracy":5.0}'

# 100m 밖 — 북쪽 약 200m (위도 +0.00180)
curl -X POST http://localhost:4001/locations \
  -H "Content-Type: application/json" \
  -d '{"userId":"cccccccc-cccc-4ccc-8ccc-cccccccccccc","latitude":37.5253634,"longitude":126.8992467,"accuracy":5.0}'
```

> **Windows PowerShell** 에서는 `curl` 대신 `Invoke-RestMethod`를 사용한다.
> ```powershell
> Invoke-RestMethod -Method Post -Uri "http://localhost:4001/locations" `
>   -ContentType "application/json" `
>   -Body '{"userId":"aaaaaaaa-aaaa-4aaa-aaaa-aaaaaaaaaaaa","latitude":37.5239634,"longitude":126.8992467,"accuracy":5.0}'
> ```

### 확인 방법

```bash
# 반경 조회 결과 확인 (100m 이내 사용자만 반환되어야 함)
curl "http://localhost:4001/locations/nearby?userId=<내-userId>"

# Redis에 저장된 전체 멤버 확인
docker-compose exec redis redis-cli ZRANGE locations:geo 0 -1
```

## 다음 단계 (이번 범위 아님)

- 마커 탭 시 거리·userId 등 정보 표시 (말풍선/BottomSheet)
- 마커 커스텀 이미지 (기본 빨간 핀 → 사람 아이콘 등)
- 인증 도입 시 userId를 인증된 식별자로 교체 ([docs/api-location-endpoint.md](./api-location-endpoint.md) 참고)
