import { Module } from '@nestjs/common';
import { LocationsController } from './locations.controller';
import { LocationsService } from './locations.service';
import { LocationsCleanupService } from './locations-cleanup.service';

@Module({
  controllers: [LocationsController],
  providers: [LocationsService, LocationsCleanupService],
})
export class LocationsModule {}
