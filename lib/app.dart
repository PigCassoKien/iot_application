import 'package:flutter/material.dart';
import 'features/clothesline/presentation/pages/home_page.dart';
import 'core/theme.dart';

class SmartClotheslineApp extends StatelessWidget {
  const SmartClotheslineApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Giàn Phơi Thông Minh',
      theme: appTheme,
      home: const HomePage(),
    );
  }
}