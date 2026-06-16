import { Global, Module } from '@nestjs/common';
import { RedisService } from './redis.service';

// @Global()로 선언하면 AppModule에 한 번만 import해도
// 모든 모듈에서 RedisService를 inject할 수 있다 (PrismaModule과 동일한 패턴)
@Global()
@Module({
  providers: [RedisService],
  exports: [RedisService],
})
export class RedisModule {}
