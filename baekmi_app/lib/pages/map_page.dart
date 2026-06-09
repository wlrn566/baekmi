import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_naver_map/flutter_naver_map.dart';
import 'package:geolocator/geolocator.dart';

import '../services/location_service.dart';

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

  // dispose 시 명시적으로 cancel 해야 메모리 누수 및 불필요한 이벤트 처리를 막을 수 있음
  StreamSubscription<Position>? _positionSubscription;

  @override
  void initState() {
    super.initState();
    _initLocation();
  }

  /// 권한 확인 → 현재 위치로 카메라 이동 → 실시간 추적 시작 순으로 초기화한다.
  /// 지도가 준비되기 전에 위치를 받아도 _mapController가 null이면 카메라 이동이 무시되므로
  /// onMapReady 이후 _moveCamera가 호출될 수 있도록 비동기로 처리한다.
  Future<void> _initLocation() async {
    try {
      await LocationService.ensurePermission();

      // 초기 카메라 위치 설정을 위해 현재 위치를 1회 조회
      final position = await LocationService.getCurrentPosition();
      _moveCamera(position);

      // 이후 이동 시 지도 카메라가 따라오도록 스트림 구독
      _positionSubscription = LocationService.getPositionStream().listen(_moveCamera);
    } catch (e) {
      // 권한 거부, 위치 서비스 비활성화 등 사용자 조치가 필요한 경우 메시지로 안내
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
      }
    }
  }

  /// 주어진 위치로 지도 카메라를 이동하고 위치 오버레이를 갱신한다.
  /// _mapController가 null이면 (지도 아직 초기화 중) 아무것도 하지 않는다.
  void _moveCamera(Position position) {
    final target = NLatLng(position.latitude, position.longitude);

    _mapController?.updateCamera(
      NCameraUpdate.scrollAndZoomTo(target: target, zoom: 16),
    );

    // 내장 위치 오버레이 위치 갱신 (파란 점이 현재 위치를 따라감)
    _locationOverlay?.setPosition(target);
  }

  @override
  void dispose() {
    // 페이지가 사라질 때 위치 스트림 구독을 해제하지 않으면
    // 백그라운드에서도 GPS가 계속 작동해 배터리를 소모함
    _positionSubscription?.cancel();
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
        onMapReady: (controller) {
          _mapController = controller;
          _locationOverlay = controller.getLocationOverlay()
            ..setIsVisible(true);
        },
      ),
    );
  }
}
