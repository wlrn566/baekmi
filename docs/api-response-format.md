# API 응답 형식

모든 엔드포인트는 동일한 구조의 JSON을 반환한다.

## 구현 상태: 완료

| 파일 | 역할 |
|------|------|
| `baekmi_api/src/common/interceptors/response.interceptor.ts` | 성공 응답 래핑 (전역 인터셉터) |
| `baekmi_api/src/common/filters/http-exception.filter.ts` | 에러 응답 통일 (전역 예외 필터) |

`main.ts`에 `useGlobalInterceptors`, `useGlobalFilters`로 전역 등록되어 모든 엔드포인트에 자동 적용된다.

## 응답 구조

```typescript
{
  success: boolean;  // 성공 여부
  data: T | null;    // 성공 시 응답 데이터, 실패 시 null
  message: string | null;  // 성공 시 null, 실패 시 에러 메시지
}
```

## 성공 응답

HTTP 상태 코드 2xx와 함께 반환된다.

```json
{
  "success": true,
  "data": { ... },
  "message": null
}
```

### 예시

**`GET /users/:userId/location`**
```json
{
  "success": true,
  "data": {
    "longitude": 126.977998316288,
    "latitude": 37.566500306287246
  },
  "message": null
}
```

**`GET /locations/nearby?userId=...`**
```json
{
  "success": true,
  "data": [
    {
      "userId": "550e8400-e29b-41d4-a716-446655440002",
      "latitude": 37.566599160412466,
      "longitude": 126.97810024023056,
      "distance": 14.2
    }
  ],
  "message": null
}
```

## 에러 응답

HTTP 상태 코드 4xx/5xx와 함께 반환된다.

```json
{
  "success": false,
  "data": null,
  "message": "에러 메시지"
}
```

### 예시

**404 — 리소스 없음**
```json
{
  "success": false,
  "data": null,
  "message": "해당 사용자의 위치 정보를 찾을 수 없습니다."
}
```

**400 — 유효성 검사 실패**

`class-validator`의 ValidationPipe 에러는 메시지가 배열로 오므로 `, `로 join해서 단일 문자열로 반환한다.

```json
{
  "success": false,
  "data": null,
  "message": "userId must be a UUID, latitude must not be greater than 90, ..."
}
```

## 구현 방식

NestJS의 두 레이어로 처리한다.

- **ResponseInterceptor**: 성공 흐름(`next.handle()`)을 `map`으로 가로채 `{ success, data, message }` 형태로 감싼다.
- **HttpExceptionFilter**: `HttpException`(NotFoundException, BadRequestException 등)을 잡아 동일한 구조의 에러 응답을 반환한다.

인터셉터에서 `catchError`로 에러까지 함께 처리하는 방법도 있으나, HTTP 상태 코드를 Response에 직접 써야 해서 복잡해진다. 역할을 분리하는 현재 구조가 더 명확하다.
