import { Injectable } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';
import { RedisService } from '../redis/redis.service';
import { CreateLocationDto } from './dto/create-location.dto';
import { LOCATIONS_GEO_KEY, LOCATIONS_LAST_SEEN_KEY } from './locations.constants';

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

  // Redis에서 조회한다 (Postgres가 아님).
  // 만료된 사용자는 Cron이 Redis에서 지우므로, 여기서 없으면 "현재는 휴면/이탈 상태"로 판단할 수 있다.
  async getLocation(userId: string) {
    const [position] = await this.redis.client.geopos(LOCATIONS_GEO_KEY, userId);
    if (!position) return null;

    const [longitude, latitude] = position;
    return { longitude: Number(longitude), latitude: Number(latitude) };
  }
}
