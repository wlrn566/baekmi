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

  // _cachedUserId가 채워지기 전에 getOrCreate()가 짧은 간격으로 여러 번 호출되면
  // (예: 위치 스트림 이벤트가 연달아 들어오는 경우) 각 호출이 따로 UUID를 생성/저장해
  // 서로 다른 userId가 만들어질 수 있다. 진행 중인 Future를 캐시해 동시 호출을 하나로 합친다.
  static Future<String>? _inFlight;

  static Future<String> getOrCreate() {
    if (_cachedUserId != null) return Future.value(_cachedUserId!);
    return _inFlight ??= _load();
  }

  static Future<String> _load() async {
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
