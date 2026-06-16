import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

/// 백엔드에 사용자를 식별시키기 위한 클라이언트 생성 UUID를 발급/보관한다.
/// 인증 시스템이 없는 동안의 임시 식별자이며, 인증 도입 시 교체될 예정이다
/// (docs/api-location-endpoint.md "사용자 식별" 섹션 참고).
class UserIdService {
  static const _key = 'user_id';

  // userId는 프로세스 생애 동안 불변이므로, 위치 이벤트마다 매번 SharedPreferences를
  // 디스크에서 다시 읽지 않도록 한 번 읽은 값을 메모리에 캐시한다.
  static String? _cachedUserId;

  static Future<String> getOrCreate() async {
    if (_cachedUserId != null) return _cachedUserId!;

    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString(_key);
    if (existing != null) {
      if (kDebugMode) debugPrint('[UserIdService] 기존 userId 사용: $existing');
      _cachedUserId = existing;
      return existing;
    }

    final newId = const Uuid().v4();
    await prefs.setString(_key, newId);
    if (kDebugMode) debugPrint('[UserIdService] 새 userId 생성: $newId');
    _cachedUserId = newId;
    return newId;
  }
}
