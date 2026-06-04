# [ISSUE-003] Docker 컨테이너에서 로컬 코드 watch(핫리로드) 미작동

**발생 시점:** NestJS 백엔드 구축  
**분류:** Docker

## 증상

- volume 연동 후 로컬 코드를 수정해도 컨테이너 api가 재시작되지 않음
- NestJS 기본 `--watch` 옵션은 Docker 컨테이너 환경에서 동작하지 않음

## 원인

- NestJS 기본 `--watch`는 파일시스템 이벤트를 직접 감지하는 방식으로, Docker 컨테이너 내부에서는 호스트의 파일 변경 이벤트가 전달되지 않음

## 원인 흐름

```
로컬 파일 수정
          ↓
volume 마운트로 컨테이너 내부 파일은 변경됨
          ↓
NestJS --watch가 파일 변경 이벤트를 감지하지 못함
          ↓
핫리로드 미작동
```

## 해결책 1 — nodemon 도입

```json
// package.json
"start:dev": "nodemon --watch src --ext ts --exec ts-node src/main.ts"
```

## 해결책 2 — nodemon도 volume에 의해 사라지는 경우

volume 설정으로 인해 nodemon도 `npm install` 레이어 이후 사라지는 현상이 추가로 발생할 수 있다.  
이 경우 command에 `npm install`을 함께 넣는다.

```yaml
command: >
  sh -c "npm install && npm run prisma:generate && npm run start:dev"
```

## 최종 권장 command

```yaml
command: >
  sh -c "npm install && npm run prisma:generate && npm run start:dev"
```

> ISSUE-001, ISSUE-002, ISSUE-003을 모두 커버한다.
