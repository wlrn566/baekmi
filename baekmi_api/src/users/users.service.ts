import { Injectable } from '@nestjs/common';
import { RedisService } from '../redis/redis.service';
import { LOCATIONS_GEO_KEY } from '../locations/locations.constants';

@Injectable()
export class UsersService {
  constructor(private readonly redis: RedisService) {}

  async getLocation(userId: string) {
    const [position] = await this.redis.client.geopos(LOCATIONS_GEO_KEY, userId);
    if (!position) return null;

    const [longitude, latitude] = position;
    return { longitude: Number(longitude), latitude: Number(latitude) };
  }
}
