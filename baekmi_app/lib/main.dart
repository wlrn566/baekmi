import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_naver_map/flutter_naver_map.dart';

import 'pages/map_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: '.env');
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
    return MaterialApp(
      title: '백미',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
      home: const MapPage(),
    );
  }
}
