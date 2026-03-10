import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:geocoding/geocoding.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:true_north/core/models/guardian_session.dart';
import 'package:true_north/core/session_repository.dart';

class GuardianScreen extends StatefulWidget {
  const GuardianScreen({super.key});

  @override
  State<GuardianScreen> createState() => _GuardianScreenState();
}

class _GuardianScreenState extends State<GuardianScreen> {
  bool isGuardianActive = false;
  bool _isValidating = false;
  GuardianSession? _guardianSession;

  // Dedicated controllers - these are the ONLY source of truth for text
  final TextEditingController _homeController = TextEditingController();
  final TextEditingController _anchorController = TextEditingController();
  final TextEditingController _landingController = TextEditingController();

  TimeOfDay _leaveTime = const TimeOfDay(hour: 23, minute: 0);
  bool _hydrationEnabled = true;
  Position? _homePoint; 

  @override
  void initState() {
    super.initState();
    _checkArrivalStatus();
    _setupServiceConnection();
  }

  void _setupServiceConnection() async {
    final service = FlutterBackgroundService();
    
    // 1. Check if already running and ask for state
    if (await service.isRunning()) {
      setState(() => isGuardianActive = true);
      service.invoke('request_state');
    }

    // 2. Listen for real-time updates
    service.on('updateUI').listen((event) {
      if (event != null && mounted) {
        print("📡 [UI] Received update from service!"); // <-- Add this to prove it's alive

        try {
          // SAFE CAST: Forces the dynamic map into the exact format fromMap needs
          final safeMap = Map<String, dynamic>.from(event);
          
print(event);

          setState(() {
            _guardianSession = GuardianSession.fromMap(safeMap);
            isGuardianActive = true;
          });
        } catch (e) {
          print("🚨 [UI] Failed to parse session data: $e"); // <-- Catches any missing keys
        }
      }
    });
  }

  @override
  void dispose() {
    _homeController.dispose();
    _anchorController.dispose();
    _landingController.dispose();
    super.dispose();
  }

  Future<void> _checkArrivalStatus() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool('show_arrival_popup') ?? false) {
      String message = prefs.getString('landing_message') ?? "You made it home.";
      if (context.mounted) _showArrivalDialog(context, message);
      await prefs.setBool('show_arrival_popup', false); 
    }
  }

  void _showArrivalDialog(BuildContext context, String landingMessage) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E3F), 
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Icon(Icons.check_circle_outline, color: Color(0xFFFFD700), size: 50),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text("Mission Accomplished", style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            Text(landingMessage, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70)),
          ],
        ),
        actions: [
          Center(
            child: TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("STAND DOWN", style: TextStyle(color: Color(0xFFFFD700), fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }

  // THE NEW, STRICT POSTCODE VALIDATOR
  Future<bool> _isPostcodeValid(String address) async {
    String cleanAddress = address.trim().toUpperCase();

    // 1. Strict RegEx check for UK Postcodes
    final RegExp ukPostcodeRegex = RegExp(r"^[A-Z]{1,2}\d[A-Z\d]? ?\d[A-Z]{2}$");
    if (!ukPostcodeRegex.hasMatch(cleanAddress)) {
      return false; 
    }

    // 2. Network Geocoding Check
    try {
      List<Location> locations = await locationFromAddress("$cleanAddress, UK")
          .timeout(const Duration(seconds: 5));
          
      if (locations.isNotEmpty) {
        _homePoint = Position(
          latitude: locations.first.latitude,
          longitude: locations.first.longitude,
          timestamp: DateTime.now(),
          accuracy: 0, altitude: 0, heading: 0, speed: 0, speedAccuracy: 0,
          altitudeAccuracy: 0, headingAccuracy: 0,
        );
        return true;
      }
      return false;
    } catch (e) {
      return false; 
    }
  }

  void _activateGuardian() async {
    final now = DateTime.now();
    
    // 1. Calculate the target time
    DateTime targetDateTime = DateTime(
      now.year, now.month, now.day, 
      _leaveTime.hour, _leaveTime.minute
    );
    if (targetDateTime.isBefore(now)) {
      targetDateTime = targetDateTime.add(const Duration(days: 1));
    }

    // 2. Create the "Source of Truth" Object
    final session = GuardianSession(
      activationTime: now,
      targetDepartureTime: targetDateTime,
      homeLat: _homePoint!.latitude,
      homeLng: _homePoint!.longitude,
      anchorReason: _anchorController.text.isNotEmpty ? _anchorController.text : "you need to be sharp tomorrow",
      homeReminderText: _landingController.text.isNotEmpty ? _landingController.text : "Welcome home. The Guardian is standing down."
    );

    // 3. Save to Repository
    await SessionRepository().saveSession(session);

    // 4. Update UI State & Close Panel
    if (!context.mounted) return;
    Navigator.pop(context); 
    setState(() {
      isGuardianActive = true;
      _guardianSession = session;
    });

    // 5. Start the Engine
    final service = FlutterBackgroundService();
    await service.startService();
    service.invoke('setAsForeground');
  }

  Future<void> _deactivateGuardian() async {
    setState(() {
      isGuardianActive = false;
      _guardianSession = null;
    });
    
    // Clear data so it doesn't resume on next app open
    await SessionRepository().clearSession();
    FlutterBackgroundService().invoke('stopService');
  }

  Future<void> _showBackgroundRationaleDialog() async {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E3F),
        title: const Text('Always-On Protection', style: TextStyle(color: Colors.white)),
        content: const Text(
            'To monitor your success even when your phone is in your pocket, '
            'the Guardian needs permission to "Allow all the time." \n\nPlease select this on the next screen.',
            style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('UNDERSTOOD', style: TextStyle(color: Color(0xFFFFD700))),
          ),
        ],
      ),
    );
  }

  Widget _buildCustomField({required TextEditingController controller, required String label, required String hint, IconData? icon}) {
    return TextField(
      controller: controller,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Color(0xFFFFD700)),
        hintText: hint,
        hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
        prefixIcon: icon != null ? Icon(icon, color: const Color(0xFFFFD700)) : null,
        enabledBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
        focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFFFFD700))),
      ),
    );
  }

  void _showPreFlightChecklist() {
    String errorMessage = ''; 

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E3F),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (BuildContext sheetContext) {
        return StatefulBuilder(
            builder: (BuildContext context, StateSetter setSheetState) {
          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom + 24,
              left: 24, right: 24, top: 24,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('THE EVENING SCRIPT', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFFFFD700), letterSpacing: 2)),
                  const SizedBox(height: 20),
                  
                  _buildCustomField(controller: _homeController, label: 'Home Postcode', hint: 'e.g. SW1A 1AA', icon: Icons.home),
                  const SizedBox(height: 10),
                  
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Intended Departure Time', style: TextStyle(color: Colors.white)),
                    subtitle: Text(_leaveTime.format(context), style: const TextStyle(color: Colors.white54)),
                    trailing: const Icon(Icons.access_time, color: Color(0xFFFFD700)),
                    onTap: () async {
                      TimeOfDay? picked = await showTimePicker(context: context, initialTime: _leaveTime);
                      if (picked != null) setSheetState(() => _leaveTime = picked);
                    },
                  ),
                  
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Hourly Hydration', style: TextStyle(color: Colors.white)),
                    activeColor: const Color(0xFFFFD700),
                    value: _hydrationEnabled,
                    onChanged: (bool value) => setSheetState(() => _hydrationEnabled = value),
                  ),
                  
                  const SizedBox(height: 15),
                  _buildCustomField(controller: _anchorController, label: "The Anchor (Why get home?)", hint: "e.g., Big meeting at 9am"),
                  const SizedBox(height: 15),
                  _buildCustomField(controller: _landingController, label: "The Landing (Final reminder)", hint: "e.g., Text Sarah I'm safe"),
                  
                  const SizedBox(height: 20),

                  if (errorMessage.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 15),
                      child: Row(
                        children: [
                          const Icon(Icons.error_outline, color: Colors.redAccent, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              errorMessage, 
                              style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ),
                    ),
                  
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFFD700), foregroundColor: Colors.black),
                      onPressed: _isValidating ? null : () async {
                        setSheetState(() => errorMessage = '');
                        
                        String cleanInput = _homeController.text.trim();

                        if (cleanInput.isEmpty) {
                          setSheetState(() => errorMessage = 'Please enter a destination.');
                          return;
                        }

                        setSheetState(() => _isValidating = true);
                        bool isValid = await _isPostcodeValid(cleanInput);
                        if (!context.mounted) return;
                        setSheetState(() => _isValidating = false);

                        if (!isValid) {
                          setSheetState(() => errorMessage = 'Invalid UK Postcode format or location not found.');
                          return;
                        }

                        if (await Permission.notification.isDenied) await Permission.notification.request();
                        LocationPermission forePermission = await Geolocator.checkPermission();
                        if (forePermission == LocationPermission.denied) forePermission = await Geolocator.requestPermission();
                        var bgStatus = await Permission.locationAlways.status;
                        
                        if (bgStatus.isGranted) {
                          bool isLocationServiceEnabled = await Geolocator.isLocationServiceEnabled();
                          if (!isLocationServiceEnabled) {
                            setSheetState(() => errorMessage = 'Please turn on your phone\'s Location/GPS.');
                            return;
                          }
                          _activateGuardian();
                        } else {
                          await _showBackgroundRationaleDialog();
                          final result = await Permission.locationAlways.request();
                          if (result.isGranted) {
                            _activateGuardian();
                          } else if (result.isPermanentlyDenied) {
                            await openAppSettings();
                          }
                        }
                      },
                      child: _isValidating 
                          ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                          : const Text('COMMIT & START GUARDIAN', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ),
          );
        });
      },
    );
  }

  void _showStandDownDialog() {
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1E1E3F),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 28),
              SizedBox(width: 10),
              Text("Stand Down?", style: TextStyle(color: Colors.white)),
            ],
          ),
          content: RichText(
            text: TextSpan(
              style: const TextStyle(color: Colors.white70, fontSize: 16, height: 1.4),
              children: [
                const TextSpan(text: "You are about to deactivate the Guardian.\n\nBut remember: "),
                TextSpan(
                  text: '"${_guardianSession?.anchorReason ?? "you need to be sharp tomorrow"}"\n\n',
                  style: const TextStyle(color: Color(0xFFFFD700), fontWeight: FontWeight.bold, fontStyle: FontStyle.italic),
                ),
                const TextSpan(text: "Are you sure you want to switch this off?"),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext), 
              child: const Text("KEEP ACTIVE", style: TextStyle(color: Colors.white54)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red.withOpacity(0.8),
                foregroundColor: Colors.white,
              ),
              onPressed: () {
                Navigator.pop(dialogContext);
                _deactivateGuardian();
              },
              child: const Text("DEACTIVATE"),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            colors: [Color(0xFF1E1E3F), Color(0xFF0F0F1A)],
            radius: 1.0,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('TRUE NORTH', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, letterSpacing: 8, color: Colors.white70)),
            const SizedBox(height: 60),
            
            GestureDetector(
              onTap: () {
                if (isGuardianActive) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Long press to deactivate')));
                } else {
                  _showPreFlightChecklist();
                }
              },
              onLongPress: () async {
                if (isGuardianActive) {
                  _showStandDownDialog();
                }
              },
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // The Outer Progress Ring (Only shows when active)
                  if (isGuardianActive && _guardianSession != null)
                    SizedBox(
                      width: 240,
                      height: 240,
                      child: CircularProgressIndicator(
                        value: _guardianSession!.progressFactor,
                        strokeWidth: 4,
                        backgroundColor: Colors.white10,
                        valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFFFFD700)),
                      ),
                    ),
                  
                  // The Main Shield Button
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 500),
                    width: 200, height: 200,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isGuardianActive ? const Color(0xFF1E1E3F) : Colors.transparent,
                      border: Border.all(color: isGuardianActive ? const Color(0xFFFFD700) : Colors.white10, width: 2),
                      boxShadow: isGuardianActive ? [BoxShadow(color: const Color(0xFFFFD700).withOpacity(0.1), blurRadius: 40, spreadRadius: 5)] : [],
                    ),
                    child: Icon(
                      isGuardianActive ? Icons.shield : Icons.shield_outlined, 
                      size: 80, 
                      color: isGuardianActive ? const Color(0xFFFFD700) : Colors.white24
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 40),

            // Tactical Readout
            if (isGuardianActive && _guardianSession != null) ...[
              Text(
                _guardianSession!.countdownText,
                style: const TextStyle(color: Color(0xFFFFD700), fontSize: 42, fontWeight: FontWeight.w900, letterSpacing: 2),
              ),
              const SizedBox(height: 8),
              Text(
                "DISTANCE TO HOME: ${_guardianSession!.distanceText.toUpperCase()}",
                style: const TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.5),
              ),
              const SizedBox(height: 24),
              const Text(
                'LONG PRESS SHIELD TO STAND DOWN',
                style: TextStyle(color: Colors.white24, fontSize: 10, letterSpacing: 1),
              ),
            ] else ...[
              const Text(
                'TAP TO CONFIGURE GUARDIAN',
                style: TextStyle(color: Colors.white54, fontWeight: FontWeight.bold, letterSpacing: 2),
              ),
            ],
          ],
        ),
      ),
    );
  }
}