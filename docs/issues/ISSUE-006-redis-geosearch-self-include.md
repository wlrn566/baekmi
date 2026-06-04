# [ISSUE-006] GEOSEARCH 결과에 자기 자신 포함

**발생 시점:** Redis 연동 구현  
**분류:** Redis

## 증상

- `GEOSEARCH ... FROM MEMBER "user_1"` 결과에 `user_1` 자신이 거리 0m로 포함됨

## 원인

- `GEOSEARCH FROM MEMBER`는 해당 멤버의 위치를 기준점으로 사용하므로 자기 자신도 결과에 포함됨
- Redis 명령어 자체에 자기 제외 옵션이 없음

## 원인 흐름

```
GEOSEARCH FROM MEMBER "user_1"
          ↓
user_1 위치 기준 반경 조회
          ↓
user_1 자신도 거리 0m로 결과에 포함
```

## 해결책

조회 결과에서 요청한 유저 본인을 필터링하는 로직을 추가한다.

```typescript
// NestJS 서비스 레이어
const nearbyUsers = results.filter((u) => u.userId !== requestingUserId);
```
