import {
  Controller,
  Get,
  NotFoundException,
  Param,
  ParseUUIDPipe,
} from '@nestjs/common';
import { UsersService } from './users.service';

@Controller('users')
export class UsersController {
  constructor(private readonly usersService: UsersService) {}

  /**
   * GET /users/:userId/location
   * Redis에 남아있는 해당 사용자의 최신 좌표를 반환한다.
   * Cron이 만료된 사용자를 Redis에서 지우므로, 결과가 없으면 만료/미전송 상태로 간주해 404를 반환한다.
   */
  @Get(':userId/location')
  async findLocation(@Param('userId', new ParseUUIDPipe()) userId: string) {
    const location = await this.usersService.getLocation(userId);
    if (!location) {
      throw new NotFoundException('해당 사용자의 위치 정보를 찾을 수 없습니다.');
    }
    return location;
  }
}
