import { Injectable, OnModuleInit, OnModuleDestroy } from '@nestjs/common';
import { PrismaPg } from '@prisma/adapter-pg';
import { PrismaClient } from '../../generated/prisma/client';

@Injectable()
export class PrismaService implements OnModuleInit, OnModuleDestroy {
  readonly client: PrismaClient;

  constructor() {
    // Prisma v7에서는 schema.prisma에 url을 명시하지 않고
    // 런타임에 adapter를 통해 DB 연결을 주입한다
    const adapter = new PrismaPg({
      connectionString: process.env.DATABASE_URL,
    });
    this.client = new PrismaClient({ adapter });
  }

  // NestJS 모듈 초기화 시 DB 연결
  async onModuleInit() {
    await this.client.$connect();
  }

  // NestJS 앱 종료 시 DB 연결 해제
  async onModuleDestroy() {
    await this.client.$disconnect();
  }
}
