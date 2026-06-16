import { Injectable, Logger } from '@nestjs/common';
import { Cron } from '@nestjs/schedule';
import { RedisService } from '../redis/redis.service';
import {
  LOCATIONS_GEO_KEY,
  LOCATIONS_LAST_SEEN_KEY,
  LOCATION_TTL_SECONDS,
} from './locations.constants';

// Redis GEO는 멤버 단위 TTL이 없어서, last_seen 기준으로 오래된 사용자를
// 주기적으로 찾아 geo/last_seen 양쪽에서 함께 지운다 (ISSUE-005 대응).
// 조회 시점에 정리하는 방식 대신 Cron을 택한 이유는 docs/redis-location-store.md 참고.
@Injectable()
export class LocationsCleanupService {
  private readonly logger = new Logger(LocationsCleanupService.name);

  constructor(private readonly redis: RedisService) {}

  // '*/30 * * * * *' — 6필드(초 분 시 일 월 요일) 중 맨 앞이 초 단위.
  // 즉 "매 30초마다(0초, 30초 시점에)" 실행한다는 뜻.
  @Cron('*/30 * * * * *')
  async removeStaleLocations() {
    // 1. 앱 서버 시각이 아니라 Redis 서버 시각을 기준으로 삼는다 (인스턴스 간 clock skew 방지).
    const [seconds] = await this.redis.client.time();

    // 2. "지금으로부터 TTL_SECONDS(300초)보다 더 전"을 만료 기준 시각으로 계산.
    const threshold = Number(seconds) - LOCATION_TTL_SECONDS;

    // 3. last_seen 정렬 집합에서 score(마지막 갱신 시각)가
    //    -inf(가장 오래된 값)부터 threshold까지인 userId들을 찾는다 = 오래돼서 만료된 사용자들.
    const staleUserIds = await this.redis.client.zrangebyscore(
      LOCATIONS_LAST_SEEN_KEY,
      '-inf',
      threshold,
    );

    // 4. 만료된 사용자가 없으면 더 할 일이 없다.
    if (staleUserIds.length === 0) return;

    // 5. last_seen과 geo 양쪽에서 같은 userId들을 제거해 Redis 상태를 정리한다.
    await this.redis.client.zrem(LOCATIONS_LAST_SEEN_KEY, ...staleUserIds);
    await this.redis.client.zrem(LOCATIONS_GEO_KEY, ...staleUserIds);

    this.logger.log(`만료된 위치 ${staleUserIds.length}건 정리: ${staleUserIds.join(', ')}`);
  }
}
