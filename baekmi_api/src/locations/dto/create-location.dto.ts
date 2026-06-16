import { IsNumber, IsOptional, IsUUID, Max, Min } from 'class-validator';

export class CreateLocationDto {
  // 인증 시스템이 없어 앱이 생성한 클라이언트 UUID로 사용자를 식별한다.
  // 추후 인증이 도입되면 인증된 사용자 ID로 교체해야 한다.
  @IsUUID()
  userId: string;

  @IsNumber()
  @Min(-90)
  @Max(90)
  latitude: number;

  @IsNumber()
  @Min(-180)
  @Max(180)
  longitude: number;

  @IsOptional()
  @IsNumber()
  accuracy?: number;
}
