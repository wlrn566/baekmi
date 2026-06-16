import 'package:flutter/material.dart';
import 'package:flutter_naver_map/flutter_naver_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';

import '../providers/location_provider.dart';

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

  @override
  void initState() {
    super.initState();
    // listen: false — initState에서는 위젯이 아직 빌드 트리에 없어 watch를 쓸 수 없다.
    _locationProvider = context.read<LocationProvider>()..addListener(_onLocationChanged);
    _locationProvider.init();
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

  /// 주어진 위치로 지도 카메라를 이동하고 위치 오버레이를 갱신한다.
  /// onMapReady 이전에 호출된 경우 _pendingPosition에 버퍼링해 준비 후 적용한다.
  void _moveCamera(Position position) {
    if (_mapController == null) {
      _pendingPosition = position;
      return;
    }

    final NLatLng target = NLatLng(position.latitude, position.longitude);

    _mapController?.updateCamera(
      NCameraUpdate.scrollAndZoomTo(target: target, zoom: 16),
    );

    // 내장 위치 오버레이 위치 갱신 (파란 점이 현재 위치를 따라감)
    _locationOverlay?.setPosition(target);
  }

  @override
  void dispose() {
    // Provider 자체는 main.dart의 ChangeNotifierProvider가 소유하므로 여기서 dispose하지 않고,
    // 이 위젯이 등록한 리스너만 해제한다.
    _locationProvider.removeListener(_onLocationChanged);
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
            zoom: 14,
          ),
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
