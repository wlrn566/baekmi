import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

/// 백엔드에 사용자를 식별시키기 위한 클라이언트 생성 UUID를 발급/보관한다.
/// 인증 시스템이 없는 동안의 임시 식별자이며, 인증 도입 시 교체될 예정이다
/// (docs/api-location-endpoint.md "사용자 식별" 섹션 참고).
class UserIdService {
  static const _key = 'user_id';

  static Future<String> getOrCreate() async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString(_key);
    if (existing != null) {
      debugPrint('[UserIdService] 기존 userId 사용: $existing');
      return existing;
    }

    final newId = const Uuid().v4();
    await prefs.setString(_key, newId);
    debugPrint('[UserIdService] 새 userId 생성: $newId');
    return newId;
  }
}
