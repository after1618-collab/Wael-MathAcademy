import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

// ============================================================
// Wael Math Academy - Landing Screen V2 (Professional)
// ============================================================
// 
// BEFORE RUNNING:
// 1. Add this package to pubspec.yaml:
//    dependencies:
//      url_launcher: ^6.2.5
//
// 2. Register images in pubspec.yaml under flutter > assets:
//    assets:
//      - assets/logo.jpg
//      - assets/WhatsApp Image 2026-08-08 at 1.34.33 AM.jpeg
//      - assets/WhatsApp Image 2026-08-08 at 1.38.09 AM.jpeg
//      - assets/youtube qr.jpeg
//
// 3. Copy your QR images to the project's assets/ folder.
// 4. Run: flutter pub get
// ============================================================

class LandingScreen extends StatefulWidget {
  const LandingScreen({super.key});

  @override
  State<LandingScreen> createState() => _LandingScreenState();
}

class _LandingScreenState extends State<LandingScreen>
    with SingleTickerProviderStateMixin {
  // ─── Colors ───
  static const Color primaryGreen = Color(0xFF1B5E20);
  static const Color secondaryGreen = Color(0xFF2E7D32);
  static const Color lightGreen = Color(0xFF4CAF50);
  static const Color accentGold = Color(0xFFFFB300);
  static const Color lightGold = Color(0xFFFFCA28);
  static const Color darkBg = Color(0xFF0D1B2A);
  static const Color cardBg = Color(0xFFF8FAFC);
  static const Color textDark = Color(0xFF1E293B);
  static const Color textMuted = Color(0xFF64748B);

  // ─── URLs ───
  final String whatsappUrl = 'https://wa.me/201003912064';
  final String telegramUrl = 'https://t.me/+3z0zMIiOZftiZmNk';
  final String youtubeUrl = 'https://youtube.com/@waeltahermath?si=yispGOSxV_sSzN2v';
  final String inviteLink = 'https://www.waelacademy.com';

  // ─── Animation ───
  late AnimationController _animController;
  late Animation<double> _fadeAnimation;

  // ─── Stats ───
  final List<Map<String, dynamic>> stats = [
    {'value': 2500, 'label': 'Student', 'icon': Icons.people},
    {'value': 150, 'label': 'Lessons', 'icon': Icons.play_circle},
    {'value': 95, 'label': 'Success %', 'icon': Icons.emoji_events},
  ];

  final List<int> animatedStats = [0, 0, 0];

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOut,
    );
    _animController.forward();
    _animateStats();
  }

  void _animateStats() {
    for (int i = 0; i < stats.length; i++) {
      final target = stats[i]['value'] as int;
      final step = (target / 60).ceil();
      Future.delayed(Duration.zero, () async {
        for (int current = 0; current <= target; current += step) {
          if (!mounted) return;
          await Future.delayed(const Duration(milliseconds: 30));
          if (mounted) {
            setState(() {
              animatedStats[i] = current > target ? target : current;
            });
          }
        }
        if (mounted) {
          setState(() => animatedStats[i] = target);
        }
      });
    }
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  Future<void> _launchUrl(String url) async {
    final Uri uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  void _shareInviteLink() async {
    final String text =
        'انضم لأكاديمية وائل للرياضيات! 🎓\n'
        'مذاكرة SAT Math, EST Math ورياضيات ثانوي\n'
        '$inviteLink';

    await Clipboard.setData(ClipboardData(text: text));

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Link copied to clipboard!',
            style: GoogleFonts.poppins(),
          ),
          backgroundColor: primaryGreen,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: FadeTransition(
        opacity: _fadeAnimation,
        child: SingleChildScrollView(
          child: Column(
            children: [
              _buildHero(),
              _buildStats(),
              _buildFeatures(),
              _buildCourses(),
              _buildTestimonials(),
              _buildQrSection(),
              _buildInviteSection(),
              _buildFooter(),
            ],
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // HERO SECTION
  // ═══════════════════════════════════════════════════════════
  Widget _buildHero() {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [primaryGreen, secondaryGreen, lightGreen],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 60),
          child: Column(
            children: [
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(25),
                  border: Border.all(color: Colors.white.withOpacity(0.3)),
                ),
                child: const Icon(Icons.school, color: Colors.white, size: 50),
              ),
              const SizedBox(height: 24),
              Text(
                'Wael Math Academy',
                style: GoogleFonts.poppins(
                  fontSize: 36,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                'Master SAT Math, EST Math &\nSecondary Mathematics',
                style: GoogleFonts.poppins(
                  fontSize: 18,
                  color: Colors.white.withOpacity(0.9),
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: 220,
                height: 54,
                child: ElevatedButton(
                  onPressed: () => Navigator.pushNamed(context, '/login'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: accentGold,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    elevation: 4,
                    shadowColor: accentGold.withOpacity(0.4),
                  ),
                  child: Text(
                    'Student Login',
                    style: GoogleFonts.poppins(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Already a student? Sign in to access your courses',
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  color: Colors.white.withOpacity(0.7),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // STATS SECTION
  // ═══════════════════════════════════════════════════════════
  Widget _buildStats() {
    return Container(
      width: double.infinity,
      color: cardBg,
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: List.generate(stats.length, (i) {
          return Column(
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: primaryGreen.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  stats[i]['icon'] as IconData,
                  color: primaryGreen,
                  size: 28,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                '${animatedStats[i]}${i == 2 ? '%' : '+'}',
                style: GoogleFonts.poppins(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: primaryGreen,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                stats[i]['label'] as String,
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  color: textMuted,
                ),
              ),
            ],
          );
        }),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // FEATURES SECTION
  // ═══════════════════════════════════════════════════════════
  Widget _buildFeatures() {
    final features = [
      {
        'icon': Icons.school,
        'title': 'SAT Math Prep',
        'desc': 'Comprehensive SAT Math course with practice tests and strategies.',
      },
      {
        'icon': Icons.calculate,
        'title': 'EST Math Prep',
        'desc': 'Specialized EST Math preparation for Egyptian students.',
      },
      {
        'icon': Icons.trending_up,
        'title': 'Secondary Math',
        'desc': 'Thorough secondary school math tutoring for all grades.',
      },
      {
        'icon': Icons.video_library,
        'title': 'Video Lessons',
        'desc': 'High-quality recorded lessons accessible anytime, anywhere.',
      },
      {
        'icon': Icons.assignment_turned_in,
        'title': 'Practice Tests',
        'desc': 'Mock exams and quizzes to track your progress effectively.',
      },
      {
        'icon': Icons.support_agent,
        'title': '24/7 Support',
        'desc': 'Get help whenever you need it from our dedicated team.',
      },
    ];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 50, horizontal: 24),
      child: Column(
        children: [
          Text(
            'Why Choose Us',
            style: GoogleFonts.poppins(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: textDark,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            width: 60,
            height: 4,
            decoration: BoxDecoration(
              color: accentGold,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 40),
          Wrap(
            spacing: 16,
            runSpacing: 16,
            alignment: WrapAlignment.center,
            children: features.map((f) {
              return SizedBox(
                width: 340,
                child: Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: primaryGreen.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          f['icon'] as IconData,
                          color: primaryGreen,
                          size: 26,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              f['title'] as String,
                              style: GoogleFonts.poppins(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: textDark,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              f['desc'] as String,
                              style: GoogleFonts.poppins(
                                fontSize: 13,
                                color: textMuted,
                                height: 1.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // COURSES SECTION
  // ═══════════════════════════════════════════════════════════
  Widget _buildCourses() {
    final courses = [
      {
        'title': 'SAT Math',
        'subtitle': 'Full Preparation',
        'icon': Icons.school,
        'color': Color(0xFF1565C0),
        'topics': ['Algebra', 'Problem Solving', 'Data Analysis'],
      },
      {
        'title': 'EST Math',
        'subtitle': 'Egyptian Students',
        'icon': Icons.calculate,
        'color': Color(0xFF6A1B9A),
        'topics': ['Geometry', 'Statistics', 'Advanced Math'],
      },
      {
        'title': 'Secondary Math',
        'subtitle': 'All Grades',
        'icon': Icons.trending_up,
        'color': Color(0xFF2E7D32),
        'topics': ['Calculus', 'Trigonometry', 'Functions'],
      },
    ];

    return Container(
      width: double.infinity,
      color: cardBg,
      padding: const EdgeInsets.symmetric(vertical: 50, horizontal: 24),
      child: Column(
        children: [
          Text(
            'Our Courses',
            style: GoogleFonts.poppins(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: textDark,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            width: 60,
            height: 4,
            decoration: BoxDecoration(
              color: accentGold,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 40),
          Wrap(
            spacing: 20,
            runSpacing: 20,
            alignment: WrapAlignment.center,
            children: courses.map((c) {
              return SizedBox(
                width: 320,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.06),
                        blurRadius: 15,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: (c['color'] as Color).withOpacity(0.1),
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(20),
                          ),
                        ),
                        child: Column(
                          children: [
                            Icon(
                              c['icon'] as IconData,
                              color: c['color'] as Color,
                              size: 48,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              c['title'] as String,
                              style: GoogleFonts.poppins(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: textDark,
                              ),
                            ),
                            Text(
                              c['subtitle'] as String,
                              style: GoogleFonts.poppins(
                                fontSize: 13,
                                color: textMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ...((c['topics'] as List<String>).map((t) {
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.check_circle,
                                      color: c['color'] as Color,
                                      size: 18,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      t,
                                      style: GoogleFonts.poppins(
                                        fontSize: 14,
                                        color: textDark,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }).toList()),
                            const SizedBox(height: 12),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                onPressed: () {},
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: c['color'] as Color,
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                ),
                                child: Text(
                                  'Learn More',
                                  style: GoogleFonts.poppins(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // TESTIMONIALS SECTION
  // ═══════════════════════════════════════════════════════════
  Widget _buildTestimonials() {
    final testimonials = [
      {
        'name': 'Ahmed K.',
        'grade': 'Grade 12',
        'text': 'The SAT Math course helped me score 780! The strategies are amazing.',
        'rating': 5,
      },
      {
        'name': 'Sara M.',
        'grade': 'Grade 11',
        'text': 'EST Math prep was exactly what I needed. Clear explanations and great practice.',
        'rating': 5,
      },
      {
        'name': 'Omar H.',
        'grade': 'Grade 10',
        'text': 'Secondary math became so much easier. The video lessons are top quality!',
        'rating': 5,
      },
    ];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 50, horizontal: 24),
      child: Column(
        children: [
          Text(
            'What Students Say',
            style: GoogleFonts.poppins(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: textDark,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            width: 60,
            height: 4,
            decoration: BoxDecoration(
              color: accentGold,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 40),
          Wrap(
            spacing: 20,
            runSpacing: 20,
            alignment: WrapAlignment.center,
            children: testimonials.map((t) {
              return SizedBox(
                width: 340,
                child: Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                    border: Border.all(
                      color: primaryGreen.withOpacity(0.1),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: List.generate(
                          t['rating'] as int,
                          (_) => const Icon(
                            Icons.star,
                            color: accentGold,
                            size: 18,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        '"${t['text']}"',
                        style: GoogleFonts.poppins(
                          fontSize: 14,
                          color: textDark,
                          height: 1.6,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: primaryGreen.withOpacity(0.15),
                              shape: BoxShape.circle,
                            ),
                            child: Center(
                              child: Text(
                                (t['name'] as String)[0],
                                style: GoogleFonts.poppins(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: primaryGreen,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                t['name'] as String,
                                style: GoogleFonts.poppins(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color: textDark,
                                ),
                              ),
                              Text(
                                t['grade'] as String,
                                style: GoogleFonts.poppins(
                                  fontSize: 12,
                                  color: textMuted,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // QR SECTION
  // ═══════════════════════════════════════════════════════════
  Widget _buildQrSection() {
    return Container(
      width: double.infinity,
      color: cardBg,
      padding: const EdgeInsets.symmetric(vertical: 50, horizontal: 24),
      child: Column(
        children: [
          Text(
            'Connect With Us',
            style: GoogleFonts.poppins(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: textDark,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            width: 60,
            height: 4,
            decoration: BoxDecoration(
              color: accentGold,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Scan or tap to connect',
            style: GoogleFonts.poppins(
              fontSize: 14,
              color: textMuted,
            ),
          ),
          const SizedBox(height: 40),
          Wrap(
            spacing: 30,
            runSpacing: 30,
            alignment: WrapAlignment.center,
            children: [
              _buildQrItem(
                imagePath: 'assets/WhatsApp Image 2026-08-08 at 1.34.33 AM.jpeg',
                label: 'WhatsApp',
                url: whatsappUrl,
                brandColor: const Color(0xFF25D366),
              ),
              _buildQrItem(
                imagePath: 'assets/WhatsApp Image 2026-08-08 at 1.38.09 AM.jpeg',
                label: 'Telegram',
                url: telegramUrl,
                brandColor: const Color(0xFF0088CC),
              ),
              _buildQrItem(
                imagePath: 'assets/youtube qr.jpeg',
                label: 'YouTube',
                url: youtubeUrl,
                brandColor: const Color(0xFFFF0000),
                fallbackIcon: Icons.play_circle_fill,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildQrItem({
    required String imagePath,
    required String label,
    required String url,
    required Color brandColor,
    IconData? fallbackIcon,
  }) {
    return GestureDetector(
      onTap: () => _launchUrl(url),
      child: Column(
        children: [
          Container(
            width: 110,
            height: 110,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              boxShadow: [
                BoxShadow(
                  color: brandColor.withOpacity(0.2),
                  blurRadius: 15,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.asset(
                imagePath,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) {
                  return Center(
                    child: Icon(
                      fallbackIcon ?? Icons.qr_code_2,
                      color: brandColor,
                      size: 48,
                    ),
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
            decoration: BoxDecoration(
              color: brandColor.withOpacity(0.15),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              label,
              style: GoogleFonts.poppins(
                fontSize: 12,
                color: brandColor,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // INVITE SECTION
  // ═══════════════════════════════════════════════════════════
  Widget _buildInviteSection() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 50, horizontal: 24),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [primaryGreen, secondaryGreen],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.15),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.people_alt_rounded,
              color: Colors.white,
              size: 40,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Invite Your Friends',
            style: GoogleFonts.poppins(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Share the app with your friends and study together!',
            style: GoogleFonts.poppins(
              fontSize: 15,
              color: Colors.white.withOpacity(0.85),
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: 240,
            height: 54,
            child: ElevatedButton.icon(
              onPressed: _shareInviteLink,
              icon: const Icon(Icons.share_rounded, size: 22),
              label: Text(
                'Share Invite Link',
                style: GoogleFonts.poppins(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: accentGold,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                elevation: 4,
                shadowColor: accentGold.withOpacity(0.4),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // FOOTER
  // ═══════════════════════════════════════════════════════════
  Widget _buildFooter() {
    return Container(
      width: double.infinity,
      color: darkBg,
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.school, color: accentGold, size: 28),
              const SizedBox(width: 10),
              Text(
                'Wael Math Academy',
                style: GoogleFonts.poppins(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Text(
            'Master SAT Math, EST Math & Secondary Mathematics',
            style: GoogleFonts.poppins(
              fontSize: 14,
              color: Colors.white.withOpacity(0.6),
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildFooterIcon(Icons.phone, '0100 391 2064'),
            ],
          ),
          const SizedBox(height: 24),
          Divider(color: Colors.white.withOpacity(0.1)),
          const SizedBox(height: 16),
          Text(
            '© 2026 Wael Math Academy. All rights reserved.',
            style: GoogleFonts.poppins(
              fontSize: 12,
              color: Colors.white.withOpacity(0.4),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFooterIcon(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: accentGold, size: 16),
        const SizedBox(width: 8),
        Text(
          text,
          style: GoogleFonts.poppins(
            fontSize: 14,
            color: Colors.white.withOpacity(0.7),
          ),
        ),
      ],
    );
  }
}
