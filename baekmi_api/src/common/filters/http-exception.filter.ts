import {
  ArgumentsHost,
  Catch,
  ExceptionFilter,
  HttpException,
} from '@nestjs/common';
import { Response } from 'express';

// HttpException(NotFoundException, BadRequestException 등)을 잡아
// 에러 응답을 { success: false, data: null, message } 형태로 통일한다.
// main.ts에 전역 필터로 등록되어 모든 엔드포인트에 적용된다.
@Catch(HttpException)
export class HttpExceptionFilter implements ExceptionFilter {
  catch(exception: HttpException, host: ArgumentsHost) {
    const ctx = host.switchToHttp();
    const response = ctx.getResponse<Response>();
    const status = exception.getStatus();
    const exceptionResponse = exception.getResponse();

    // ValidationPipe 에러는 message가 string[] 로 오므로 join해서 단일 문자열로 만든다.
    let message: string;
    if (typeof exceptionResponse === 'string') {
      message = exceptionResponse;
    } else {
      const body = exceptionResponse as Record<string, unknown>;
      message = Array.isArray(body.message)
        ? (body.message as string[]).join(', ')
        : (body.message as string);
    }

    response.status(status).json({
      success: false,
      data: null,
      message,
    });
  }
}
