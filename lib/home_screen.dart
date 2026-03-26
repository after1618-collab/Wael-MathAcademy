import 'package:flutter/material.dart';
import 'package:wael_mcp/api_service.dart';

/// A screen that acts as a router after login.
/// It fetches the user's role and redirects to the appropriate dashboard.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final Future<String?> _roleFuture;

  @override
  void initState() {
    super.initState();
    _roleFuture = _getUserRole();
  }

  Future<String?> _getUserRole() async {
    try {
      // ✅ استخدام ApiService بدلاً من Supabase مباشرة
      final role = await ApiService.getUserRole();
      debugPrint('--- User role from database: $role ---');
      return role;
    } catch (e) {
      debugPrint('--- Error fetching user role: $e ---');
      // يمكن إضافة منطق تسجيل الخروج هنا إذا لزم الأمر
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String?>(
      future: _roleFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final role = snapshot.data;

        // Use a post-frame callback to perform the navigation.
        // This prevents "setState() or markNeedsBuild() called during build" error.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (role == 'admin') {
            Navigator.of(context).pushReplacementNamed('/admin_sections');
          } else if (role == 'student') {
            Navigator.of(context).pushReplacementNamed('/student_dashboard');
          } else {
            // If role is null or unknown, go back to login.
            Navigator.of(context).pushReplacementNamed('/login');
          }
        });

        // Return a placeholder widget while navigation is occurring.
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      },
    );
  }
}
