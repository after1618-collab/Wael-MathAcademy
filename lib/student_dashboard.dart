import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dart:async';
import 'student_home_screen.dart';
import 'package:wael_mcp/session_manager.dart';
import 'package:wael_mcp/api_service.dart';

class StudentDashboard extends StatefulWidget {
  const StudentDashboard({super.key});

  @override
  State<StudentDashboard> createState() => _StudentDashboardState();
}

class _StudentDashboardState extends State<StudentDashboard> {
  late Future<Map<String, dynamic>> _studentDataFuture;
  Timer? _sessionPollingTimer;

  @override
  void initState() {
    super.initState();
    _studentDataFuture = _fetchStudentData();
    _startSessionPolling();
  }

  void _startSessionPolling() {
    _sessionPollingTimer =
        Timer.periodic(const Duration(minutes: 3), (timer) async {
      try {
        final isValid = await ApiService.validateSession();
        if (mounted && !isValid) {
          timer.cancel();
          await SessionManager().clear();
          Navigator.of(context)
              .pushNamedAndRemoveUntil('/login', (route) => false);
        }
      } catch (e) {
        timer.cancel();
        debugPrint("Error polling session status: $e");
      }
    });
  }

  @override
  void dispose() {
    _sessionPollingTimer?.cancel();
    super.dispose();
  }

  Future<Map<String, dynamic>> _fetchStudentData() async {
    try {
      final profile = await ApiService.getProfile();
      return {
        'studentName': profile['full_name'] ?? 'طالب',
        'className': profile['class_name'] ?? 'غير محدد',
        'successRate': (profile['success_rate'] as num?)?.toDouble() ?? 0.0,
      };
    } on ApiException catch (e) {
      if (e.code == 401) {
        await SessionManager().clear();
        if (mounted) {
          Navigator.of(context)
              .pushNamedAndRemoveUntil('/login', (route) => false);
        }
        throw 'الجلسة انتهت. سجّل الدخول مرة أخرى';
      }
      throw e.message;
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: _studentDataFuture,
      builder: (context, snapshot) {
        // ===== LOADING =====
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Scaffold(
            body: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFF0F2027), Color(0xFF2C5364)],
                ),
              ),
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Animated Logo
                    Container(
                      width: 90,
                      height: 90,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF6A11CB), Color(0xFF2575FC)],
                        ),
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF6A11CB).withOpacity(0.5),
                            blurRadius: 30,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.school_rounded,
                        color: Colors.white,
                        size: 45,
                      ),
                    )
                        .animate(onPlay: (c) => c.repeat(reverse: true))
                        .scaleXY(
                          begin: 1,
                          end: 1.08,
                          duration: 800.ms,
                          curve: Curves.easeInOut,
                        )
                        .shimmer(
                          delay: 500.ms,
                          duration: 1500.ms,
                          color: Colors.white.withOpacity(0.3),
                        ),

                    const SizedBox(height: 30),

                    Text(
                      'Loading your dashboard...',
                      style: GoogleFonts.poppins(
                        color: Colors.white70,
                        fontSize: 16,
                      ),
                    ).animate().fadeIn(delay: 300.ms),

                    const SizedBox(height: 24),

                    // Progress dots
                    SizedBox(
                      width: 60,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: List.generate(3, (i) {
                          return Container(
                            width: 12,
                            height: 12,
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.6),
                              shape: BoxShape.circle,
                            ),
                          )
                              .animate(
                                  onPlay: (c) => c.repeat(reverse: true))
                              .scaleXY(
                                begin: 0.5,
                                end: 1,
                                delay: Duration(milliseconds: i * 200),
                                duration: 600.ms,
                              )
                              .fadeIn(
                                delay: Duration(milliseconds: i * 200),
                              );
                        }),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        // ===== ERROR =====
        if (snapshot.hasError) {
          return Scaffold(
            body: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFF0F2027), Color(0xFF2C5364)],
                ),
              ),
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 90,
                        height: 90,
                        decoration: BoxDecoration(
                          color: Colors.red.shade400.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(50),
                        ),
                        child: Icon(
                          Icons.wifi_off_rounded,
                          size: 45,
                          color: Colors.red.shade300,
                        ),
                      )
                          .animate()
                          .fadeIn(duration: 400.ms)
                          .shakeX(hz: 2, amount: 5, duration: 500.ms),
                      const SizedBox(height: 24),
                      Text(
                        'Oops! Something went wrong',
                        style: GoogleFonts.poppins(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                        ),
                      ).animate().fadeIn(delay: 200.ms),
                      const SizedBox(height: 10),
                      Text(
                        '${snapshot.error}',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.poppins(
                          color: Colors.white60,
                          fontSize: 14,
                        ),
                      ).animate().fadeIn(delay: 300.ms),
                      const SizedBox(height: 32),
                      ElevatedButton.icon(
                        onPressed: () {
                          setState(() {
                            _studentDataFuture = _fetchStudentData();
                          });
                        },
                        icon: const Icon(Icons.refresh_rounded),
                        label: Text(
                          'Try Again',
                          style: GoogleFonts.poppins(
                              fontWeight: FontWeight.w600),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF2575FC),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 32, vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      ).animate().fadeIn(delay: 500.ms).slideY(begin: 0.3),
                    ],
                  ),
                ),
              ),
            ),
          );
        }

        // ===== SUCCESS =====
        final data = snapshot.data!;
        return StudentHomeScreen(
          studentName: data['studentName'],
          className: data['className'],
          successRate: data['successRate'],
        );
      },
    );
  }
}