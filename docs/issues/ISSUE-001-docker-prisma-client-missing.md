# [ISSUE-001] Docker 배포 시 Prisma Client 누락

**발생 시점:** NestJS 백엔드 구축 (2026/04/03)  
**분류:** Docker

## 증상

- 도커 이미지 빌드 시 `npx prisma generate`로 Prisma Client 생성 완료
- api 컨테이너에 로컬 volume을 연동하면 컨테이너 내부 파일이 로컬 데이터로 덮어씌워짐
- 결과적으로 Prisma Client가 사라지며 "Prisma Client가 없다" 에러 발생

## 원인

- Docker volume 마운트가 이미지 빌드 레이어를 덮어씌우는 구조이기 때문
- `prisma generate`는 빌드 시점에 실행되지만, volume 연동 후 컨테이너 내부 파일이 로컬 파일로 교체됨

## 원인 흐름

```
도커 이미지 빌드 → Prisma Client 생성 완료
          ↓
volume 연동 → 로컬 볼륨으로 덮어씌워지면서 Prisma Client 사라짐
          ↓
컨테이너 api 기동 시 Prisma Client 없음 → 에러
```

## 해결책

`docker-compose.yml`의 command에서 컨테이너가 뜬 뒤 Prisma Client를 재생성한다.

```yaml
command: >
  sh -c "npm install && npm run prisma:generate && npm run start:dev"
```

> ISSUE-003과 함께 묶어 최종 command 하나로 커버된다.
