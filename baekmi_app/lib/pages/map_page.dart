import 'package:flutter/material.dart';
import 'package:flutter_naver_map/flutter_naver_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';

import '../providers/location_provider.dart';
import '../providers/nearby_provider.dart';

class MapPage extends StatefulWidget {
  const MapPage({super.key});

  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> {
  // onMapReady 콜백에서 주입받아 카메라 제어 및 오버레이 접근에 사용
  NaverMapController? _mapController;

  // 현재 위치를 지도에 표시하는 내장 오버레이 (파란 점)
  NLocationOverlay? _locationOverlay;

  // onMapReady 이전에 위치를 수신한 경우 지도 준비 후 적용하기 위해 버퍼링
  Position? _pendingPosition;

  late LocationProvider _locationProvider;
  late NearbyProvider _nearbyProvider;

  NCircleOverlay? _radiusCircle;

  // 매 폴링마다 fromWidget 래스터라이즈를 반복하지 않도록 최초 1회만 생성해 재사용한다.
  NOverlayImage? _markerIcon;

  @override
  void initState() {
    super.initState();
    // listen: false — initState에서는 위젯이 아직 빌드 트리에 없어 watch를 쓸 수 없다.
    _locationProvider = context.read<LocationProvider>()..addListener(_onLocationChanged);
    _locationProvider.init();

    // addListener는 VoidCallback(void Function())을 기대하므로 async 메서드를 직접 넘기지 않는다.
    _nearbyProvider = context.read<NearbyProvider>()..addListener(_nearbyUsersListener);
    _nearbyProvider.init();
  }

  /// LocationProvider의 상태(position/errorMessage)가 바뀔 때마다 호출된다.
  /// View는 ViewModel이 들고 있는 상태를 화면에 반영하는 역할만 한다.
  void _onLocationChanged() {
    final position = _locationProvider.position;
    if (position != null) {
      _moveCamera(position);
    }

    final errorMessage = _locationProvider.errorMessage;
    if (errorMessage != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(errorMessage)));
    }
  }

  /// addListener가 기대하는 VoidCallback 래퍼 — async 메서드를 직접 넘기면 타입 불일치가 발생한다.
  void _nearbyUsersListener() => _onNearbyUsersChanged();

  /// 주변 사람 목록이 바뀔 때마다 마커를 전체 교체한다.
  /// clearOverlays(marker 타입)는 NLocationOverlay(파란 점)에 영향을 주지 않는다.
  /// clearOverlays는 fromWidget await 이후에 호출해 아이콘 렌더링 시간 동안 깜빡임을 막는다.
  Future<void> _onNearbyUsersChanged() async {
    if (_mapController == null) return;

    if (_nearbyProvider.nearbyUsers.isEmpty) {
      _mapController!.clearOverlays(type: NOverlayType.marker);
      return;
    }

    _markerIcon ??= await NOverlayImage.fromWidget(
      widget: SizedBox(
        width: 32,
        height: 32,
        child: Center(
          child: Container(
            width: 18,
            height: 18,
            decoration: BoxDecoration(
              color: Colors.red,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2.5),
              boxShadow: [
                BoxShadow(
                  color: Colors.red.withValues(alpha: 0.45),
                  blurRadius: 8,
                  spreadRadius: 2,
                ),
              ],
            ),
          ),
        ),
      ),
      size: const Size(32, 32),
      context: context,
    );

    if (!mounted) return;
    final icon = _markerIcon!;

    final markers = _nearbyProvider.nearbyUsers
        .map((u) => NMarker(id: u.userId, position: NLatLng(u.latitude, u.longitude))
          ..setIcon(icon))
        .toSet();

    _mapController!.clearOverlays(type: NOverlayType.marker);
    _mapController!.addOverlayAll(markers);
  }

  /// 주어진 위치로 지도 카메라를 이동하고 위치 오버레이를 갱신한다.
  /// onMapReady 이전에 호출된 경우 _pendingPosition에 버퍼링해 준비 후 적용한다.
  void _moveCamera(Position position) {
    if (_mapController == null) {
      _pendingPosition = position;
      return;
    }

    final NLatLng target = NLatLng(position.latitude, position.longitude);

    _mapController?.updateCamera(
      NCameraUpdate.scrollAndZoomTo(target: target, zoom: 17),
    );

    // 내장 위치 오버레이 위치 갱신 (파란 점이 현재 위치를 따라감)
    _locationOverlay?.setPosition(target);

    // NCircleOverlay는 특정 위경도에 고정된 지리적 오버레이다.
    // 카메라가 내 위치를 항상 중앙에 두더라도, 원 자체의 좌표를 갱신하지 않으면
    // 내가 이동했을 때 원이 이전 위치에 남아 화면 중앙에서 벗어난다.
    // 따라서 위치가 바뀔 때마다 setCenter로 원의 중심도 함께 옮겨준다.
    if (_radiusCircle == null) {
      _radiusCircle = NCircleOverlay(
        id: 'radius_circle',
        center: target,
        radius: 100,
        color: Colors.blue.withValues(alpha: 0.08),
        outlineColor: Colors.blue.withValues(alpha: 0.4),
        outlineWidth: 1,
      );
      _mapController?.addOverlay(_radiusCircle!);
    } else {
      _radiusCircle!.setCenter(target);
    }
  }

  @override
  void dispose() {
    // Provider 자체는 main.dart의 ChangeNotifierProvider가 소유하므로 여기서 dispose하지 않고,
    // 이 위젯이 등록한 리스너만 해제한다.
    _locationProvider.removeListener(_onLocationChanged);
    _nearbyProvider.removeListener(_nearbyUsersListener);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: NaverMap(
        options: const NaverMapViewOptions(
          // 위치를 받아오기 전 초기 화면으로 서울 시청을 보여줌
          initialCameraPosition: NCameraPosition(
            target: NLatLng(37.5665, 126.9780),
            zoom: 17,
          ),
          maxZoom: 18,
          minZoom: 16,
        ),
        // 지도 준비 완료 후 컨트롤러 저장, 위치 오버레이를 꺼내 표시 상태로 설정
        // 버퍼링된 위치가 있으면 즉시 적용
        onMapReady: (controller) {
          _mapController = controller;
          _locationOverlay = controller.getLocationOverlay()
            ..setIsVisible(true);
          if (_pendingPosition != null) {
            _moveCamera(_pendingPosition!);
            _pendingPosition = null;
          }
        },
      ),
    );
  }
}
