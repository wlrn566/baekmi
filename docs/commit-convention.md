# 커밋 컨벤션

[Conventional Commits](https://www.conventionalcommits.org/) 형식을 따릅니다.

## 형식

```
<type>(<scope>): <subject>

<body>
```

## Type

| 타입 | 설명 |
|------|------|
| `feat` | 새로운 기능 추가 |
| `fix` | 버그 수정 |
| `docs` | 문서 수정 |
| `style` | 코드 포맷팅, 세미콜론 누락 등 (기능 변경 없음) |
| `refactor` | 코드 리팩토링 (기능 변경 없음) |
| `test` | 테스트 추가 또는 수정 |
| `chore` | 빌드 설정, 패키지 업데이트 등 |
| `infra` | Docker, CI/CD 등 인프라 관련 |

## Scope

| 스코프 | 설명 |
|--------|------|
| `api` | baekmi_api (NestJS) |
| `app` | baekmi_app (Flutter) |
| `infra` | docker-compose, Dockerfile |
| `docs` | 문서 |

## 예시

```
feat(api): 위치 저장 API 구현

fix(app): 위치 권한 거부 시 앱 크래시 수정

docs(docs): ISSUE-007 Redis TTL 이슈 추가

infra: api 컨테이너 핫리로드 설정 추가

chore(api): prisma 버전 업데이트
```

## 브랜치 네이밍

```
<type>/<scope>-<subject>
```

```
feat/api-location-save
fix/app-gps-crash
chore/infra-docker-hotreload
docs/commit-convention
```

---

## 규칙

- `subject`는 현재 시제로 작성 (과거형 X)
- `subject` 끝에 마침표 X
- `body`는 어떤 작업을 했는지 간단히 목록으로 작성 (필수)
