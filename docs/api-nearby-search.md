# 주변 사람 조회 API 설계

반경 N미터 이내 사용자 목록을 반환하는 `GET /locations/nearby`와,
특정 사용자의 현재 위치를 반환하는 `GET /users/:userId/location` 설계 및 구현 내용을 정리한다.

## 구현 상태: 완료

| 파일 | 역할 |
|------|------|
| `baekmi_api/src/users/users.module.ts` | UsersModule |
| `baekmi_api/src/users/users.service.ts` | `getLocation(userId)` — Redis GEOPOS 조회 |
| `baekmi_api/src/users/users.controller.ts` | `GET /users/:userId/location` |
| `baekmi_api/src/locations/dto/get-nearby.dto.ts` | 반경 검색 쿼리스트링 DTO |
| `baekmi_api/src/locations/locations.service.ts` | `getNearbyLocations(userId, radius)` 추가 |
| `baekmi_api/src/locations/locations.controller.ts` | `GET /locations/nearby` 추가 |
| `baekmi_api/src/locations/locations.constants.ts` | `DEFAULT_NEARBY_RADIUS_METERS`, `MAX_NEARBY_RADIUS_METERS` 추가 |

## 배경

- `POST /locations`와 Redis GEO 저장/만료 정리까지 완료된 상태 ([docs/redis-location-store.md](./redis-location-store.md)).
- 이번 기능이 인프라를 실제로 사용하는 첫 번째 조회 기능이다.

## 라우트 설계 결정

### `GET /locations/:userId` → `GET /users/:userId/location`으로 이동

기존 `GET /locations/:userId`는 `:userId`가 Location 리소스의 ID처럼 읽히지만,
실제로는 "특정 유저의 위치를 조회"하는 요청이다. 조회의 주어가 유저이므로
`GET /users/:userId/location`이 의미상 더 정확하다.

이에 따라 UsersModule을 신설하고, 단건 위치 조회를 그 안으로 이동했다.

### `GET /locations/nearby?userId=...` — LocationsModule 유지

반환값이 "위치 레코드 목록"이고, `userId`는 검색 기준점 역할을 하는 쿼리스트링 파라미터다.
위치 컬렉션에 대한 필터 쿼리로 읽히므로 `/locations` 네임스페이스에 두는 것이 자연스럽다.

### `POST /locations` — 변경 없음

위치 데이터를 컬렉션에 추가하는 동작이고, userId는 body에 있으므로 경로를 바꿀 이유가 없다.

## UsersModule 구조

```
src/users/
├── users.module.ts
├── users.service.ts    # RedisService 직접 주입 (LocationsService 미사용)
└── users.controller.ts
```

`UsersService`는 `LocationsService`를 거치지 않고 `RedisService`를 직접 주입받아 GEOPOS를 호출한다.
`RedisModule`이 `@Global()`이므로 `UsersModule`에서 별도 import 없이 주입받을 수 있다.

## `GET /users/:userId/location`

### 동작

```
GET /users/{userId}/location
       ↓
UsersController.findLocation(userId)
       ↓
UsersService.getLocation(userId)
       ↓
GEOPOS locations:geo {userId}
       ├─ 없음 → 404 (만료됐거나 한 번도 위치를 보낸 적 없음)
       └─ 있음 → { longitude, latitude }
```

### 응답 예시

```json
{ "longitude": 126.978, "latitude": 37.5665 }
```

## `GET /locations/nearby`

### 쿼리스트링

| 파라미터 | 타입 | 필수 | 기본값 | 제약 |
|----------|------|------|--------|------|
| `userId` | UUID | ✓ | — | UUID v4 형식 |
| `radius` | number | — | 100 | 1 ~ 5000 (미터) |

### 동작

```
GET /locations/nearby?userId={uuid}&radius={meters}
       ↓
LocationsController.findNearby(dto)
       ↓
LocationsService.getNearbyLocations(userId, radius)
       ↓
GEOSEARCH locations:geo FROMMEMBER {userId} BYRADIUS {radius} m ASC COUNT 100 WITHDIST WITHCOORD
       ↓
결과에서 자기 자신 제외 (ISSUE-006)
       ↓
[{ userId, latitude, longitude, distance }]
```

### 자기 자신 제외 (ISSUE-006)

`GEOSEARCH FROMMEMBER`는 기준 멤버 자신도 결과에 포함한다(거리 0).
응답에 본인이 포함되는 건 의미 없으므로 파싱 후 명시적으로 필터링한다.

### GEOSEARCH raw call 이유

ioredis 5의 `geosearch()` 타입 오버로드가 `WITHDIST + WITHCOORD` 동시 사용을 커버하지 않는다.
`(this.redis.client as any).geosearch(...)` 형태로 타입 우회 후 결과를 직접 파싱한다.

### Redis 응답 형태 (`WITHDIST WITHCOORD` 기준)

```
[
  ["userId1", "45.32", ["126.9780", "37.5665"]],
  ["userId2", "87.12", ["126.9790", "37.5668"]],
]
```

파싱: `[memberId, distance_string, [longitude_string, latitude_string]]`

### userId가 Redis에 없는 경우

`GEOSEARCH FROMMEMBER`는 대상 멤버가 없으면 Redis 에러를 던진다.
`.catch(() => [])` 처리 후 빈 배열을 반환한다.
"근처에 아무도 없음"과 동일하게 처리한다.

### COUNT 100 제한

반경 100m 안에 수백 명이 있는 시나리오는 현실적으로 드물지만,
GEOSEARCH 결과 수를 무제한으로 열어두지 않기 위해 안전 상한으로 100을 설정한다.

### 응답 예시

```json
[
  { "userId": "bbbb...", "latitude": 37.5666, "longitude": 126.9781, "distance": 14.35 },
  { "userId": "cccc...", "latitude": 37.5668, "longitude": 126.9783, "distance": 67.12 }
]
```

## 라우트 순서 주의 (`GET /locations/:userId` 제거 후)

기존에 있던 `GET /locations/:userId`를 제거하면서 `/locations/nearby`가 `:userId` 패턴과
충돌할 위험도 함께 사라졌다. 그럼에도 컨트롤러에서 `@Get('nearby')`는 `@Get(':something')` 형태의
동적 라우트보다 항상 위에 선언하는 습관을 유지한다.

## 검증 방법

```bash
# 1. 위치 두 개 삽입 (근접 좌표)
curl -X POST http://localhost:4001/locations \
  -H "Content-Type: application/json" \
  -d '{"userId":"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa","latitude":37.5665,"longitude":126.9780,"accuracy":5}'

curl -X POST http://localhost:4001/locations \
  -H "Content-Type: application/json" \
  -d '{"userId":"bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb","latitude":37.5666,"longitude":126.9781,"accuracy":5}'

# 2. 단건 조회 (UsersModule)
curl http://localhost:4001/users/aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa/location

# 3. 반경 조회 — B만 결과에 나와야 함 (A 자신 제외)
curl "http://localhost:4001/locations/nearby?userId=aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"

# 4. 반경 1m — 빈 배열이어야 함
curl "http://localhost:4001/locations/nearby?userId=aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa&radius=1"
```
