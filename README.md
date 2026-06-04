# 백미

> 내 위치 기준 반경 100m 이내의 가까운 이웃들과 실시간으로 소통하는 **하이퍼로컬 휘발성 커뮤니티 앱**

물리적으로는 가깝지만 심리적으로 멀었던 주변 사람들을 잇는 디지털 징검다리 역할을 합니다.

---

## 배경

| 문제 | 설명 |
|------|------|
| 틈새 시간의 지루함 | 출퇴근 지하철, 맛집 웨이팅 등 짧은 대기 시간의 무료함을 해소할 창구 부족 |
| 상황적 공감 | "지금 이 지하철 너무 덥지 않나요?"처럼 같은 공간에 있는 사람만 즉각 공감할 수 있는 상황 데이터 공유 필요 |
| 심리적 거리감 | 옆 사람에게 직접 말 걸기 부담스러운 현대인을 위한 가벼운 소통 채널 필요 |

---

## 기술 스택

| 영역 | 기술 |
|------|------|
| 클라이언트 | Flutter (geolocator) |
| 백엔드 | NestJS (TypeScript) |
| ORM | Prisma |
| 실시간 통신 | Socket.io + Redis Pub/Sub |
| 위치 인메모리 | Redis Geospatial (GEOADD / GEOSEARCH) |
| 영구 저장소 | PostgreSQL + PostGIS |
| 인프라 | Docker / docker-compose |

---

## 핵심 기능

- **실시간 위치 동기화** — Flutter에서 5~10초 주기로 위경도 전송 → Redis GEOADD로 갱신
- **반경 100m 유저 조회** — Redis GEOSEARCH로 현재 위치 기준 주변 유저 조회
- **위치 기반 실시간 채팅** — 특정 방 입장 없이 주변 유저 전체에게 메시지 브로드캐스트 (Redis Pub/Sub)
- **영구 저장** — 이동 경로는 PostGIS, 1:1 대화 기록은 PostgreSQL에 저장

---

## 아키텍처

```
Flutter (geolocation)
   │  위도/경도 전송 (5~10초 주기)
   ▼
NestJS  /location
   ├─[INSERT]──→ PostgreSQL + PostGIS  (이동 경로 영구 저장)
   └─[GEOADD]──→ Redis Geospatial     (실시간 위치 갱신)
                      │ GEOSEARCH (반경 100m)
                      ▼
                 반경 내 유저 목록
                      │
WebSocket (Socket.io) ⇄ Redis Pub/Sub
   │  주변 유저 전체에 메시지 브로드캐스트
   ▼
Flutter  (지도 마커 표시 / 채팅 UI)
```

---

## 데이터 모델

### PostgreSQL (PostGIS)

```
user
├── user_id     serial       PK
├── nickname    varchar
└── created_at  timestamp

location
├── location_id  serial      PK
├── coords       geography   (PostGIS)
├── created_at   timestamp
└── user_id      serial      FK → user

chat_message
├── chat_message_id  serial  PK
├── content          text
├── sender_id        serial  FK → user
├── receiver_id      serial  FK → user
└── created_at       timestamp
```

### Redis Geospatial

```bash
# key: user:location / member: user_id

# 위치 저장 (경도 → 위도 순서 주의)
GEOADD user:location 126.9780 37.5665 "user_1"

# 반경 100m 유저 조회
GEOSEARCH user:location BYRADIUS 100 m FROM MEMBER "user_1" WITHDIST
```

---

## 진행 상황

| 단계 | 상태 |
|------|------|
| 기능 정의 및 아키텍처 설계 | ✅ 완료 |
| 인프라 구축 (Docker) | ✅ 완료 |
| DB 설계 (PostgreSQL / Redis) | ✅ 완료 |
| NestJS 백엔드 구축 | ✅ 완료 |
| Flutter 위치 동기화 구현 | 🔄 진행 중 |
| Redis + PostgreSQL 연동 | ⬜ 시작 전 |
| Flutter 지도 마커 구현 | ⬜ 시작 전 |
| Socket.io 구현 | ⬜ 시작 전 |
| Redis Pub/Sub 브로드캐스팅 | ⬜ 시작 전 |
| 메시지 영구 저장 | ⬜ 시작 전 |

---

## 관련 문서

- [이슈 & 해결책](./ISSUES.md)
