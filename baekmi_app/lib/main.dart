import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_naver_map/flutter_naver_map.dart';
import 'package:provider/provider.dart';

import 'pages/map_page.dart';
import 'providers/location_provider.dart';
import 'providers/nearby_provider.dart';
import 'services/dio_client.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: '.env');
  DioClient.init();
  await FlutterNaverMap().init(
    clientId: dotenv.get('NAVER_MAP_CLIENT_ID'),
    onAuthFailed: (ex) => debugPrint('Naver Map auth failed: $ex'),
  );
  runApp(const BaekmiApp());
}

class BaekmiApp extends StatelessWidget {
  const BaekmiApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => LocationProvider()),
        ChangeNotifierProvider(create: (_) => NearbyProvider()),
      ],
      child: MaterialApp(
        title: '백미',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        ),
        home: const MapPage(),
      ),
    );
  }
}
