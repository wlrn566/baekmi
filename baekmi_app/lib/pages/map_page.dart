import 'package:flutter/material.dart';
import 'package:flutter_naver_map/flutter_naver_map.dart';

class MapPage extends StatelessWidget {
  const MapPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: NaverMap(
        options: const NaverMapViewOptions(
          initialCameraPosition: NCameraPosition(
            target: NLatLng(37.5665, 126.9780),
            zoom: 14,
          ),
        ),
      ),
    );
  }
}
