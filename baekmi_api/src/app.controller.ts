import { Controller, Get } from '@nestjs/common';
import { AppService } from './app.service';

@Controller()
export class AppController {
  constructor(private readonly appService: AppService) {}

  // GET / — 서버 헬스체크용 기본 라우터
  @Get()
  getHello(): string {
    return this.appService.getHello();
  }
}
