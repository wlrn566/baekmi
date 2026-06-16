import { Injectable } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';
import { CreateLocationDto } from './dto/create-location.dto';

@Injectable()
export class LocationsService {
  constructor(private readonly prisma: PrismaService) {}

  // 위치 히스토리를 누적하지 않고 사용자별 최신 위치 1건만 유지한다 (휘발성 컨셉).
  // userId(@unique)를 키로 upsert하므로 같은 사용자가 다시 보내면 기존 행이 갱신된다.
  upsertLocation(dto: CreateLocationDto) {
    return this.prisma.client.location.upsert({
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
  }
}
