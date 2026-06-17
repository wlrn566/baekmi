import { Type } from 'class-transformer';
import { IsNumber, IsOptional, IsUUID, Max, Min } from 'class-validator';
import {
  DEFAULT_NEARBY_RADIUS_METERS,
  MAX_NEARBY_RADIUS_METERS,
} from '../locations.constants';

export class GetNearbyDto {
  @IsUUID()
  userId: string;

  // 쿼리스트링은 문자열로 들어오므로 @Type(() => Number)로 숫자 변환한다.
  // 전역 ValidationPipe의 transform: true가 이 변환을 처리한다.
  @IsOptional()
  @IsNumber()
  @Min(1)
  @Max(MAX_NEARBY_RADIUS_METERS)
  @Type(() => Number)
  radius: number = DEFAULT_NEARBY_RADIUS_METERS;
}
