# Redis 기반 위치 저장/조회 설계

`POST /locations`로 받은 좌표를 Redis GEO에도 반영해 **저장-갱신**과 **userId 기준 단건 조회**를 빠르게 처리하기 위한 설계와 구현 내용을 정리한다.

## 구현 상태: 완료

| 파일 | 역할 |
|------|------|
| `baekmi_api/src/redis/redis.module.ts`, `redis.service.ts` | ioredis 클라이언트 (Global 모듈, `PrismaService`와 동일한 생명주기 패턴) |
| `baekmi_api/src/locations/locations.constants.ts` | Redis 키 이름(`locations:geo`, `locations:last_seen`), `LOCATION_TTL_SECONDS`(300) |
| `baekmi_api/src/locations/locations.service.ts` | `upsertLocation`에서 Postgres upsert + Redis `GEOADD`/`ZADD` dual-write, `getLocation`(Redis `GEOPOS`) |
| `baekmi_api/src/locations/locations.controller.ts` | `GET /locations/:userId` 추가 |
| `baekmi_api/src/locations/locations-cleanup.service.ts` | 30초마다(`*/30 * * * * *`) 만료된 위치를 정리하는 `@Cron` 작업 |
| `baekmi_api/src/app.module.ts` | `RedisModule`, `ScheduleModule.forRoot()` 등록 |

## 배경

- 기존 `POST /locations`는 PostgreSQL(Prisma)에만 upsert한다 ([docs/api-location-endpoint.md](./api-location-endpoint.md)).
- "반경 100m 주변 사람" 같은 위치 기반 조회는 결국 Redis GEOSEARCH로 처리할 계획이었고(`docs/issues/ISSUE-004~006`), 이번 기능이 그 첫 단계다.
- 이번 범위는 **저장/갱신**과 **userId로 단건 조회**까지다. 반경 검색(GEOSEARCH)은 다음 단계.

## 설계 결정

### 1. Redis 클라이언트: `ioredis`

GEO 커맨드(`GEOADD`, `GEOPOS`, `GEOSEARCH`)를 전부 지원하고 NestJS 생태계에서 가장 널리 쓰인다. `PrismaModule`과 동일하게 `@Global()` `RedisModule`을 만들어 어디서든 주입받아 쓸 수 있게 한다.

```
src/redis/
├── redis.module.ts
└── redis.service.ts   # ioredis 클라이언트를 감싸는 서비스
```

### 2. 키 설계

| 키 | 타입 | 용도 |
|----|------|------|
| `locations:geo` | GEO (sorted set) | 좌표 본체. `GEOADD locations:geo {longitude} {latitude} {userId}` ([ISSUE-004](./issues/ISSUE-004-redis-geoadd-order.md) 순서 주의: 경도 먼저) |
| `locations:last_seen` | sorted set | 만료 판정용. `ZADD locations:last_seen {timestamp} {userId}` |

좌표와 "마지막 갱신 시각"을 별도 키로 분리한 이유는 Redis GEO 자체에 멤버 단위 TTL이 없기 때문이다 ([ISSUE-005](./issues/ISSUE-005-redis-user-location-residue.md)).

### 3. 만료 전략: Cron 주기적 정리

Redis GEO(`GEOADD`로 만들어지는 sorted set)는 멤버(유저) 단위 TTL을 지원하지 않는다 ([ISSUE-005](./issues/ISSUE-005-redis-user-location-residue.md)). 그래서 "마지막으로 위치를 보낸 시각"을 별도 자료구조에 기록해두고, 그 시각이 오래된 유저를 직접 찾아서 지워야 한다. 검토한 두 가지 방식과 선택 이유를 정리한다.

#### 방식 A — 동반 키 + TTL (조회 시점에 정리)

- 위치를 갱신할 때마다 `user:location:ttl:{userId}` 같은 별도 키에 `EXPIRE`를 걸어둔다 (값 자체는 의미 없고, 키의 존재 여부만 본다).
- 조회(`GEOPOS`) 또는 검색(`GEOSEARCH`) 시점에, 결과로 나온 각 userId에 대해 동반 키가 살아있는지 확인한다.
- 동반 키가 만료되어 사라졌다면 "이 유저는 죽은 데이터"로 간주하고, 그 자리에서 `ZREM`으로 `locations:geo`에서도 제거한다(lazy cleanup).

**장점**
- 별도 스케줄러나 새 의존성 없이 지금 가진 도구(EXPIRE)만으로 구현 가능.
- Redis가 키 만료를 자동으로 관리해주므로 "임계값을 직접 계산"하는 로직이 없다.

**단점**
- **아무도 조회하지 않는 유저는 영원히 안 지워진다.** 정리가 "읽기 시점에 얹혀가는" 부수효과이기 때문에, 읽기가 없으면 청소도 일어나지 않는다 → 메모리가 계속 쌓일 수 있다.
- 지금 요구사항(userId 단건 조회, `GEOPOS` 1건)에서는 동반 키 1개만 확인하면 되니 단순하지만, 다음 단계인 GEOSEARCH(반경 검색)에서는 결과로 나온 멤버 수(N)만큼 동반 키를 추가로 조회해야 한다(`GEOSEARCH` 1번 + `EXISTS`/`MGET` N번, 또는 파이프라인으로 묶어도 N개 키 조회가 매 검색마다 발생). 검색 빈도가 높아질수록 이 오버헤드가 누적된다.
- "만료 확인 + 정리" 로직이 조회 경로(`GEOPOS`, `GEOSEARCH`)마다 중복으로 들어가야 해서, 조회 기능을 추가할 때마다 같은 로직을 또 구현/유지보수해야 한다.

#### 방식 B — 주기적 배치 정리 (Cron)

- 위치를 갱신할 때마다 `ZADD locations:last_seen {timestamp} {userId}`로 "마지막 갱신 시각"을 별도 정렬 집합(sorted set)에 기록한다.
- `@nestjs/schedule`의 `@Cron`으로 일정 주기(예: 30초)마다 다음을 수행한다.

```
매 주기마다:
  ZRANGEBYSCORE locations:last_seen -inf (now - TTL_SECONDS)
  → 임계값보다 오래된 userId 목록
  → ZREM locations:last_seen {...}
  → ZREM locations:geo {...}
```

**장점**
- 조회 여부와 무관하게 능동적으로 정리되므로, 죽은 데이터가 무한정 쌓이는 일이 없다 — 메모리가 예측 가능하게 관리된다.
- `locations:geo`가 "항상 살아있는 유저만 담고 있다"는 불변식이 유지되므로, 조회/검색 코드(`GEOPOS`, 추후 `GEOSEARCH`)는 만료 체크 로직 없이 결과를 그대로 믿고 써도 된다. 즉 정리 로직이 한 곳(Cron 작업)에만 있고, 조회 경로는 단순해진다.
- 정리 비용이 "주기당 1회 일괄 처리"로 고정되어 있어, 조회가 잦아져도(특히 GEOSEARCH 도입 후) 정리 비용이 같이 늘지 않는다.

**단점**
- `@nestjs/schedule`이라는 새 의존성과 Cron 작업 클래스가 하나 더 필요하다.
- 정리 주기 사이에는 이미 죽은 유저가 짧게 남아있을 수 있다(최대 주기 시간만큼의 지연). 예를 들어 30초 주기라면 최악의 경우 만료 후 30초까지는 조회/검색 결과에 보일 수 있다.

#### 결론

지금 범위(userId 단건 조회)만 보면 방식 A가 더 가볍지만, 바로 다음 단계로 예정된 GEOSEARCH(반경 검색)를 고려하면 방식 A는 검색 결과 수만큼 추가 조회가 필요해지고 정리 로직이 조회 경로마다 중복된다. 반면 방식 B는 한 번 구현해두면 모든 조회 경로(현재의 단건 조회, 추후의 반경 검색)가 "항상 깨끗한 데이터"를 전제로 단순하게 동작할 수 있다. 따라서 약간의 지연(최대 Cron 주기)과 새 의존성을 감수하고 **방식 B(Cron 주기적 정리)**를 택한다.

`TTL_SECONDS`와 Cron 주기는 앱의 위치 전송 빈도(`LocationService`의 `distanceFilter: 10m` 기준 이동 시 전송)를 보고 구현 시점에 정한다. 일반적으로 Cron 주기는 `TTL_SECONDS`보다 충분히 짧게(예: TTL의 1/4~1/2 수준) 잡아야 정리 지연이 체감되지 않는다.

### 4. 기존 Postgres 흐름과의 관계: 같은 요청에서 함께 갱신 (dual-write)

`POST /locations` 한 번의 호출로 Postgres upsert와 Redis 갱신을 모두 수행한다. 클라이언트는 엔드포인트 하나만 호출하면 된다.

```
LocationsService.upsertLocation(dto)
  ├─ prisma.client.location.upsert(...)   # 기존: 영구 저장소, 추후 이력 테이블 확장 여지
  └─ redisService 호출                     # 신규: GEOADD + ZADD(last_seen)
```

### 5. userId 기준 조회: 신규 `GET /locations/:userId`

Redis에서 조회한다(Postgres가 아님 — 만료된 유저는 Postgres엔 남아 있어도 Redis엔 없어야 "현재 휘발성 상태"를 정확히 반영).

```
GEOPOS locations:geo {userId}
→ 없으면 404 (만료되었거나 한 번도 위치를 보낸 적 없음)
→ 있으면 { longitude, latitude } 반환
```

## 구현 절차 흐름

### 1. 위치 저장/갱신 — `POST /locations`

```
앱 → POST /locations { userId, latitude, longitude, accuracy }
        ↓
   LocationsController.create(dto)
        ↓
   LocationsService.upsertLocation(dto)
        ├─ Postgres: prisma.client.location.upsert({ where: { userId }, ... })
        │     └─ 영구 저장소, 추후 이력 테이블 확장 여지 (이번 변경 없음)
        │
        └─ Redis (신규):
              ① GEOADD locations:geo {longitude} {latitude} {userId}
              ② ZADD locations:last_seen {now} {userId}
        ↓
   두 작업 완료 후 응답 반환
```

### 2. userId 기준 조회 — `GET /locations/:userId` (신규)

```
앱 → GET /locations/{userId}
        ↓
   LocationsController.findOne(userId)
        ↓
   LocationsService.getLocation(userId)
        ↓
   GEOPOS locations:geo {userId}
        ├─ 결과 없음 → 404 (만료됐거나 한 번도 보낸 적 없음)
        └─ 결과 있음 → { longitude, latitude } 응답
```

### 3. 만료 정리 — Cron (신규, 백그라운드)

```
@Cron(주기, 예: 30초마다)
        ↓
   ZRANGEBYSCORE locations:last_seen -inf (now - TTL_SECONDS)
        ↓
   임계값보다 오래된 userId 목록 추출
        ↓
   목록이 비어있지 않으면:
        ├─ ZREM locations:last_seen {...목록}
        └─ ZREM locations:geo {...목록}
        ↓
   (다음 주기까지 대기)
```

이 세 흐름은 서로 독립적으로 동작한다. ①/②는 클라이언트 요청에 의해 트리거되고, ③은 별도 백그라운드 스케줄러로 항시 동작한다.

## 예상되는 이슈

구현 전에 미리 예상되는 문제들. 우선순위가 높은 것부터 정리한다.

### 1. GEOADD + ZADD 원자성 부족 (우선순위 높음) — 해결됨

`GEOADD`와 `ZADD(last_seen)`는 별도의 두 명령이라, 중간에 실패(앱 크래시, 네트워크 끊김)하면 `GEOADD`만 적용되고 `last_seen`은 갱신되지 않을 수 있다. 이러면 방금 들어온 좌표인데도 `last_seen`이 과거 값으로 남아 Cron이 "오래됐다"고 잘못 판단해 지워버릴 수 있다.

→ **대응**: `LocationsService.upsertLocation`에서 `redis.client.multi().geoadd(...).zadd(...).exec()`로 두 명령을 원자적으로 묶었다.

### 2. 인증 없는 `GET /locations/:userId`의 노출 문제 (우선순위 높음) — 계획 수립됨

`userId`는 인증된 식별자가 아니라 클라이언트가 생성한 UUID일 뿐이다. 이 UUID를 아는(또는 다른 응답에서 노출되거나 추측되는) 누구나 해당 사용자의 실시간 좌표를 조회할 수 있게 된다.

→ **대응**: JWT 인증 도입 시 해결할 계획. `User` 테이블을 신설해 `Location.userId`를 인증된 `User.id`로 교체하고, 인증 가드로 본인 확인 후에만 조회 가능하도록 제한한다. 자세한 계획 → [docs/api-location-endpoint.md](./api-location-endpoint.md)의 "사용자 식별" 섹션.

### 3. Postgres-Redis dual-write 불일치 — 미해결

Postgres upsert와 Redis 갱신 중 한쪽만 성공하는 부분 실패 상황(예: Postgres는 성공, Redis 호출 타임아웃)에 대한 처리가 설계에 없다.

→ **대응**: 실패 시 요청 자체를 실패로 처리할지, 로그만 남기고 넘어갈지(eventual consistency 허용) 구현 시점에 정책을 정해야 한다.

### 4. API 인스턴스가 여러 개로 늘어나면 Cron 중복 실행 — 미해결

지금은 컨테이너 1개라 문제 없지만, API를 여러 인스턴스로 스케일하면 각 인스턴스가 동일한 `@Cron`을 동시에 실행한다. `ZREM`은 멱등이라 당장 깨지는 건 아니지만 불필요한 중복 작업이 발생한다.

→ **대응**: 분산 락(예: Redis `SET NX`로 "이번 주기는 내가 처리한다" 표시) 또는 정리 작업을 단일 인스턴스/별도 워커로 분리.

### 5. `last_seen` score로 앱 서버 시각(`Date.now()`)을 쓰는 것 — 해결됨

여러 API 인스턴스의 시계가 어긋나면(clock skew) 만료 판정이 인스턴스마다 다르게 흔들릴 수 있다.

→ **대응**: `Date.now()` 대신 `redis.client.time()`(Redis `TIME` 명령)으로 받은 서버 시각을 score로 사용했다.

### 6. `accuracy`가 Redis에는 반영되지 않음 — 미해결

GPS 오차가 큰 좌표도 그대로 `GEOADD`되므로, 추후 GEOSEARCH 단계에서 부정확한 위치가 "근처"로 잘못 잡힐 수 있다. 지금 범위(단건 조회)에서는 영향이 없지만 반경 검색 도입 시 고려가 필요하다.

→ **대응**: 반경 검색 기능 설계 시 정확도 필터링(예: `accuracy`가 일정 값 이상이면 검색 대상에서 제외) 여부를 결정한다.

## 구현 완료 체크리스트

- [x] `ioredis`, `@nestjs/schedule` 패키지 설치
- [x] `.env.example` / `.env` / `docker-compose.yml`의 `api` 서비스에 `REDIS_HOST`, `REDIS_PORT` 환경변수 추가
- [x] `src/redis/redis.module.ts`, `redis.service.ts` 작성 후 `AppModule`에 등록
- [x] `LocationsService`에 Redis 갱신 로직 추가 (dual-write, MULTI로 원자적 실행)
- [x] `LocationsController`에 `GET /locations/:userId` 라우터 추가
- [x] Cron 정리 작업 클래스 작성 (`*/30 * * * * *`)

## redis-cli로 데이터 확인하기

pgAdmin처럼 GUI는 따로 없으므로, `docker-compose exec`로 컨테이너 안의 `redis-cli`를 직접 호출해서 확인한다. **`docker-compose.yml`이 있는 프로젝트 루트에서 실행해야 한다** (다른 경로에서 실행하면 `no configuration file provided` 에러가 난다).

```bash
# 대화형 셸 진입 (여러 명령을 연달아 입력하고 싶을 때)
docker-compose exec redis redis-cli

# 한 번에 명령 하나씩 실행하고 싶을 때
docker-compose exec redis redis-cli <명령>
```

자주 쓰는 명령:

```bash
# 전체 키 목록
docker-compose exec redis redis-cli KEYS '*'

# 키 타입 확인 (locations:geo, locations:last_seen 둘 다 내부적으로 zset)
docker-compose exec redis redis-cli TYPE locations:geo

# 두 키에 들어있는 전체 멤버와 score 보기
docker-compose exec redis redis-cli ZRANGE locations:geo 0 -1 WITHSCORES
docker-compose exec redis redis-cli ZRANGE locations:last_seen 0 -1 WITHSCORES

# 특정 userId의 좌표 조회
docker-compose exec redis redis-cli GEOPOS locations:geo {userId}

# 특정 userId의 마지막 갱신 시각(score, Unix epoch 초)
docker-compose exec redis redis-cli ZSCORE locations:last_seen {userId}

# 현재 Redis 서버 시각 (만료 임계값 계산 기준)
docker-compose exec redis redis-cli TIME

# 멤버 수동 삭제 (테스트용)
docker-compose exec redis redis-cli ZREM locations:geo {userId}
docker-compose exec redis redis-cli ZREM locations:last_seen {userId}
```

## 다음 단계 (이번 범위 아님)

- `GEOSEARCH ... FROM MEMBER`로 반경 검색 시 본인 제외 처리 ([ISSUE-006](./issues/ISSUE-006-redis-geosearch-self-include.md))
- 반경 검색 API(`GET /locations/nearby?userId=...&radius=...`) 추가
