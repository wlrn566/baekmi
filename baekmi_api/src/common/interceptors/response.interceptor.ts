import {
  CallHandler,
  ExecutionContext,
  Injectable,
  NestInterceptor,
} from '@nestjs/common';
import { Observable } from 'rxjs';
import { map } from 'rxjs/operators';

// 성공 응답을 { success: true, data, message: null } 형태로 감싼다.
// main.ts에 전역 인터셉터로 등록되어 모든 엔드포인트에 적용된다.
@Injectable()
export class ResponseInterceptor<T> implements NestInterceptor<T, unknown> {
  intercept(_context: ExecutionContext, next: CallHandler<T>): Observable<unknown> {
    return next.handle().pipe(
      map((data) => ({
        success: true,
        data,
        message: null,
      })),
    );
  }
}
