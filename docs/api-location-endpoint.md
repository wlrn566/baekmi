# 위치 데이터 수신 API 설계

앱(`baekmi_app`)에서 보낸 좌표(위도/경도)를 받는 라우터에 대한 설계 결정과 구현 구조를 정리한다.

## 설계 결정

### 저장소: PostgreSQL (Prisma)

`docs/issues`에 Redis GEOADD/GEOSEARCH 관련 이슈(ISSUE-004~006)가 정리되어 있어 "반경 100m 주변 사람"이라는 휘발성 컨셉상 Redis GEO 저장이 자연스러워 보이지만, 1차 구현은 **PostgreSQL(Prisma)**로 한다.

- Redis GEO는 "주변 사람 검색(GEOSEARCH)" 기능을 만들 때 도입한다.
- 현재는 좌표를 받아 저장하는 라우터 하나만 필요한 단계이므로, 이미 연동되어 있는 Prisma/PostgreSQL을 그대로 사용한다.
- 사용자별로 위치 히스토리를 누적하지 않고 **최신 위치 1건만 유지**(upsert)하여 휘발성 컨셉을 반영한다.

### 이 테이블의 용도 (Redis 도입 이후에도 유지하는 이유)

"반경 100m 주변 사람 검색"은 결국 속도 때문에 Redis GEOSEARCH를 거치게 되므로, 이 `locations` 테이블은 그 조회 경로에는 쓰이지 않는다. 그럼에도 `POST /locations`가 Postgres에 upsert하는 동작은 그대로 유지하기로 했다.

- 지금 구조(사용자별 최신 위치 1건 upsert)는 그대로 두되, **나중에 `unique` 제약을 없애고 append-only 이력 테이블로 확장할 수 있는 여지**를 남겨두기 위함이다.
- Redis 도입 완료: `POST /locations`가 Postgres upsert와 Redis 갱신을 함께 수행한다(dual-write). 키 설계, 만료 전략 등 자세한 내용은 [docs/redis-location-store.md](./redis-location-store.md) 참고.

### 사용자 식별: 클라이언트 생성 UUID

인증 시스템과 `User` 모델이 아직 없으므로, 앱이 생성한 UUID(device/session 단위)를 요청 body에 포함해 사용자를 식별한다.

기기 고유 식별자(ANDROID_ID, 광고 ID 등)로 대체하는 방안도 검토했으나 채택하지 않았다 — IMEI/시리얼은 Android 10+에서 접근 차단, 광고 ID는 정책상 다른 영구 식별자와 결합 금지, ANDROID_ID도 결국 "재설치/공장초기화 시 끊긴다"는 점에서 클라이언트 UUID와 동일한 한계를 가지면서 추가 패키지/플랫폼 분기 비용만 더 든다. 같은 이유로 지금 시점에 `User` 테이블도 만들지 않았다 — 저장할 부가 정보가 없어 FK 무결성 외에 얻는 게 없다(YAGNI).

> **추후 인증 도입 시 계획**: JWT 기반 로그인을 추가하면 ① JWT의 사용자 식별 클레임(`sub` 등)을 키로 하는 `User` 테이블을 신설하고, ② `Location.userId`가 가리키는 대상을 클라이언트 UUID → 인증된 `User.id`로 교체하고, ③ 인증 가드로 본인 확인 후에만 위치를 보내거나 조회하도록 제한한다. 이 변경은 [docs/redis-location-store.md](./redis-location-store.md)의 "예상되는 이슈 #2(인증 없는 GET 조회 노출)"도 함께 해결한다.

## 구현 구조

```
baekmi_api/src/locations/
├── locations.module.ts
├── locations.controller.ts
├── locations.service.ts
└── dto/
    └── create-location.dto.ts
```

- `Location` 모델(`prisma/schema.prisma`): `id`, `userId`(`@unique`), `latitude`, `longitude`, `accuracy`, `createdAt`, `updatedAt`
  - DB 컬럼은 `@map`/`@@map`으로 snake_case 매핑 (`locations` 테이블, `user_id`/`created_at`/`updated_at` 컬럼). TS 코드에서는 그대로 camelCase 사용.
- `POST /locations`: `CreateLocationDto`로 검증(`class-validator`) 후 `userId` 기준 upsert
- `main.ts`에 전역 `ValidationPipe`(`whitelist`, `transform`) 등록 (기존에는 없었음)
- `LocationsService`는 `PrismaService.client`(Prisma v7의 adapter 기반 연결)를 통해 `location` 모델에 접근
- 스키마(`@map`/모델) 변경 후에는 `npx prisma generate`로 클라이언트를 반드시 재생성해야 한다 — 안 하면 이전 테이블명을 참조해 런타임에 `TableDoesNotExist` 에러가 난다 ([ISSUE-007](./issues/ISSUE-007-prisma-schema-change-nodemon-crash.md) 참고)

## 검증 방법

```bash
docker-compose exec api npx prisma migrate dev --name add_location

curl -X POST http://localhost:4001/locations \
  -H "Content-Type: application/json" \
  -d '{"userId":"550e8400-e29b-41d4-a716-446655440000","latitude":37.5665,"longitude":126.9780,"accuracy":5.0}'
```

동일 `userId`로 재요청 시 레코드가 추가되지 않고 갱신되는지 확인한다.
