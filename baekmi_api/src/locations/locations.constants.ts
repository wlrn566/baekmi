// Redis 키 이름과 만료 기준값. Cron 정리 작업(locations-cleanup)에서도 동일한 키를 참조한다.
export const LOCATIONS_GEO_KEY = 'locations:geo';
export const LOCATIONS_LAST_SEEN_KEY = 'locations:last_seen';

// last_seen으로부터 이 값(초)보다 오래 지나면 만료된 것으로 간주한다.
export const LOCATION_TTL_SECONDS = 300;
