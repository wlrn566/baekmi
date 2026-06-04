# [ISSUE-004] Redis GEOADD 인자 순서 혼동

**발생 시점:** Redis 연동 구현  
**분류:** Redis

## 증상

- 위도(latitude)를 먼저, 경도(longitude)를 나중에 넣는 실수
- 위치가 전혀 다른 곳에 저장되거나 조회 결과가 이상하게 나옴

## 원인

- 일반적으로 위치를 표현할 때 "위도, 경도" 순서를 쓰는 습관과 Redis의 순서가 반대이기 때문

## 원인 흐름

```
위도(37.5665), 경도(126.9780) 순서로 익숙함
          ↓
GEOADD에 위도 → 경도 순으로 입력
          ↓
잘못된 위치에 저장 → GEOSEARCH 결과 이상
```

## 해결책

**경도(longitude) 먼저, 위도(latitude) 나중**으로 입력한다.

```bash
# GEOADD key longitude latitude member  ← 순서 주의
GEOADD user:location 126.9780 37.5665 "user_1"
#                    ^^^경도^^^  ^^^위도^^^
```
