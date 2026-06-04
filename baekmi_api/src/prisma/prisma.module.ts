import { Global, Module } from '@nestjs/common';
import { PrismaService } from './prisma.service';

// @Global()로 선언하면 AppModule에 한 번만 import해도
// 모든 모듈에서 PrismaService를 inject할 수 있다
@Global()
@Module({
  providers: [PrismaService],
  exports: [PrismaService],
})
export class PrismaModule {}
