import 'package:flutter/material.dart';
import 'app.dart';
import 'core/services/guardian_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeGuardianService();
  runApp(const TrueNorthApp());
}