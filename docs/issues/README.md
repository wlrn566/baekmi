# 이슈 목록

> 개발 중 발생한 이슈와 검증된 해결책을 기록합니다.
> AI 에이전트는 작업 전 이 문서를 참고해 동일 문제를 반복하지 마세요.

## Docker

| 번호 | 제목 |
|------|------|
| [ISSUE-001](./ISSUE-001-docker-prisma-client-missing.md) | Docker 배포 시 Prisma Client 누락 |
| [ISSUE-002](./ISSUE-002-docker-port-conflict.md) | Docker 컨테이너 ↔ 로컬 포트 충돌 |
| [ISSUE-003](./ISSUE-003-docker-hot-reload.md) | Docker 컨테이너에서 로컬 코드 watch(핫리로드) 미작동 |

## Redis

| 번호 | 제목 |
|------|------|
| [ISSUE-004](./ISSUE-004-redis-geoadd-order.md) | GEOADD 인자 순서 혼동 (경도 → 위도) |
| [ISSUE-005](./ISSUE-005-redis-user-location-residue.md) | 퇴장한 유저 위치 데이터 잔류 |
| [ISSUE-006](./ISSUE-006-redis-geosearch-self-include.md) | GEOSEARCH 결과에 자기 자신 포함 |
