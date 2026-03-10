import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:true_north/core/models/guardian_session.dart';

class SessionRepository {
  static const String _key = 'guardian_session_data';

  Future<void> saveSession(GuardianSession session) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = jsonEncode(session.toMap());
    await prefs.setString(_key, jsonString);
  }

  Future<GuardianSession?> getSession() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString(_key);
    
    if (jsonString == null) return null;

    try {
      final Map<String, dynamic> map = jsonDecode(jsonString);
      return GuardianSession.fromMap(map);
    } catch (e) {
      print("🚨 Repository: Failed to decode session: $e");
      return null;
    }
  }

  Future<void> clearSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}