import 'package:dio/dio.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

/// 앱 전체에서 공유하는 Dio 싱글톤.
/// 백엔드를 호출하는 모든 API 서비스(LocationApiService 등)는
/// 각자 Dio를 만들지 않고 여기서 가져다 쓴다.
class DioClient {
  static late final Dio instance;

  /// 앱 시작 시 main()에서 dotenv.load() 이후 한 번만 호출한다.
  static void init() {
    instance = Dio(BaseOptions(baseUrl: dotenv.get('API_BASE_URL')));
  }
}
