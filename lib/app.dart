import 'package:flutter/material.dart';
import 'features/guardian/presentation/guardian_screen.dart';

class TrueNorthApp extends StatelessWidget {
  const TrueNorthApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'True North',
      theme: ThemeData(
        scaffoldBackgroundColor: const Color(0xFF1A1A24), 
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFFFFD700), 
          surface: Color(0xFF232330),
        ),
        useMaterial3: true,
      ),
      home: const GuardianScreen(),
    );
  }
}