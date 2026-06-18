# 백미 — CLAUDE.md

반경 100m 이내 주변 사람들과 실시간 소통하는 하이퍼로컬 휘발성 커뮤니티 앱.

## 모노레포 구조

```
baekmi/
├── baekmi_api/       # NestJS 백엔드
├── baekmi_app/       # Flutter 앱
├── docs/
│   ├── commit-convention.md       # 커밋 컨벤션
│   ├── flutter-naver-map.md       # 네이버 지도 SDK 연동 가이드
│   ├── flutter-geolocation.md     # 위치 조회/추적 구현 가이드
│   ├── api-location-endpoint.md   # 위치 데이터 수신 API 설계
│   ├── redis-location-store.md    # Redis 기반 위치 저장/조회 설계
│   ├── app-location-sync.md       # 플러터 위치 데이터 연동 설계
│   └── issues/
│       ├── README.md     # 이슈 인덱스 (분류별 목록)
│       ├── TEMPLATE.md   # 이슈 파일 작성 템플릿
│       └── ISSUE-XXX-*.md
├── docker-compose.yml
└── CLAUDE.md
```

---

## API — `baekmi_api`

**스택:** NestJS (TypeScript) · Prisma · PostgreSQL + PostGIS · Redis

### 실행

모든 서비스는 Docker로 실행한다. 로컬에서 직접 실행하지 않는다.

```bash
docker-compose up
```

| 서비스 | 포트 |
|--------|------|
| API (NestJS) | 4001 |
| PostgreSQL | 5432 |
| Redis | 6379 |
| pgAdmin | 5050 |

### 환경변수

루트 `.env` 파일을 사용한다. Docker가 환경변수를 컨테이너에 직접 주입한다. `.env`는 git에 올라가지 않는다.

### 주요 명령어

```bash
# Prisma 클라이언트 생성
npm run prisma:generate

# 개발 서버 (Docker 내부에서 자동 실행됨)
npm run start:dev
```

### 주요 기능

- **위치 데이터 수신**: 앱이 보낸 좌표를 받아 PostgreSQL(Prisma)에 저장. 설계 결정 및 구현 구조 → [docs/api-location-endpoint.md](./docs/api-location-endpoint.md)
- **Redis 기반 위치 저장/조회**: 같은 요청에서 Redis GEO에도 dual-write, Cron으로 만료 정리. 설계 및 구현 → [docs/redis-location-store.md](./docs/redis-location-store.md)
- **주변 사람 조회**: `GET /locations/nearby`로 반경 N미터 내 사용자 목록 반환, `GET /users/:userId/location`으로 단건 조회. 설계 및 구현 → [docs/api-nearby-search.md](./docs/api-nearby-search.md)
- **응답 형식 통일**: 모든 엔드포인트가 `{ success, data, message }` 구조로 응답. 전역 인터셉터/필터로 자동 적용 → [docs/api-response-format.md](./docs/api-response-format.md)
- **주변 사람 마커 표시**: `GET /locations/nearby`를 5초 폴링해 반경 100m 내 사용자를 지도 마커로 표시. 설계 및 구현 → [docs/app-nearby-markers.md](./docs/app-nearby-markers.md)

### 디렉토리 구조

```
baekmi_api/
├── src/
│   ├── prisma/       # PrismaModule, PrismaService
│   ├── redis/        # RedisModule, RedisService (ioredis 클라이언트)
│   ├── locations/    # 위치 데이터 수신/반경 검색 (Controller/Service, Cron 정리, dto)
│   ├── users/        # 사용자 단건 위치 조회 (Controller/Service)
│   ├── common/       # 전역 인터셉터/필터 (응답 형식 통일)
│   ├── app.module.ts
│   └── main.ts
├── prisma/
│   ├── schema.prisma
│   └── migrations/
├── Dockerfile.dev
└── package.json
```

---

## App — `baekmi_app`

**스택:** Flutter 3.44.0 · Dart 3.12.0 · flutter_naver_map · flutter_dotenv · geolocator

### 주요 기능

- **지도**: `flutter_naver_map` 사용. 자세한 연동 방법 → [docs/flutter-naver-map.md](./docs/flutter-naver-map.md)
- **위치**: `geolocator` 사용. 자세한 구현 방법 → [docs/flutter-geolocation.md](./docs/flutter-geolocation.md)
- **백엔드 연동**: MVVM(Provider) 구조로 `dio`를 통해 `POST /locations` 호출, userId는 `shared_preferences`에 보관한 클라이언트 생성 UUID. 설계 및 구현 → [docs/app-location-sync.md](./docs/app-location-sync.md)

### 실행

```bash
cd baekmi_app
flutter run
```

### 코드 컨벤션

- `var` 키워드 사용 금지 — `final`/`const`의 타입 추론은 허용, 재할당 가능한 변수는 명시적 타입 선언
- 새 기능은 **MVVM** 구조를 따른다 (Provider + ChangeNotifier). `models/`(데이터) · `services/`(외부 시스템 저수준 래퍼, 서로 모름) · `repositories/`(service 조합 도메인 로직)가 Model, `providers/`가 ViewModel(상태 보유, Widget/BuildContext를 모름), `pages/`가 View(ViewModel을 구독해 화면만 갱신, 비즈니스 로직 없음). 자세한 예시 → [docs/app-location-sync.md](./docs/app-location-sync.md)

### 디렉토리 구조

```
baekmi_app/
├── lib/
│   ├── main.dart
│   ├── models/        # Model — 데이터 구조 (LocationPayload 등)
│   ├── services/      # Model — 외부 시스템 저수준 래퍼 (geolocator/shared_preferences/dio)
│   ├── repositories/  # Model — service 조합 도메인 로직
│   ├── providers/     # ViewModel — ChangeNotifier 상태 보유
│   └── pages/         # View — map_page.dart
├── android/
├── ios/
└── pubspec.yaml
```

---

## Infra — `docker-compose.yml`

**서비스:** postgres · redis · pgadmin · api

### 실행 전 사전 조건

루트에 `.env` 파일이 있어야 한다. 없으면 환경변수가 비어 컨테이너가 정상 기동되지 않는다.
`.env`는 git에 올라가지 않으므로 새 PC나 새 환경에서 클론했을 때는 직접 생성해야 한다.
`.env.example`을 복사해서 값을 채워 사용한다.

```bash
cp .env.example .env
```

필요한 환경변수:
- `POSTGRES_USER`, `POSTGRES_PASSWORD`, `POSTGRES_DB`
- `PGADMIN_DEFAULT_EMAIL`, `PGADMIN_DEFAULT_PASSWORD`
- `REDIS_HOST`, `REDIS_PORT`
- `PORT`, `DATABASE_URL`

### Dockerfile.dev

- 위치: `baekmi_api/Dockerfile.dev`
- 개발 환경 전용 이미지
- 내부 포트: 3000 (`EXPOSE 3000`)
- 빌드 시 `prisma generate` 실행 — 단, volume 마운트로 덮어씌워지므로 실제 적용은 `command`에서 재실행함 (ISSUE-001 참고)

### 주의사항

- `api` 컨테이너는 volume 마운트로 로컬 코드와 동기화됨
- volume이 이미지 빌드 결과물을 덮어쓰기 때문에 컨테이너 시작 시 `npm install && npm run prisma:generate`를 재실행함 (ISSUE-001, ISSUE-003 참고)
- 외부 포트(4001)와 내부 포트(`$PORT`)를 다르게 설정해 로컬 포트 충돌을 방지함 (ISSUE-002 참고)

---

## 워크플로우

1. 작업 브랜치 생성 (`feat/api-location-save`, `fix/app-gps-crash` 등)
2. 커밋 전에 변경 사항과 관련된 `CLAUDE.md`/`docs/*.md`를 훑어보고 최신화한다 (디렉토리 구조, 주요 기능 설명, 설계 문서 등 코드와 어긋난 부분이 있는지 확인)
3. 커밋 (커밋 컨벤션 준수)
4. PR 생성 시 `.github/PULL_REQUEST_TEMPLATE.md` 형식을 그대로 따른다 (`gh pr create --body`로 임의 형식을 넘기지 말 것 — 템플릿이 무시된다)

브랜치 네이밍 및 커밋 컨벤션 → [docs/commit-convention.md](./docs/commit-convention.md)

---

## Docs

### 커밋 컨벤션

Conventional Commits 형식을 따른다. 자세한 내용 → [docs/commit-convention.md](./docs/commit-convention.md)

### 이슈 파일 작성 규칙

새 이슈 파일을 만들 때는 반드시 `docs/issues/TEMPLATE.md`를 읽고 그 구조를 따른다.

- 파일명: `ISSUE-XXX-{키워드}.md`
- 위치: `docs/issues/`
- 작성 후 `docs/issues/README.md` 인덱스에 추가한다.

기존 이슈 목록 → [docs/issues/README.md](./docs/issues/README.md)
