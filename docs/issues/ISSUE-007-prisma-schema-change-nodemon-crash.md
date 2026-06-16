# [ISSUE-007] Prisma 스키마 변경 후 실행 중인 프로세스가 stale Prisma Client를 참조

**발생 시점:** 2026/06/16
**분류:** NestJS

## 증상

두 가지 형태로 나타난다.

1. **컴파일 크래시**: `schema.prisma`에 모델을 추가한 뒤 `src`에 그 모델을 쓰는 코드를 먼저 작성하면, 이미 실행 중이던 `nodemon`(`npm run start:dev`)이 TypeScript 컴파일 에러로 크래시함
   - 에러 예시: `Property 'location' does not exist on type 'PrismaClient<...>'`
   - crash 이후 `[nodemon] app crashed - waiting for file changes before starting...` 상태로 멈춤
2. **런타임 에러 (크래시 없음)**: `@map`/`@@map`처럼 테이블·컬럼명을 바꾸는 마이그레이션을 적용한 뒤 `npx prisma generate`를 다시 실행하지 않으면, 코드는 정상 컴파일되지만 요청 시 500 에러가 발생함
   - 에러 예시: `P2021 TableDoesNotExist`, `relation "public.Location" does not exist` (이미 `locations`로 테이블명을 바꿨는데도 구버전 클라이언트가 옛 이름을 참조)

## 원인

- `nodemon`은 `src` 디렉토리만 watch한다 (`package.json`의 `start:dev` 스크립트 참고). `schema.prisma`나 `node_modules/@prisma/client` 변경은 감지하지 못해 자동 재시작되지 않는다
- 실행 중인 Node 프로세스는 `require` 시점에 로드한 Prisma Client(타입 + 런타임 매핑 정보)를 메모리에 들고 있다. `schema.prisma`를 바꾸고 `prisma generate`/`migrate dev`를 실행해도, 그 변경은 디스크의 `node_modules/.prisma/client`에만 반영되고 **이미 떠 있는 프로세스에는 반영되지 않는다**
- 따라서 스키마 변경 → 코드 작성 → generate 순서로 진행하면 컴파일 시점에 구버전 타입을 참조해 크래시하고, generate를 했더라도 프로세스를 재시작하지 않으면 구버전 런타임 매핑(옛 테이블/컬럼명)으로 쿼리를 보내 실패한다

## 원인 흐름

```
schema.prisma 수정 (모델 추가 또는 @map으로 테이블/컬럼명 변경)
          ↓
prisma generate를 아직 안 함 → src에 새 코드 작성 시 컴파일 크래시
또는
prisma generate 실행 (node_modules 갱신) → 이미 떠 있는 프로세스는 재시작 전까지 구버전 클라이언트 사용 → 런타임 에러
```

## 해결책

**Prisma 스키마를 바꿀 때마다 다음 순서를 지킨다.**

1. `schema.prisma` 수정
2. `npx prisma generate` (테이블/컬럼 구조가 바뀌면 `npx prisma migrate dev --name <migration_name>`)
3. 그 모델을 사용하는 `src` 코드는 2번 이후에 작성
4. 이미 떠 있는 `nodemon` 프로세스가 있다면 `src`의 아무 파일이나 touch해서 강제로 재시작시킨다 (schema/node_modules 변경만으로는 자동 재시작되지 않음)

```bash
docker-compose exec api npx prisma generate
docker-compose exec api npx prisma migrate dev --name <migration_name>
# 재시작 유도 (크래시 복구 또는 stale 클라이언트 갱신)
touch src/main.ts
```
