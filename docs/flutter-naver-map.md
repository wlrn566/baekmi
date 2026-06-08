# Flutter 네이버 지도 SDK 연동 가이드

## 패키지

- [flutter_naver_map](https://pub.dev/packages/flutter_naver_map) 1.4.4
- [flutter_dotenv](https://pub.dev/packages/flutter_dotenv) 6.0.1

**요구사항**
- Android: minSdk 23 이상
- iOS: 12.0 이상 (추후 지원 예정)

> 현재 Android 전용으로 연동되어 있으며 iOS 설정은 추후 진행 예정이다.

---

## 1. Naver Cloud Platform Client ID 발급

1. https://console.ncloud.com 접속
2. 서비스 검색 → **Maps** → **Mobile Dynamic Map** 신청
3. Application 등록 시 Android 패키지명 입력: `com.baekmi.baekmi_app`
4. 등록 완료 후 **인증정보**에서 Client ID 확인

---

## 2. 환경변수 설정

`baekmi_app/.env.example`을 복사해서 값을 채운다.

```bash
cp baekmi_app/.env.example baekmi_app/.env
```

```
NAVER_MAP_CLIENT_ID=발급받은_Client_ID
```

`baekmi_app/.env`는 git에 올라가지 않는다.

---

## 3. Android 설정

### `android/app/src/main/AndroidManifest.xml`

인터넷 권한 추가:
```xml
<uses-permission android:name="android.permission.INTERNET" />
```

### `android/app/build.gradle.kts`

flutter_naver_map 최소 SDK 요구사항:
```kotlin
defaultConfig {
    minSdk = 23
}
```

---

## 4. Flutter 코드

### SDK 초기화 (`lib/main.dart`)

```dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: '.env');
  await FlutterNaverMap().init(
    clientId: dotenv.get('NAVER_MAP_CLIENT_ID'),
    onAuthFailed: (ex) => debugPrint('Naver Map auth failed: $ex'),
  );
  runApp(const BaekmiApp());
}
```

### 지도 위젯 (`lib/pages/map_page.dart`)

```dart
NaverMap(
  options: const NaverMapViewOptions(
    initialCameraPosition: NCameraPosition(
      target: NLatLng(37.5665, 126.9780), // 서울 시청
      zoom: 14,
    ),
  ),
)
```

---

## 5. 실행

```bash
cd baekmi_app
flutter pub get
flutter run
```
