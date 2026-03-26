import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:wael_mcp/services/video_service.dart';
import 'dart:html' as html;
import 'dart:ui_web' as ui_web;
import 'dart:async';
import 'dart:js' as js;
import 'dart:math' as math;

class VideoPlayerScreen extends StatefulWidget {
  final Map<String, dynamic> lesson;
  const VideoPlayerScreen({super.key, required this.lesson});

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen>
    with WidgetsBindingObserver {
  bool _isLoading = true;
  bool _accessDenied = false;
  String _errorMessage = '';
  Map<String, dynamic>? _accessData;
  late final String _viewId;
  bool _iframeRegistered = false;
  Timer? _heartbeatTimer;
  Timer? _devToolsTimer;
  bool _markedAsWatched = false;
  bool _devToolsDetected = false;
  double _watchedPercent = 0.0;
  bool _watchCountRecorded = false;
  int _totalSecondsWatched = 0;

  // Listeners for cleanup
  final List<StreamSubscription> _subscriptions = [];
  html.StyleElement? _protectionStyle;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _viewId =
        'video-${widget.lesson['id'] ?? DateTime.now().millisecondsSinceEpoch}';
    _injectGlobalProtectionCSS();
    _enableAllProtections();
    _requestAccess();
  }

  @override
  void dispose() {
    // لو خرج وكان قرب من النهاية (60%+) سجل المشاهدة
    // ✅ غيرنا 0.6 → 0.7 عشان يتطابق مع الـ heartbeat
    if (_watchedPercent >= 0.7 && !_watchCountRecorded) {
      _recordWatchCount();
    }
    WidgetsBinding.instance.removeObserver(this);
    _heartbeatTimer?.cancel();
    _devToolsTimer?.cancel();
    _removeAllProtections();
    super.dispose();
  }

  // =============================================
  //  🔒 LAYER 1: Global CSS Protection
  // =============================================

  void _injectGlobalProtectionCSS() {
    _protectionStyle = html.StyleElement()
      ..text = '''
        /* ===== WAEL MCP VIDEO PROTECTION ===== */
        
        /* Disable ALL selection */
        body, html, * {
          -webkit-user-select: none !important;
          -moz-user-select: none !important;
          -ms-user-select: none !important;
          user-select: none !important;
          -webkit-touch-callout: none !important;
        }
        
        /* Disable drag */
        img, video, iframe, a, * {
          -webkit-user-drag: none !important;
          -khtml-user-drag: none !important;
          -moz-user-drag: none !important;
          -o-user-drag: none !important;
          user-drag: none !important;
          draggable: false !important;
        }
        
        /* Disable printing */
        @media print {
          body, html {
            display: none !important;
            visibility: hidden !important;
          }
        }
        
        /* Disable image toolbar in Edge/IE */
        img {
          -ms-interpolation-mode: nearest-neighbor;
        }
        
        /* Make iframe non-downloadable */
        iframe {
          pointer-events: auto;
        }
      ''';
    html.document.head?.append(_protectionStyle!);
  }

  // =============================================
  //  🛡️ LAYER 2: Event-Level Protections
  // =============================================

  void _enableAllProtections() {
    // 2a. Block right-click on ENTIRE document
    _subscriptions.add(
      html.document.onContextMenu.listen((e) {
        e.preventDefault();
        e.stopPropagation();
        _showWarning('Right-click is disabled');
      }),
    );

    // 2b. Block ALL dangerous keyboard shortcuts
    _subscriptions.add(
      html.document.onKeyDown.listen((event) {
        final key = event.keyCode;
        final ctrl = event.ctrlKey || event.metaKey; // Cmd on Mac
        final shift = event.shiftKey;

        // PrintScreen
        if (key == 44) {
          event.preventDefault();
          event.stopPropagation();
          _showWarning('Screenshots are not allowed');
          return;
        }

        // F12 — DevTools
        if (key == 123) {
          event.preventDefault();
          event.stopPropagation();
          _showWarning('Developer tools are blocked');
          return;
        }

        // Ctrl/Cmd + S — Save
        if (ctrl && key == 83) {
          event.preventDefault();
          event.stopPropagation();
          return;
        }

        // Ctrl/Cmd + U — View Source
        if (ctrl && key == 85) {
          event.preventDefault();
          event.stopPropagation();
          return;
        }

        // Ctrl/Cmd + P — Print
        if (ctrl && key == 80) {
          event.preventDefault();
          event.stopPropagation();
          _showWarning('Printing is not allowed');
          return;
        }

        // Ctrl + Shift + I — DevTools
        if (ctrl && shift && key == 73) {
          event.preventDefault();
          event.stopPropagation();
          _showWarning('Developer tools are blocked');
          return;
        }

        // Ctrl + Shift + J — Console
        if (ctrl && shift && key == 74) {
          event.preventDefault();
          event.stopPropagation();
          return;
        }

        // Ctrl + Shift + C — Inspect Element
        if (ctrl && shift && key == 67) {
          event.preventDefault();
          event.stopPropagation();
          return;
        }

        // Ctrl + Shift + S — Screenshot (some browsers)
        if (ctrl && shift && key == 83) {
          event.preventDefault();
          event.stopPropagation();
          return;
        }

        // Ctrl + A — Select All
        if (ctrl && key == 65) {
          event.preventDefault();
          return;
        }
      }),
    );

    // 2c. Block drag events
    _subscriptions.add(
      html.document.onDragStart.listen((e) {
        e.preventDefault();
      }),
    );

    // 2d. Block drop events
    _subscriptions.add(
      html.document.onDrop.listen((e) {
        e.preventDefault();
      }),
    );

    // 2e. Detect tab switch / visibility change
    _subscriptions.add(
      html.document.onVisibilityChange.listen((_) {
        if (html.document.hidden ?? false) {
          debugPrint('User left tab — video page');
        }
      }),
    );

    // 2f. Block beforeprint event
    _subscriptions.add(
      html.window.on['beforeprint'].listen((e) {
        _showWarning('Printing is not allowed');
      }),
    );

    // 2g. DevTools detection via debugger timing
    _startDevToolsDetection();
  }

  void _startDevToolsDetection() {
    _devToolsTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      final start = DateTime.now().millisecondsSinceEpoch;

      // This trick: console.log with %c runs slower when DevTools is open
      js.context.callMethod('eval', [
        '''
        (function() {
          var devtools = false;
          var threshold = 160;
          var widthThreshold = window.outerWidth - window.innerWidth > threshold;
          var heightThreshold = window.outerHeight - window.innerHeight > threshold;
          if (widthThreshold || heightThreshold) {
            devtools = true;
          }
          window.__devtools_open = devtools;
        })();
        '''
      ]);

      final isOpen = js.context['__devtools_open'] as bool? ?? false;

      if (isOpen && mounted && !_devToolsDetected) {
        setState(() => _devToolsDetected = true);
        _showWarning('Developer tools detected! Close them to continue.');
      } else if (!isOpen && mounted && _devToolsDetected) {
        setState(() => _devToolsDetected = false);
      }
    });
  }

  void _removeAllProtections() {
    for (final sub in _subscriptions) {
      sub.cancel();
    }
    _subscriptions.clear();
    _protectionStyle?.remove();
    _devToolsTimer?.cancel();
  }

  void _showWarning(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.shield_rounded, color: Colors.white, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '⚠️ $message',
                style: GoogleFonts.poppins(
                    color: Colors.white, fontWeight: FontWeight.w500),
              ),
            ),
          ],
        ),
        backgroundColor: Colors.red.shade700,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  // =============================================
  //  ACCESS CONTROL
  // =============================================

  Future<void> _requestAccess() async {
    try {
      setState(() {
        _isLoading = true;
        _accessDenied = false;
      });

      final data =
          await VideoService.requestVideoAccess(widget.lesson['id']);
      if (mounted) {
        setState(() {
          _accessData = data;
          _isLoading = false;
        });
        _registerProtectedIframe(data);
        _startHeartbeat();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _accessDenied = true;
          _errorMessage = e.toString().replaceAll('Exception: ', '');
        });
      }
    }
  }

  // =============================================
  //  🧱 LAYER 3: Protected iframe with FULL overlay
  // =============================================

  void _registerProtectedIframe(Map<String, dynamic> data) {
    final videoUrl = data['video_url'] ?? '';
    final videoType = data['video_type'] ?? 'youtube';
    final studentName = data['student_name'] ?? 'Student';
    final studentEmail = data['student_email'] ?? '';
    final studentId = data['student_id'] ?? '';
    final embedUrl = _getEmbedUrl(videoUrl, videoType);
    final timestamp = DateTime.now().toIso8601String();

    ui_web.platformViewRegistry.registerViewFactory(
      _viewId,
      (int viewId) {
        // معرفة ما إذا كان الفيديو مباشراً (ليس يوتيوب أو فيميو)
        final bool isDirectVideo =
            videoType != 'youtube' && videoType != 'vimeo';

        // === OUTER CONTAINER ===
        final container = html.DivElement()
          ..style.position = 'relative'
          ..style.width = '100%'
          ..style.height = '100%'
          ..style.overflow = 'hidden'
          ..style.userSelect = 'none'
          ..style.borderRadius = '16px'
          // منع أي تفاعل إضافي بالماوس في قائمة السياق
          ..onContextMenu.listen((e) => e.preventDefault())
          ..setAttribute('oncontextmenu', 'return false;')
          ..setAttribute('onselectstart', 'return false;')
          ..setAttribute('ondragstart', 'return false;');

        // === MEDIA ELEMENT (Video / IFrame) ===
        final html.Element mediaElement = isDirectVideo
            ? (html.VideoElement()
              ..src = embedUrl
              ..controls = true // نحتاج إظهار الكنترولز لأنها من المتصفح
              ..style.border = 'none'
              ..style.width = '100%'
              ..style.height = '100%'
              ..style.borderRadius = '16px'
              ..setAttribute('controlslist', 'nodownload nofullscreen') // ❌ Disable download and fullscreen
              ..setAttribute('disablepictureinpicture', 'true')
              // 🚫 THE REAL FIX FOR "SAVE VIDEO AS" 🚫
              ..onContextMenu.listen((e) {
                e.preventDefault();
                e.stopPropagation();
              }))
            : (html.IFrameElement()
              ..src = embedUrl
              ..style.border = 'none'
              ..style.width = '100%'
              ..style.height = '100%'
              ..style.borderRadius = '16px'
              ..allowFullscreen = false // ❌ Disable fullscreen
              ..setAttribute('sandbox',
                  'allow-scripts allow-same-origin allow-presentation allow-popups allow-forms')
              ..setAttribute('allow',
                  'accelerometer; autoplay; encrypted-media; gyroscope; picture-in-picture'));

        // === 🎭 LAYER 3a: FULL transparent overlay (blocks ALL interaction except play) ===
        final fullOverlay = html.DivElement()
          ..style.position = 'absolute'
          ..style.top = '0'
          ..style.left = '0'
          ..style.width = '100%'
          ..style.height = '100%'
          ..style.zIndex = '10000'
          ..style.background = 'transparent'
          // Allow clicks to pass through to iframe (for play button)
          ..style.pointerEvents = 'none';

        // === 🎭 LAYER 3b: TOP shield (blocks right-click on video controls) ===
        final topShield = html.DivElement()
          ..style.position = 'absolute'
          ..style.top = '0'
          ..style.left = '0'
          ..style.width = '100%'
          ..style.height = '50px'
          ..style.zIndex = '10001'
          ..style.background = 'transparent'
          ..style.pointerEvents = 'auto' // ← Blocks interaction on top area
          ..style.cursor = 'default';

        // Block right-click on top shield
        topShield.onContextMenu.listen((e) {
          e.preventDefault();
          e.stopPropagation();
        });

        // === 🎭 LAYER 3c: BOTTOM shield (blocks download button area) ===
        final bottomShield = html.DivElement()
          ..style.position = 'absolute'
          ..style.bottom = '0'
          ..style.left = '0'
          ..style.width = '100%'
          ..style.height = '45px'
          ..style.zIndex = '10001'
          ..style.background = 'transparent'
          ..style.pointerEvents = 'auto'
          ..style.cursor = 'default';

        bottomShield.onContextMenu.listen((e) {
          e.preventDefault();
          e.stopPropagation();
        });

        // === 🎭 LAYER 3d: RIGHT side shield (blocks kebab menu / 3-dots) ===
        final rightShield = html.DivElement()
          ..style.position = 'absolute'
          ..style.top = '0'
          ..style.right = '0'
          ..style.width = '60px'
          ..style.height = '100%'
          ..style.zIndex = '10001'
          ..style.background = 'transparent'
          ..style.pointerEvents = 'auto'
          ..style.cursor = 'default';

        rightShield.onContextMenu.listen((e) {
          e.preventDefault();
          e.stopPropagation();
        });

        // === 🎨 DYNAMIC WATERMARK (multiple, moving) ===
        final watermarkContainer = html.DivElement()
          ..style.position = 'absolute'
          ..style.top = '0'
          ..style.left = '0'
          ..style.width = '100%'
          ..style.height = '100%'
          ..style.pointerEvents = 'none'
          ..style.zIndex = '9999'
          ..style.overflow = 'hidden';

        // Create multiple watermarks at random positions
        final random = math.Random();
        for (int i = 0; i < 4; i++) {
          final watermark = html.DivElement()
            ..style.position = 'absolute'
            ..style.opacity = '0.08'
            ..style.color = 'white'
            ..style.fontSize = '14px'
            ..style.fontWeight = 'bold'
            ..style.fontFamily = 'monospace'
            ..style.transform = 'rotate(-${25 + random.nextInt(15)}deg)'
            ..style.textShadow = '1px 1px 3px rgba(0,0,0,0.3)'
            ..style.whiteSpace = 'nowrap'
            ..style.pointerEvents = 'none'
            ..text = '$studentName • $studentEmail • $timestamp';

          // Position each watermark differently
          switch (i) {
            case 0:
              watermark.style.top = '15%';
              watermark.style.left = '5%';
              break;
            case 1:
              watermark.style.top = '45%';
              watermark.style.right = '5%';
              break;
            case 2:
              watermark.style.bottom = '25%';
              watermark.style.left = '15%';
              break;
            case 3:
              watermark.style.top = '70%';
              watermark.style.left = '40%';
              break;
          }
          watermarkContainer.children.add(watermark);
        }

        container.children.add(mediaElement);

        // الدروع صُممت خصيصاً لمشغلات الـ IFrame مثل يوتيوب لتعطيل الوصول لأجزاء معينة مثل أزرار القنوات
        if (!isDirectVideo) {
          container.children.addAll([
            fullOverlay,
            topShield,
            bottomShield,
            rightShield,
          ]);
        }
        
        // العلامة المائية تضاف دائماً
        container.children.add(watermarkContainer);

        return container;
      },
    );
    setState(() => _iframeRegistered = true);
  }

  String _getEmbedUrl(String url, String type) {
    if (type == 'youtube') {
      final videoId = VideoService.extractYoutubeId(url);
      if (videoId != null) {
        return 'https://www.youtube.com/embed/$videoId'
            '?rel=0'
            '&modestbranding=1'
            '&enablejsapi=1' // ✅ مهم عشان نتابع البروجريس
            '&origin=${html.window.location.origin}'
            '&disablekb=1' // Disable keyboard controls
            '&fs=0' // Disable fullscreen button
            '&iv_load_policy=3' // Hide annotations
            '&controls=1'
            '&playsinline=1';
      }
    } else if (type == 'vimeo') {
      final vimeoRegex = RegExp(r'vimeo\.com/(\d+)');
      final match = vimeoRegex.firstMatch(url);
      if (match != null) {
        return 'https://player.vimeo.com/video/${match.group(1)}'
            '?title=0&byline=0&portrait=0&download=0';
      }
    }
    return url;
  }

  void _startHeartbeat() {
    const int watchThresholdSeconds = 180; // 3 دقايق بس
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 10), (_) async {
      if (!mounted) return;

      // احسب الوقت اللي الطالب قضاه فعلاً في الصفحة
      _totalSecondsWatched += 10;

      // ✅ لو مفيش duration_minutes خد 5 دقايق كـ default بدل 10
      final lessonDuration = (widget.lesson['duration_minutes'] ?? 5) * 60;
      _watchedPercent = (_totalSecondsWatched / lessonDuration).clamp(0.0, 1.0);

      debugPrint(
          '⏱️ Watched: $_totalSecondsWatched s / $lessonDuration s '
          '= ${(_watchedPercent * 100).toStringAsFixed(1)}%');

      // ✅ سجل لو عدى 3 دقايق أو 70% أيهما أقل
      if ((_totalSecondsWatched >= watchThresholdSeconds ||
              _watchedPercent >= 0.7) &&
          !_watchCountRecorded) {
        await _recordWatchCount();
      }
    });
  }

  Future<void> _recordWatchCount() async {
    if (_watchCountRecorded) return;
    _watchCountRecorded = true;

    try {
      // ⚠️ NOTE: Ensure recordWatch is implemented in VideoService
      await VideoService.recordWatch(widget.lesson['id']);
      debugPrint(
          '✅ Watch recorded at ${(_watchedPercent * 100).toStringAsFixed(1)}%');

      if (mounted) {
        setState(() {
          _markedAsWatched = true;
          // ✅ حدّث العداد في الـ UI
          if (_accessData != null) {
            final used = (_accessData!['watches_used'] ?? 0) + 1;
            _accessData!['watches_used'] = used;
            _accessData!['watches_remaining'] = (2 - used).clamp(0, 2);
          }
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.task_alt_rounded,
                    color: Colors.white, size: 18),
                const SizedBox(width: 10),
                Text(
                  'Watch recorded (${(_watchedPercent * 100).toInt()}% watched)',
                  style: GoogleFonts.poppins(color: Colors.white),
                ),
              ],
            ),
            backgroundColor: Colors.blue.shade700,
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            margin: const EdgeInsets.all(16),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      _watchCountRecorded = false; // عشان يحاول تاني
      debugPrint('❌ Error recording watch: $e');
    }
  }

  Future<void> _markAsWatched() async {
    if (_markedAsWatched) return;
    try {
      await VideoService.updateProgress(widget.lesson['id'], 100);
      if (mounted) {
        setState(() => _markedAsWatched = true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle_rounded,
                    color: Colors.white, size: 20),
                const SizedBox(width: 10),
                Text('Marked as watched!',
                    style: GoogleFonts.poppins(fontWeight: FontWeight.w500)),
              ],
            ),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
            margin: const EdgeInsets.all(16),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        _showWarning('Error: $e');
      }
    }
  }

  // =============================================
  //  UI
  // =============================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: _devToolsDetected ? _buildDevToolsWarning() : _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) return _buildLoadingState();
    if (_accessDenied) return _buildAccessDenied();
    return _buildPlayer();
  }

  // ===== DEVTOOLS DETECTED =====
  Widget _buildDevToolsWarning() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF1A0000), Color(0xFF0A0A0A)],
        ),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.2),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.dangerous_rounded,
                  size: 55, color: Colors.red),
            )
                .animate(onPlay: (c) => c.repeat(reverse: true))
                .scaleXY(begin: 1, end: 1.1, duration: 600.ms),
            const SizedBox(height: 28),
            Text(
              '⚠️ Developer Tools Detected',
              style: GoogleFonts.poppins(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: Colors.red,
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: Text(
                'Please close Developer Tools to continue watching the video.',
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  color: Colors.white54,
                ),
              ),
            ),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.arrow_back_rounded),
              label: Text('Go Back',
                  style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red.shade700,
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ===== LOADING =====
  Widget _buildLoadingState() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF1A1A2E), Color(0xFF0A0A0A)],
        ),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: const Color(0xFF2575FC).withOpacity(0.15),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(Icons.play_circle_rounded,
                  color: Color(0xFF2575FC), size: 45),
            )
                .animate(onPlay: (c) => c.repeat(reverse: true))
                .scaleXY(begin: 1, end: 1.1, duration: 800.ms),
            const SizedBox(height: 24),
            Text(
              'Verifying access...',
              style: GoogleFonts.poppins(color: Colors.white60, fontSize: 16),
            ).animate().fadeIn(delay: 200.ms),
            const SizedBox(height: 8),
            Text(
              'Checking security layers',
              style: GoogleFonts.poppins(color: Colors.white30, fontSize: 12),
            ).animate().fadeIn(delay: 400.ms),
            const SizedBox(height: 20),
            SizedBox(
              width: 40,
              child: LinearProgressIndicator(
                backgroundColor: Colors.white.withOpacity(0.1),
                valueColor: const AlwaysStoppedAnimation(Color(0xFF2575FC)),
                borderRadius: BorderRadius.circular(10),
              ),
            ).animate().fadeIn(delay: 500.ms),
          ],
        ),
      ),
    );
  }

  // ===== ACCESS DENIED =====
  Widget _buildAccessDenied() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF1A1A2E), Color(0xFF0A0A0A)],
        ),
      ),
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(children: [_buildBackButton()]),
            ),
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 100,
                        height: 100,
                        decoration: BoxDecoration(
                          color: Colors.red.withOpacity(0.15),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.lock_rounded,
                            size: 50, color: Colors.redAccent),
                      )
                          .animate()
                          .fadeIn()
                          .shakeX(hz: 2, amount: 6, duration: 500.ms),
                      const SizedBox(height: 28),
                      Text('Access Denied',
                          style: GoogleFonts.poppins(
                              fontSize: 26,
                              fontWeight: FontWeight.w700,
                              color: Colors.white)),
                      const SizedBox(height: 12),
                      Text(_errorMessage,
                          textAlign: TextAlign.center,
                          style: GoogleFonts.poppins(
                              fontSize: 14, color: Colors.white54)),
                      const SizedBox(height: 28),
                      Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: Colors.amber.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(16),
                          border:
                              Border.all(color: Colors.amber.withOpacity(0.3)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.info_outline_rounded,
                                color: Colors.amber, size: 22),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'Contact your teacher to reset your watch count.',
                                style: GoogleFonts.poppins(
                                    color: Colors.amber, fontSize: 13),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 28),
                      ElevatedButton.icon(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.arrow_back_rounded),
                        label: Text('Go Back',
                            style: GoogleFonts.poppins(
                                fontWeight: FontWeight.w600)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white.withOpacity(0.1),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 32, vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                            side: BorderSide(
                                color: Colors.white.withOpacity(0.2)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ===== VIDEO PLAYER =====
  Widget _buildPlayer() {
    final watchesUsed = _accessData?['watches_used'] ?? 0;
    final watchesRemaining = _accessData?['watches_remaining'] ?? 0;
    final watched = widget.lesson['watched'] ?? false;
    final isLastWatch = watchesRemaining == 0;

    return SafeArea(
      child: Column(
        children: [
          // TOP BAR
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                _buildBackButton(),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    widget.lesson['title'] ?? 'Lesson',
                    style: GoogleFonts.poppins(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                // Watch badge
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: isLastWatch
                        ? Colors.red.withOpacity(0.2)
                        : Colors.white.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                        color: isLastWatch
                            ? Colors.red.withOpacity(0.4)
                            : Colors.white.withOpacity(0.15)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isLastWatch
                            ? Icons.warning_amber_rounded
                            : Icons.visibility_rounded,
                        color:
                            isLastWatch ? Colors.redAccent : Colors.white70,
                        size: 16,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '$watchesUsed/2',
                        style: GoogleFonts.poppins(
                          color: isLastWatch
                              ? Colors.redAccent
                              : Colors.white70,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                // Security badge
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.shield_rounded,
                      color: Colors.greenAccent, size: 18),
                ),
              ],
            ),
          ).animate().fadeIn(duration: 300.ms),

          // LAST WATCH WARNING
          if (isLastWatch)
            Container(
              width: double.infinity,
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              margin: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [
                  Colors.red.shade800.withOpacity(0.6),
                  Colors.red.shade900.withOpacity(0.6),
                ]),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.warning_rounded,
                      color: Colors.amber, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    'This is your last watch!',
                    style: GoogleFonts.poppins(
                        color: Colors.amber,
                        fontSize: 12,
                        fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ).animate().fadeIn().shakeX(hz: 2, amount: 3, duration: 400.ms),

          if (isLastWatch) const SizedBox(height: 8),

          // VIDEO PLAYER
          Expanded(
            flex: 5,
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF2575FC).withOpacity(0.2),
                    blurRadius: 30,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: _iframeRegistered
                    ? HtmlElementView(viewType: _viewId)
                    : Container(
                        color: const Color(0xFF1A1A2E),
                        child: Center(
                          child: CircularProgressIndicator(
                            color: Colors.white.withOpacity(0.5),
                            strokeWidth: 2,
                          ),
                        ),
                      ),
              ),
            ).animate().fadeIn(delay: 200.ms, duration: 500.ms),
          ),

          const SizedBox(height: 12),

          // LESSON INFO
          Expanded(
            flex: 3,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
              decoration: BoxDecoration(
                color: const Color(0xFF141425),
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(24)),
                border: Border(
                  top: BorderSide(
                      color: Colors.white.withOpacity(0.08), width: 1),
                ),
              ),
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.lesson['title'] ?? '',
                      style: GoogleFonts.poppins(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: Colors.white),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 10,
                      runSpacing: 8,
                      children: [
                        if (widget.lesson['duration_minutes'] != null)
                          _buildChip(Icons.access_time_rounded,
                              '${widget.lesson['duration_minutes']} min'),
                        _buildChip(
                            Icons.visibility_rounded, '$watchesUsed/2'),
                        if (watched || _markedAsWatched)
                          _buildChip(Icons.check_circle_rounded,
                              'Completed',
                              color: Colors.green),
                        _buildChip(
                            Icons.shield_rounded, 'Protected',
                            color: Colors.greenAccent),
                      ],
                    ),
                    if (widget.lesson['description'] != null &&
                        widget.lesson['description']
                            .toString()
                            .isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Container(
                          height: 1,
                          color: Colors.white.withOpacity(0.08)),
                      const SizedBox(height: 14),
                      Text(
                        widget.lesson['description'],
                        style: GoogleFonts.poppins(
                            fontSize: 14,
                            color: Colors.white54,
                            height: 1.6),
                      ),
                    ],
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton.icon(
                        onPressed: (watched || _markedAsWatched)
                            ? null
                            : _markAsWatched,
                        icon: Icon(
                          (watched || _markedAsWatched)
                              ? Icons.check_circle_rounded
                              : Icons.check_circle_outline_rounded,
                          size: 22,
                        ),
                        label: Text(
                          (watched || _markedAsWatched)
                              ? 'Watched ✅'
                              : 'Mark as Watched',
                          style: GoogleFonts.poppins(
                              fontSize: 15, fontWeight: FontWeight.w600),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: (watched || _markedAsWatched)
                              ? Colors.green.withOpacity(0.2)
                              : const Color(0xFF2575FC),
                          foregroundColor: (watched || _markedAsWatched)
                              ? Colors.green
                              : Colors.white,
                          disabledBackgroundColor:
                              Colors.green.withOpacity(0.15),
                          disabledForegroundColor: Colors.green,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14)),
                          elevation: 0,
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.04),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                            color: Colors.white.withOpacity(0.06)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.shield_rounded,
                              size: 18,
                              color: Colors.white.withOpacity(0.3)),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Protected • Watermarked • Monitored',
                              style: GoogleFonts.poppins(
                                  fontSize: 11,
                                  color: Colors.white.withOpacity(0.3)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ).animate().fadeIn(delay: 400.ms).slideY(begin: 0.1),
          ),
        ],
      ),
    );
  }

  Widget _buildBackButton() {
    return GestureDetector(
      onTap: () => Navigator.pop(context),
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withOpacity(0.1)),
        ),
        child: const Icon(Icons.arrow_back_ios_new_rounded,
            color: Colors.white, size: 18),
      ),
    );
  }

  Widget _buildChip(IconData icon, String text, {Color? color}) {
    final c = color ?? Colors.white.withOpacity(0.5);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: c.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: c.withOpacity(0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: c),
          const SizedBox(width: 5),
          Text(text,
              style: GoogleFonts.poppins(
                  fontSize: 12, color: c, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}