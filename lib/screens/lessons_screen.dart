import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:wael_mcp/services/video_service.dart';
import 'video_player_screen.dart';

class LessonsScreen extends StatefulWidget {
  final String courseId;
  final String courseTitle;

  const LessonsScreen({
    super.key,
    required this.courseId,
    required this.courseTitle,
  });

  @override
  State<LessonsScreen> createState() => _LessonsScreenState();
}

class _LessonsScreenState extends State<LessonsScreen> {
  List<Map<String, dynamic>> lessons = [];
  bool isLoading = true;
  String? error;

  @override
  void initState() {
    super.initState();
    _loadLessons();
  }

  Future<void> _loadLessons() async {
    try {
      setState(() {
        isLoading = true;
        error = null;
      });
      final data = await VideoService.getCourseLessons(widget.courseId);
      if (mounted) {
        setState(() {
          lessons = data;
          isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          error = e.toString();
          isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final watched = lessons.where((l) => l['watched'] == true).length;
    final total = lessons.length;
    final progressPercent = total > 0 ? (watched / total) : 0.0;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          // ===== APP BAR =====
          SliverAppBar(
            expandedHeight: 180,
            floating: false,
            pinned: true,
            stretch: true,
            backgroundColor: const Color(0xFF2575FC),
            leading: IconButton(
              icon: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.arrow_back_ios_new_rounded,
                    color: Colors.white, size: 18),
              ),
              onPressed: () => Navigator.pop(context),
            ),
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF6A11CB), Color(0xFF2575FC)],
                  ),
                ),
                child: Stack(
                  children: [
                    Positioned(
                      right: -30,
                      top: -30,
                      child: Container(
                        width: 160,
                        height: 160,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withOpacity(0.06),
                        ),
                      ),
                    ),
                    SafeArea(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(24, 50, 24, 20),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.courseTitle,
                              style: GoogleFonts.poppins(
                                color: Colors.white,
                                fontSize: 22,
                                fontWeight: FontWeight.w700,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 12),
                            if (!isLoading && error == null)
                              _buildHeaderProgress(
                                  watched, total, progressPercent),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // ===== BODY =====
          SliverToBoxAdapter(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildHeaderProgress(int watched, int total, double percent) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              '$watched / $total lessons completed',
              style: GoogleFonts.poppins(
                color: Colors.white70,
                fontSize: 13,
              ),
            ),
            const Spacer(),
            Text(
              '${(percent * 100).toInt()}%',
              style: GoogleFonts.poppins(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 14,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: LinearProgressIndicator(
            value: percent,
            minHeight: 8,
            backgroundColor: Colors.white.withOpacity(0.2),
            valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
          ),
        ),
      ],
    ).animate().fadeIn(delay: 300.ms);
  }

  Widget _buildBody() {
    // Loading
    if (isLoading) {
      return Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: List.generate(4, (i) {
            return Container(
              margin: const EdgeInsets.only(bottom: 14),
              height: 90,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
              ),
            )
                .animate(onPlay: (c) => c.repeat(reverse: true))
                .shimmer(duration: 1200.ms, color: Colors.grey.shade200);
          }),
        ),
      );
    }

    // Error
    if (error != null) {
      return Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          children: [
            const SizedBox(height: 40),
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.error_outline_rounded,
                  size: 40, color: Colors.red.shade300),
            ).animate().fadeIn().shakeX(hz: 2, amount: 5),
            const SizedBox(height: 20),
            Text(
              error!,
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(color: Colors.grey[600]),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: _loadLessons,
              icon: const Icon(Icons.refresh_rounded),
              label: Text('Retry',
                  style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2575FC),
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ],
        ),
      );
    }

    // Empty
    if (lessons.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          children: [
            const SizedBox(height: 50),
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.video_library_outlined,
                  size: 40, color: Colors.grey.shade400),
            ).animate().fadeIn().scale(begin: const Offset(0.8, 0.8)),
            const SizedBox(height: 16),
            Text(
              'No lessons yet',
              style: GoogleFonts.poppins(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
      );
    }

    // Lessons List
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 30),
      child: Column(
        children: List.generate(lessons.length, (index) {
          return _buildLessonTile(lessons[index], index);
        }),
      ),
    );
  }

  Widget _buildLessonTile(Map<String, dynamic> lesson, int index) {
    final watched = lesson['watched'] ?? false;
    final watchPercentage = (lesson['watch_percentage'] ?? 0) as int;
    final duration = lesson['duration_minutes'];
    final isFree = lesson['is_free'] ?? false;
    final videoType = lesson['video_type'] ?? 'youtube';

    String? thumbnailUrl;
    if (videoType == 'youtube') {
      thumbnailUrl =
          VideoService.getYoutubeThumbnail(lesson['video_url'] ?? '');
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: watched
                ? Colors.green.withOpacity(0.08)
                : Colors.black.withOpacity(0.05),
            blurRadius: 15,
            offset: const Offset(0, 4),
          ),
        ],
        border: watched
            ? Border.all(color: Colors.green.withOpacity(0.2), width: 1.5)
            : null,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => VideoPlayerScreen(lesson: lesson),
              ),
            ).then((_) => _loadLessons());
          },
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                // Number / Check
                _buildLessonNumber(index + 1, watched, watchPercentage),
                const SizedBox(width: 14),

                // Thumbnail
                _buildThumbnail(thumbnailUrl, videoType, watched),
                const SizedBox(width: 14),

                // Info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        lesson['title'] ?? '',
                        style: GoogleFonts.poppins(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                          color: watched
                              ? Colors.grey[500]
                              : const Color(0xFF1A1A2E),
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          if (duration != null) ...[
                            Icon(Icons.access_time_rounded,
                                size: 13, color: Colors.grey[400]),
                            const SizedBox(width: 3),
                            Text(
                              '${duration}m',
                              style: GoogleFonts.poppins(
                                fontSize: 12,
                                color: Colors.grey[400],
                              ),
                            ),
                            const SizedBox(width: 10),
                          ],
                          if (isFree)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.green.shade50,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                'FREE',
                                style: GoogleFonts.poppins(
                                  fontSize: 10,
                                  color: Colors.green,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          if (watched) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.green.shade50,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                '✅ Done',
                                style: GoogleFonts.poppins(
                                  fontSize: 10,
                                  color: Colors.green,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),

                // Arrow
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: watched
                        ? Colors.green.withOpacity(0.1)
                        : const Color(0xFF2575FC).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.play_arrow_rounded,
                    color: watched ? Colors.green : const Color(0xFF2575FC),
                    size: 20,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    )
        .animate()
        .fadeIn(delay: Duration(milliseconds: 100 + (index * 80)))
        .slideX(begin: 0.1);
  }

  Widget _buildLessonNumber(int number, bool watched, int watchPercentage) {
    return Container(
      width: 46,
      height: 46,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: watched
            ? const LinearGradient(
                colors: [Color(0xFF4CAF50), Color(0xFF66BB6A)])
            : null,
        color: watched ? null : Colors.grey.shade50,
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (watchPercentage > 0 && !watched)
            SizedBox(
              width: 46,
              height: 46,
              child: CircularProgressIndicator(
                value: watchPercentage / 100,
                strokeWidth: 3,
                color: const Color(0xFF2575FC),
                backgroundColor: Colors.transparent,
              ),
            ),
          watched
              ? const Icon(Icons.check_rounded, color: Colors.white, size: 22)
              : Text(
                  '$number',
                  style: GoogleFonts.poppins(
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF2575FC),
                    fontSize: 16,
                  ),
                ),
        ],
      ),
    );
  }

  Widget _buildThumbnail(String? url, String videoType, bool watched) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Stack(
        children: [
          if (url != null)
            Image.network(
              url,
              width: 85,
              height: 55,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => _placeholderThumb(videoType),
            )
          else
            _placeholderThumb(videoType),
          // Overlay on watched
          if (watched)
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Center(
                  child: Icon(Icons.check_circle,
                      color: Colors.white, size: 22),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _placeholderThumb(String type) {
    return Container(
      width: 85,
      height: 55,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF6A11CB), Color(0xFF2575FC)],
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(
        type == 'direct' ? Icons.video_file_rounded : Icons.play_arrow_rounded,
        color: Colors.white,
        size: 24,
      ),
    );
  }
}