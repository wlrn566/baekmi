import { Body, Controller, Get, Post, Query } from '@nestjs/common';
import { LocationsService } from './locations.service';
import { CreateLocationDto } from './dto/create-location.dto';
import { GetNearbyDto } from './dto/get-nearby.dto';

@Controller('locations')
export class LocationsController {
  constructor(private readonly locationsService: LocationsService) {}

  /**
   * POST /locations
   * 앱이 보낸 좌표(userId, latitude, longitude, accuracy)를 받아 해당 사용자의 위치를 갱신한다.
   * userId 기준 upsert이므로 같은 사용자가 다시 호출하면 기존 위치가 최신 값으로 덮어써진다.
   */
  @Post()
  create(@Body() dto: CreateLocationDto) {
    return this.locationsService.upsertLocation(dto);
  }

  /**
   * GET /locations/nearby?userId=...&radius=...
   * userId 기준 반경 radius(기본 100m) 이내 사용자 목록을 반환한다.
   * 결과에서 요청자 자신은 제외된다 (ISSUE-006).
   * userId가 Redis에 없으면(위치 미전송/만료) 빈 배열을 반환한다.
   */
  @Get('nearby')
  findNearby(@Query() dto: GetNearbyDto) {
    return this.locationsService.getNearbyLocations(dto.userId, dto.radius);
  }
}
