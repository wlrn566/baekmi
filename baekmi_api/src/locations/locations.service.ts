import { Injectable } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';
import { RedisService } from '../redis/redis.service';
import { CreateLocationDto } from './dto/create-location.dto';
import {
  LOCATIONS_GEO_KEY,
  LOCATIONS_LAST_SEEN_KEY,
} from './locations.constants';

@Injectable()
export class LocationsService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly redis: RedisService,
  ) {}

  // 위치 히스토리를 누적하지 않고 사용자별 최신 위치 1건만 유지한다 (휘발성 컨셉).
  // userId(@unique)를 키로 upsert하므로 같은 사용자가 다시 보내면 기존 행이 갱신된다.
  // Postgres 외에 Redis(GEOADD + ZADD)에도 같은 좌표를 반영한다 (dual-write).
  async upsertLocation(dto: CreateLocationDto) {
    const location = await this.prisma.client.location.upsert({
      where: { userId: dto.userId },
      update: {
        latitude: dto.latitude,
        longitude: dto.longitude,
        accuracy: dto.accuracy,
      },
      create: {
        userId: dto.userId,
        latitude: dto.latitude,
        longitude: dto.longitude,
        accuracy: dto.accuracy,
      },
    });

    // 앱 서버 시각 대신 Redis 서버 시각을 score로 써서 인스턴스 간 시계 오차(clock skew) 영향을 없앤다.
    const [seconds] = await this.redis.client.time();

    // GEOADD와 ZADD를 MULTI로 묶어 원자적으로 실행한다.
    // 둘이 분리되어 있으면 중간에 실패할 경우 last_seen이 갱신되지 않아
    // Cron이 방금 들어온 좌표를 "오래된 데이터"로 잘못 판단해 지울 수 있다.
    await this.redis.client
      .multi()
      .geoadd(LOCATIONS_GEO_KEY, dto.longitude, dto.latitude, dto.userId)
      .zadd(LOCATIONS_LAST_SEEN_KEY, seconds, dto.userId)
      .exec();

    return location;
  }

  // GEOSEARCH로 반경 내 사용자 목록을 반환한다.
  // FROMMEMBER 대신 FROMLONLAT을 쓰는 이유: FROMMEMBER는 대상 멤버가 없을 때 Redis 에러를 던지므로
  // catch로 모든 에러를 삼켜야 하는데, 이러면 Redis 장애/타임아웃도 "아무도 없음"으로 오인된다.
  // GEOPOS로 기준 좌표를 먼저 확인 → 없으면 빈 배열 반환 / 있으면 FROMLONLAT으로 GEOSEARCH.
  // ioredis 5의 geosearch() 타입 오버로드가 WITHDIST+WITHCOORD 조합을 커버하지 않아
  // as any로 우회 후 결과를 직접 파싱한다 (docs/api-nearby-search.md 참고).
  async getNearbyLocations(userId: string, radius: number) {
    const [position] = await this.redis.client.geopos(LOCATIONS_GEO_KEY, userId);
    if (!position) return [];

    const [longitude, latitude] = position;
    const raw = await (this.redis.client as any)
      .geosearch(
        LOCATIONS_GEO_KEY,
        'FROMLONLAT', longitude, latitude,
        'BYRADIUS', radius, 'm',
        'ASC', 'COUNT', 100,
        'WITHDIST', 'WITHCOORD',
      ) as [string, string, [string, string]][];

    // FROMLONLAT 기반이어도 동일 좌표의 본인이 포함될 수 있으므로 명시적으로 제외한다 (ISSUE-006).
    return raw
      .filter(([memberId]) => memberId !== userId)
      .map(([memberId, distance, [lon, lat]]) => ({
        userId: memberId,
        latitude: Number(lat),
        longitude: Number(lon),
        distance: Number(distance),
      }));
  }
}
