import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:geocoding/geocoding.dart';

import 'package:true_north/core/models/guardian_session.dart';
import 'package:true_north/core/session_repository.dart';

class GuardianScreen extends StatefulWidget {
  const GuardianScreen({super.key});

  @override
  State<GuardianScreen> createState() => _GuardianScreenState();
}

class _GuardianScreenState extends State<GuardianScreen> with SingleTickerProviderStateMixin {
  // --- STATE ---
  bool _isValidating = false;
  GuardianSession? _guardianSession;
  bool get isGuardianActive => _guardianSession != null;
  Timer? _uiClockTimer;

  bool _hasShownLateModal = false;

  // --- ANIMATION CONTROLLER ---
  late AnimationController _glowController;
  late Animation<double> _glowOpacity;

  // --- CONTROLLERS ---
  final TextEditingController _homeController = TextEditingController();
  final TextEditingController _anchorController = TextEditingController();
  final TextEditingController _landingController = TextEditingController();

  // --- CONFIG ---
  TimeOfDay _leaveTime = const TimeOfDay(hour: 23, minute: 0);
  bool _nudgesEnabled = true;
  Position? _homePoint; 

  @override
  void initState() {
    super.initState();
    
    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2), 
    );
    
    _glowOpacity = Tween<double>(begin: 0.05, end: 0.30).animate(
      CurvedAnimation(parent: _glowController, curve: Curves.easeInOut),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      
      _setupServiceConnection();
      
      _uiClockTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (isGuardianActive && _guardianSession != null && mounted) {
          
          bool isLate = _guardianSession!.targetDepartureTime.isBefore(DateTime.now());
          bool isSnoozed = _guardianSession!.isSnoozed;
          
          // 🛡️ FIX 1: THE LIFECYCLE CHECK
          // Only trigger if late, not snoozed, hasn't shown, AND the app is fully resumed on screen
          if (isLate && !isSnoozed && !_hasShownLateModal) {
            if (WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
              _hasShownLateModal = true;
              _showLateInterventionModal();
            }
          } else if (isSnoozed) {
            // Reset the flag so the modal can attack them again when the snooze expires
            _hasShownLateModal = false;
          }
          
          Duration targetDuration = isLate ? const Duration(seconds: 1) : const Duration(seconds: 2);
          
          if (_glowController.duration != targetDuration) {
            _glowController.duration = targetDuration;
            if (_glowController.isAnimating) {
              _glowController.repeat(reverse: true);
            }
          }

          setState(() {}); 
        }
      });
    });
  }

  void _showLateInterventionModal() {
    showDialog(
      context: context,
      barrierDismissible: false, 
      // 🛡️ FIX 2: POPSCOPE
      // This prevents the user from swiping back or using the Android back button to escape
      builder: (context) => PopScope(
        canPop: false, 
        child: AlertDialog(
          backgroundColor: const Color(0xFFFF4C4C).withOpacity(0.95), 
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.white, size: 28),
              SizedBox(width: 10),
              Text("MISSION CRITICAL", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                "You are past your departure time. Stand down now, or remember why you need to move:", 
                style: TextStyle(color: Colors.white, fontSize: 15)
              ),
              const SizedBox(height: 15),
              Text(
                '"${_guardianSession?.anchorReason}"', 
                style: const TextStyle(color: Colors.white, fontSize: 18, fontStyle: FontStyle.italic, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
            ],
          ),
          actions: [
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.black, 
                foregroundColor: Colors.white,
              ),
              onPressed: () {
                Navigator.pop(context);
                _snoozeGuardian(); 
              },
              child: const Text("SNOOZE (5 MINS)", style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  void _setupServiceConnection() async {
    final service = FlutterBackgroundService();
    
    if (await service.isRunning()) {
      if (mounted) {
        setState(() {
          if (!_glowController.isAnimating) _glowController.repeat(reverse: true); 
        });
      }
      service.invoke('request_state');
    }

    service.on('updateUI').listen((event) {
      if (event != null && mounted) {
        try {
          final safeMap = Map<String, dynamic>.from(event);
          if (mounted) {
            setState(() {
              _guardianSession = GuardianSession.fromMap(safeMap);
              if (!_glowController.isAnimating) _glowController.repeat(reverse: true);
            });
          }
        } catch (e) {
          print("🚨 [UI] Failed to parse session data: $e"); 
        }
      }
    });
  }

  @override
  void dispose() {
    _uiClockTimer?.cancel();
    _glowController.dispose(); 
    _homeController.dispose();
    _anchorController.dispose();
    _landingController.dispose();
    super.dispose();
  }

  Future<bool> _isPostcodeValid(String address) async {
    String cleanAddress = address.trim().toUpperCase();
    final RegExp ukPostcodeRegex = RegExp(r"^[A-Z]{1,2}\d[A-Z\d]? ?\d[A-Z]{2}$");
    if (!ukPostcodeRegex.hasMatch(cleanAddress)) return false; 

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
    
    DateTime targetDateTime = DateTime(
      now.year, now.month, now.day, 
      _leaveTime.hour, _leaveTime.minute
    );
    if (targetDateTime.isBefore(now)) {
      targetDateTime = targetDateTime.add(const Duration(days: 1));
    }

    final session = GuardianSession(
      activationTime: now,
      targetDepartureTime: targetDateTime,
      homeLat: _homePoint!.latitude,
      homeLng: _homePoint!.longitude,
      anchorReason: _anchorController.text.isNotEmpty ? _anchorController.text : "you need to be sharp tomorrow",
      homeReminderText: _landingController.text.isNotEmpty ? _landingController.text : "Welcome home. The Guardian is standing down.",
      nudgesEnabled: _nudgesEnabled,
    );

    await SessionRepository().saveSession(session);

    if (!context.mounted) return;
    Navigator.pop(context); 
    setState(() {
      _guardianSession = session;
      _glowController.repeat(reverse: true); 
    });

    final service = FlutterBackgroundService();
    await service.startService();
    service.invoke('setAsForeground');
  }

  Future<void> _deactivateGuardian() async {
    setState(() {
      _guardianSession = null;
      _glowController.reset(); 
    });
    
    await SessionRepository().clearSession();
    FlutterBackgroundService().invoke('stopService');
  }

  void _snoozeGuardian() {
    FlutterBackgroundService().invoke('snooze_mission');
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

  Widget _buildCustomField({required TextEditingController controller, 
    required String label, 
    required String hint, 
    IconData? icon,
    TextCapitalization textCapitalization = TextCapitalization.none,
  }) {
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
                  const Text('GOOD INTENTIONS', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFFFFD700), letterSpacing: 2)),
                  const SizedBox(height: 20),
                  
                  _buildCustomField(controller: _homeController, label: 'Home Postcode', hint: 'e.g. SW1A 1AA', icon: Icons.home, textCapitalization: TextCapitalization.characters),
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
                    title: const Text('Tactical Nudges', style: TextStyle(color: Colors.white)),
                    subtitle: const Text('Periodic messages to keep you on track', style: TextStyle(color: Colors.white54)),
                    activeColor: const Color(0xFFFFD700),
                    value: _nudgesEnabled,
                    onChanged: (bool value) => setSheetState(() => _nudgesEnabled = value),
                  ),
                  
                  const SizedBox(height: 15),
                  _buildCustomField(controller: _anchorController, label: "The Anchor (Why get home?)", hint: "e.g., Big meeting at 9am", textCapitalization: TextCapitalization.sentences),
                  const SizedBox(height: 15),
                  _buildCustomField(controller: _landingController, label: "The Landing (Reminder when your home)", hint: "e.g., Let my family know I'm home safe", textCapitalization: TextCapitalization.sentences),
                  
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
                const TextSpan(text: "You are about to deactivate the Guardian.\n\nBut remember\n\n: "),
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

  Color _getGlowColor() {
    if (_guardianSession == null) return const Color(0xFF4CAF50); 
    
    final diff = _guardianSession!.targetDepartureTime.difference(DateTime.now()); 
    
    if (diff.isNegative) return const Color(0xFFFF4C4C); 
    
    if (diff.inMinutes <= 30) {
      double factor = 1.0 - (diff.inSeconds / (30 * 60)); 
      return Color.lerp(
        const Color(0xFF4CAF50), 
        const Color(0xFFFF4C4C), 
        factor.clamp(0.0, 1.0)
      )!;
    }
    
    return const Color(0xFF4CAF50); 
  }

  Widget _buildTacticalShield() {
    double progress = _guardianSession?.progressFactor ?? 0.0;
    Color activeStatusColor = _getGlowColor();

    return GestureDetector(
      onTap: () {
        if (!isGuardianActive) _showPreFlightChecklist();
      },
      onLongPress: () {
        if (isGuardianActive) _showStandDownDialog();
      },
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (isGuardianActive)
            AnimatedBuilder(
              animation: _glowController,
              builder: (context, child) {
                return Container(
                  width: 260,
                  height: 260,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: activeStatusColor.withOpacity(_glowOpacity.value),
                        blurRadius: 100, 
                        spreadRadius: 20,
                      ),
                    ],
                  ),
                );
              }
            ),
            
          if (isGuardianActive)
            SizedBox(
              width: 250,
              height: 250,
              child: CircularProgressIndicator(
                value: progress,
                strokeWidth: 3,
                backgroundColor: Colors.white.withOpacity(0.05),
                valueColor: AlwaysStoppedAnimation<Color>(activeStatusColor),
              ),
            ),

          AnimatedContainer(
            duration: const Duration(milliseconds: 600),
            curve: Curves.easeOutCirc,
            width: 200,
            height: 200,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isGuardianActive ? const Color(0xFF1E1E3F) : Colors.transparent,
              border: Border.all(
                color: isGuardianActive ? activeStatusColor : Colors.white10,
                width: 1.5,
              ),
            ),
            child: Icon(
              isGuardianActive ? Icons.shield : Icons.shield_outlined, 
              size: 80, 
              color: isGuardianActive ? activeStatusColor : Colors.white10 
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActiveReadouts() {
    final diff = _guardianSession!.targetDepartureTime.difference(DateTime.now()); 
    final bool isLate = diff.isNegative;
    final bool isSnoozed = _guardianSession!.isSnoozed;
    
    return Column(
      children: [
        Text(
          _guardianSession!.countdownText,
          style: TextStyle(
            color: isLate ? const Color(0xFFFF4C4C) : const Color(0xFFFFD700),
            fontSize: 48, 
            fontWeight: FontWeight.w900, 
            letterSpacing: 2,           
          ),
        ),
        const SizedBox(height: 12),
        
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white10),
            color: Colors.black12,
          ),
          child: Text(
            "DISTANCE TO HOME: ${_guardianSession!.distanceText.toUpperCase()}",
            style: const TextStyle(
              color: Colors.white54,
              fontSize: 11,
              fontWeight: FontWeight.w900,
              letterSpacing: 2,
            ),
          ),
        ),
        
        const SizedBox(height: 30),

        if (isLate && isSnoozed) ...[
          const Text("SNOOZED FOR 5 MINUTES", style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold, letterSpacing: 2)),
        ],

        const SizedBox(height: 30),

        const Text(
          "HOLD SHIELD TO STAND DOWN",
          style: TextStyle(color: Colors.white10, fontSize: 10, letterSpacing: 3),
        ),
      ],
    );
  }

  Widget _buildInactiveState() {
    return const Column(
      children: [
        Text(
          'TAP SHIELD TO CONFIGURE',
          style: TextStyle(color: Colors.white54, fontWeight: FontWeight.bold, letterSpacing: 2),
        ),
      ],
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
            radius: 1.2, 
          ),
        ),
        // 🛡️ FIX 4: CUSTOMSCROLLVIEW
        // This ensures the new inline UI button doesn't crash into the bottom of the screen!
        child: SafeArea(
          child: CustomScrollView(
            slivers: [
              SliverFillRemaining(
                hasScrollBody: false,
                child: Column(
                  children: [
                    const SizedBox(height: 20),
                    const Text(
                      'TRUE NORTH', 
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: 12, color: Colors.white24)
                    ),
                    
                    const Spacer(),
                    _buildTacticalShield(),
                    const Spacer(),

                    if (isGuardianActive && _guardianSession != null)
                      _buildActiveReadouts()
                    else
                      _buildInactiveState(),

                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}