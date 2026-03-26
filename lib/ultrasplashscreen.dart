import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class UltraSplashScreen extends StatefulWidget {
  const UltraSplashScreen({super.key});

  @override
  State<UltraSplashScreen> createState() => _UltraSplashScreenState();
}

class _UltraSplashScreenState extends State<UltraSplashScreen> {
  bool _visible = false;

  @override
  void initState() {
    super.initState();

    // Start the fade-in animation shortly after the screen is built.
    Future.delayed(const Duration(milliseconds: 200), () {
      if (mounted) {
        setState(() {
          _visible = true;
        });
      }
    });
    _redirect();
  }

  /// Checks auth state and redirects the user after a delay.
  Future<void> _redirect() async {
    // Wait for the splash screen animation to be visible for a moment.
    await Future.delayed(const Duration(seconds: 3));

    if (!mounted) return;

    final session = Supabase.instance.client.auth.currentSession;
    if (session == null) {
      // If no user is logged in, go to the login screen.
      Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
    } else {
      // If a user is logged in, go to the home router screen.
      Navigator.of(context).pushNamedAndRemoveUntil('/home', (route) => false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // We use a Scaffold to provide a standard app screen structure.
    return Scaffold(
      backgroundColor: Colors.white,
      // The body is the animated logo that fills the screen.
      body: AnimatedOpacity(
        opacity: _visible ? 1.0 : 0.0,
        duration: const Duration(seconds: 1),
        child: SizedBox(
          width: double.infinity,
          height: double.infinity,
          child: Image.asset(
            "assets/logo.jpg",
            // BoxFit.cover makes the image fill the screen without distortion.
            fit: BoxFit.cover,
          ),
        ),
      ),
    );
  }
}
