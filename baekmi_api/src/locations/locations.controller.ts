import { Body, Controller, Post } from '@nestjs/common';
import { LocationsService } from './locations.service';
import { CreateLocationDto } from './dto/create-location.dto';

@Controller('locations')
export class LocationsController {
  constructor(private readonly locationsService: LocationsService) {}

  /**
   * POST /locations
   * 앱이 보낸 좌표(userId, latitude, longitude, accuracy)를 받아 해당 사용자의 위치를 갱신한다.
   * userId 기준 upsert이므로 같은 사용자가 다시 호출하면 기존 위치가 최신 값으로 덮어써진다.
   * dto 검증(@IsUUID, 위경도 범위 등)은 main.ts에 등록된 전역 ValidationPipe가 처리한다.
   */
  @Post()
  create(@Body() dto: CreateLocationDto) {
    return this.locationsService.upsertLocation(dto);
  }
}
