import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:animated_text_kit/animated_text_kit.dart';
import 'package:wael_mcp/student_dashboard.dart';
import 'package:wael_mcp/session_manager.dart';
import 'package:wael_mcp/api_service.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io';
import 'dart:async';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with TickerProviderStateMixin {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _emailFocus = FocusNode();
  final _passwordFocus = FocusNode();
  String? _errorMessage;
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _hasError = false; // For shake animation

  // Background animation
  late AnimationController _bgController;

  @override
  void initState() {
    super.initState();
    _bgController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _emailFocus.dispose();
    _passwordFocus.dispose();
    _bgController.dispose();
    super.dispose();
  }

  // ============ LOGIN LOGIC (Same as yours) ============
  Future<void> _login() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _hasError = false;
    });

    try {
      final email = _emailController.text.trim();
      final password = _passwordController.text.trim();

      if (email.isEmpty || password.isEmpty) {
        throw Exception('Please enter your email and password');
      }

      if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(email)) {
        throw Exception('Please enter a valid email address');
      }

      final deviceId = await SessionManager().getOrCreateDeviceId();

      final response = await http.post(
        Uri.parse('${ApiService.baseUrl}/sessions/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': email,
          'password': password,
          'device_id': deviceId,
        }),
      ).timeout(const Duration(seconds: 15));

      final responseBody = jsonDecode(response.body);

      if (response.statusCode == 200) {
        final sessionToken = responseBody['session_token'];
        await SessionManager().setToken(sessionToken);

        if (mounted) {
          Navigator.pushReplacement(
            context,
            PageRouteBuilder(
              pageBuilder: (_, __, ___) => const StudentDashboard(),
              transitionsBuilder: (_, anim, __, child) {
                return FadeTransition(opacity: anim, child: child);
              },
              transitionDuration: const Duration(milliseconds: 500),
            ),
          );
        }
      } else {
        switch (response.statusCode) {
          case 401:
            throw Exception('Incorrect password');
          case 403:
            throw Exception(
                'Account is not activated. Contact your teacher');
          case 404:
            throw Exception('No account found with this email');
          case 400:
            throw Exception(responseBody['detail'] ?? 'Invalid data');
          case 429:
            throw Exception(
                'Too many attempts. Please wait and try again');
          default:
            throw Exception(
                responseBody['detail'] ?? 'An unexpected error occurred');
        }
      }
    } on SocketException {
      _setError(
          'Cannot connect to server. Check your internet connection');
    } on TimeoutException {
      _setError('Connection timed out. Please try again');
    } on FormatException {
      _setError('Server communication error. Try again later');
    } catch (e) {
      _setError(e.toString().replaceAll('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _setError(String msg) {
    if (mounted) {
      setState(() {
        _errorMessage = msg;
        _hasError = true;
      });
      // Reset shake trigger
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) setState(() => _hasError = false);
      });
    }
  }

  // ============ UI ============
  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isWide = size.width > 850;

    return Scaffold(
      body: AnimatedBuilder(
        animation: _bgController,
        builder: (context, child) {
          return Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color.lerp(
                    const Color(0xFF0F2027),
                    const Color(0xFF2C5364),
                    _bgController.value,
                  )!,
                  Color.lerp(
                    const Color(0xFF6A11CB),
                    const Color(0xFF2575FC),
                    _bgController.value,
                  )!,
                ],
              ),
            ),
            child: child,
          );
        },
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: isWide
                  ? _buildDesktopLayout(size)
                  : _buildMobileLayout(size),
            ),
          ),
        ),
      ),
    );
  }

  // ============ DESKTOP LAYOUT ============
  Widget _buildDesktopLayout(Size size) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 950, maxHeight: 580),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 40,
            offset: const Offset(0, 20),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Row(
          children: [
            // Left: Branding
            Expanded(flex: 5, child: _buildBrandingPanel()),
            // Right: Form
            Expanded(flex: 5, child: _buildFormCard()),
          ],
        ),
      ),
    )
        .animate()
        .fadeIn(duration: 700.ms)
        .scale(
          begin: const Offset(0.93, 0.93),
          end: const Offset(1, 1),
          duration: 700.ms,
          curve: Curves.easeOutBack,
        );
  }

  // ============ MOBILE LAYOUT ============
  Widget _buildMobileLayout(Size size) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Logo + Title
        _buildMobileBranding(),
        const SizedBox(height: 32),
        // Form
        Container(
          constraints: const BoxConstraints(maxWidth: 420),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.15),
                blurRadius: 30,
                offset: const Offset(0, 15),
              ),
            ],
          ),
          child: _buildFormCard(),
        ),
      ],
    )
        .animate()
        .fadeIn(duration: 600.ms)
        .slideY(begin: 0.08, end: 0, duration: 600.ms, curve: Curves.easeOut);
  }

  // ============ BRANDING PANEL (Desktop Left Side) ============
  Widget _buildBrandingPanel() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF6A11CB), Color(0xFF2575FC)],
        ),
      ),
      padding: const EdgeInsets.all(40),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Logo
          ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: Image.asset(
              'assets/logo.jpg',
              width: 100,
              height: 100,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: Colors.white.withOpacity(0.3),
                    width: 2,
                  ),
                ),
                child: const Icon(
                    Icons.school_rounded, color: Colors.white, size: 50),
              ),
            ),
          )
              .animate(onPlay: (c) => c.repeat(reverse: true))
              .shimmer(
                delay: 3000.ms,
                duration: 1800.ms,
                color: Colors.white.withOpacity(0.3),
              ),
          const SizedBox(height: 28),

          // App Name
          Text(
            'WAEL MCP',
            style: GoogleFonts.poppins(
              fontSize: 32,
              fontWeight: FontWeight.w800,
              color: Colors.white,
              letterSpacing: 3,
            ),
          ).animate().fadeIn(delay: 200.ms).slideX(begin: -0.2),

          const SizedBox(height: 12),

          // Animated Subtitle
          SizedBox(
            height: 28,
            child: DefaultTextStyle(
              style: GoogleFonts.poppins(fontSize: 15, color: Colors.white70),
              child: AnimatedTextKit(
                repeatForever: true,
                pause: const Duration(milliseconds: 1500),
                animatedTexts: [
                  TypewriterAnimatedText(
                    'Learn Smarter, Not Harder 📚',
                    speed: const Duration(milliseconds: 60),
                  ),
                  TypewriterAnimatedText(
                    'Your Success Starts Here 🚀',
                    speed: const Duration(milliseconds: 60),
                  ),
                  TypewriterAnimatedText(
                    'Master Every Subject ⭐',
                    speed: const Duration(milliseconds: 60),
                  ),
                ],
              ),
            ),
          ).animate().fadeIn(delay: 400.ms),

          const SizedBox(height: 36),

          // Features list
          _featureRow(Icons.quiz_rounded, 'Interactive Exams'),
          const SizedBox(height: 10),
          _featureRow(Icons.play_circle_rounded, 'Video Lessons'),
          const SizedBox(height: 10),
          _featureRow(Icons.analytics_rounded, 'Track Progress'),
        ],
      ),
    );
  }

  Widget _featureRow(IconData icon, String text) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.15),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: Colors.white, size: 20),
        ),
        const SizedBox(width: 12),
        Text(
          text,
          style: GoogleFonts.poppins(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    ).animate().fadeIn(delay: 600.ms).slideX(begin: -0.3);
  }

  // ============ MOBILE BRANDING ============
  Widget _buildMobileBranding() {
    return Column(
      children: [
        // Logo
        ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: Image.asset(
            'assets/logo.jpg',
            width: 90,
            height: 90,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Container(
              width: 90,
              height: 90,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF6A11CB), Color(0xFF2575FC)],
                ),
                borderRadius: BorderRadius.circular(22),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF6A11CB).withOpacity(0.4),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: const Icon(
                  Icons.school_rounded, size: 45, color: Colors.white),
            ),
          ),
        )
            .animate(onPlay: (c) => c.repeat(reverse: true))
            .shimmer(
              delay: 3000.ms,
              duration: 1800.ms,
              color: Colors.white.withOpacity(0.3),
            ),

        const SizedBox(height: 18),

        Text(
          'WAEL MCP',
          style: GoogleFonts.poppins(
            fontSize: 28,
            fontWeight: FontWeight.w800,
            color: Colors.white,
            letterSpacing: 3,
          ),
        ).animate().fadeIn(delay: 200.ms),

        const SizedBox(height: 6),
        Text(
          'Student Portal',
          style: GoogleFonts.poppins(
            fontSize: 14,
            color: Colors.white60,
          ),
        ).animate().fadeIn(delay: 300.ms),
      ],
    );
  }

  // ============ FORM CARD ============
  Widget _buildFormCard() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Title
          Text(
            'Welcome Back! 👋',
            style: GoogleFonts.poppins(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF1A1A2E),
            ),
          ).animate().fadeIn(delay: 300.ms).slideX(begin: 0.15),

          const SizedBox(height: 4),
          Text(
            'Sign in to continue your learning journey',
            style: GoogleFonts.poppins(
              fontSize: 13,
              color: Colors.grey[500],
            ),
          ).animate().fadeIn(delay: 400.ms),

          const SizedBox(height: 28),

          // Error
          if (_errorMessage != null)
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.red.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.error_outline,
                      color: Colors.red.shade400, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _errorMessage!,
                      style: TextStyle(
                        color: Colors.red.shade700,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: () => setState(() => _errorMessage = null),
                    child: Icon(Icons.close,
                        size: 18, color: Colors.red.shade300),
                  ),
                ],
              ),
            )
                .animate()
                .fadeIn(duration: 300.ms)
                .shakeX(hz: 3, amount: 6, duration: 400.ms),

          if (_errorMessage != null) const SizedBox(height: 18),

          // Email
          _buildField(
            controller: _emailController,
            focusNode: _emailFocus,
            label: 'Email Address',
            hint: 'student@example.com',
            icon: Icons.email_rounded,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            onSubmitted: (_) => _passwordFocus.requestFocus(),
          ).animate().fadeIn(delay: 500.ms).slideY(begin: 0.15),

          const SizedBox(height: 18),

          // Password
          _buildField(
            controller: _passwordController,
            focusNode: _passwordFocus,
            label: 'Password',
            hint: '••••••••',
            icon: Icons.lock_rounded,
            obscure: _obscurePassword,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _login(),
            suffix: IconButton(
              icon: Icon(
                _obscurePassword
                    ? Icons.visibility_off_rounded
                    : Icons.visibility_rounded,
                color: Colors.grey[400],
                size: 20,
              ),
              onPressed: () =>
                  setState(() => _obscurePassword = !_obscurePassword),
            ),
          ).animate().fadeIn(delay: 600.ms).slideY(begin: 0.15),

          const SizedBox(height: 28),

          // Login Button
          _buildLoginButton()
              .animate()
              .fadeIn(delay: 700.ms)
              .slideY(begin: 0.2),

          const SizedBox(height: 20),

          // Footer
          Center(
            child: Text(
              '🔒 Secured connection',
              style: GoogleFonts.poppins(
                fontSize: 11,
                color: Colors.grey[400],
              ),
            ),
          ).animate().fadeIn(delay: 900.ms),
        ],
      ),
    );
  }

  // ============ INPUT FIELD ============
  Widget _buildField({
    required TextEditingController controller,
    required FocusNode focusNode,
    required String label,
    required String hint,
    required IconData icon,
    bool obscure = false,
    Widget? suffix,
    TextInputType? keyboardType,
    TextInputAction? textInputAction,
    void Function(String)? onSubmitted,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.poppins(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: const Color(0xFF1A1A2E),
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          focusNode: focusNode,
          obscureText: obscure,
          keyboardType: keyboardType,
          textInputAction: textInputAction,
          onSubmitted: onSubmitted,
          style: GoogleFonts.poppins(fontSize: 14, color: Colors.black87),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: GoogleFonts.poppins(
              color: Colors.grey[350],
              fontSize: 14,
            ),
            prefixIcon: Icon(icon, color: Colors.grey[400], size: 20),
            suffixIcon: suffix,
            filled: true,
            fillColor: const Color(0xFFF8F9FD),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: Colors.grey.shade200),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide:
                  const BorderSide(color: Color(0xFF2575FC), width: 1.5),
            ),
          ),
        ),
      ],
    );
  }

  // ============ LOGIN BUTTON ============
  Widget _buildLoginButton() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      height: 54,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        gradient: _isLoading
            ? LinearGradient(
                colors: [Colors.grey.shade400, Colors.grey.shade500])
            : const LinearGradient(
                colors: [Color(0xFF6A11CB), Color(0xFF2575FC)],
              ),
        boxShadow: _isLoading
            ? []
            : [
                BoxShadow(
                  color: const Color(0xFF6A11CB).withOpacity(0.4),
                  blurRadius: 15,
                  offset: const Offset(0, 6),
                ),
              ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _isLoading ? null : _login,
          borderRadius: BorderRadius.circular(14),
          child: Center(
            child: _isLoading
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2.5,
                    ),
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'Sign In',
                        style: GoogleFonts.poppins(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Icon(Icons.arrow_forward_rounded,
                          color: Colors.white, size: 20),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}