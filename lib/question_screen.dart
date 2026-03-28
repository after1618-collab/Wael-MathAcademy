import 'package:flutter/material.dart';
import 'package:wael_mcp/api_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:html' as html;
import 'dart:js' as js;
import 'dart:async';

class QuestionScreen extends StatefulWidget {
  final String sectionId;
  final String sectionName;

  const QuestionScreen({
    super.key,
    required this.sectionId,
    required this.sectionName,
  });

  @override
  State<QuestionScreen> createState() => _QuestionScreenState();
}

class _QuestionScreenState extends State<QuestionScreen> with WidgetsBindingObserver {
  late final Future<List<Map<String, dynamic>>> _questionsFuture;
  final PageController _pageController = PageController();
  final Map<String, String> _selectedAnswers = {};
  int _currentPage = 0;
  final Map<String, bool> _isCorrect = {};
  final Map<String, bool> _isRevealed = {};
  
  String _studentName = 'طالب';
  String _studentEmail = '';

  // 🛡️ Protection variables
  final List<StreamSubscription> _subscriptions = [];
  html.StyleElement? _protectionStyle;
  Timer? _devToolsTimer;
  bool _devToolsDetected = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _injectGlobalProtectionCSS();
    _enableAllProtections();
    _pageController.addListener(() =>
        setState(() => _currentPage = _pageController.page?.round() ?? 0));
    _questionsFuture = ApiService.getQuestions(widget.sectionId);
    _loadStudentProfile();
  }

  Future<void> _loadStudentProfile() async {
    try {
      final profile = await ApiService.getProfile();
      if (mounted) {
        setState(() {
          _studentName = profile['full_name'] ?? 'طالب';
          _studentEmail = profile['email'] ?? '';
        });
      }
    } catch (e) {
      debugPrint('Error loading profile for watermark: $e');
    }
  }

  // =============================================
  //  🔒 LAYER 1: Global CSS Protection
  // =============================================
  void _injectGlobalProtectionCSS() {
    _protectionStyle = html.StyleElement()
      ..text = '''
        /* ===== QUESTION PROTECTION ===== */
        
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
        
        /* Disable image toolbar */
        img {
          -ms-interpolation-mode: nearest-neighbor;
          pointer-events: none;
        }
      ''';
    html.document.head?.append(_protectionStyle!);
  }

  // =============================================
  //  🛡️ LAYER 2: Event-Level Protections
  // =============================================
  void _enableAllProtections() {
    _subscriptions.add(
      html.document.onContextMenu.listen((e) {
        e.preventDefault();
        e.stopPropagation();
        _showWarning('Right-click is disabled');
      }),
    );

    _subscriptions.add(
      html.document.onKeyDown.listen((event) {
        final key = event.keyCode;
        final ctrl = event.ctrlKey || event.metaKey;
        final shift = event.shiftKey;

        if (key == 44) {
          event.preventDefault();
          _showWarning('Screenshots are not allowed');
          return;
        }

        if (key == 123) {
          event.preventDefault();
          _showWarning('Developer tools are blocked');
          return;
        }

        if (ctrl && [83, 85, 80].contains(key)) {
          event.preventDefault();
          return;
        }

        if (ctrl && shift && [73, 74, 67].contains(key)) {
          event.preventDefault();
          return;
        }

        if (ctrl && key == 65) {
          event.preventDefault();
          return;
        }

        // ✅ التنقل بالأسهم (يمين = التالي، يسار = السابق)
        if (key == 39) { // Right Arrow
          _pageController.nextPage(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
          );
        } else if (key == 37) { // Left Arrow
          _pageController.previousPage(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
          );
        }
      }),
    );

    _subscriptions.add(html.document.onDragStart.listen((e) => e.preventDefault()));
    _subscriptions.add(html.document.onDrop.listen((e) => e.preventDefault()));
    _startDevToolsDetection();
  }

  void _startDevToolsDetection() {
    _devToolsTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      try {
        js.context.callMethod('eval', [
          '''
          (function() {
            var devtools = false;
            var threshold = 160;
            if (window.outerWidth - window.innerWidth > threshold ||
                window.outerHeight - window.innerHeight > threshold) {
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
      } catch (e) {
        debugPrint('DevTools detection error: $e');
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
            Expanded(child: Text('⚠️ $message', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500))),
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

  Widget _buildWatermarkText(String text, double angle) {
    return Transform.rotate(
      angle: angle,
      child: Text(
        text,
        style: TextStyle(
          color: Colors.black.withOpacity(0.19),
          fontSize: 12,
          fontWeight: FontWeight.bold,
          fontFamily: 'monospace',
        ),
      ),
    );
  }

  Future<void> _submitAnswer(String questionId, String answer,
      Map<String, dynamic> question) async {
    if (_selectedAnswers.containsKey(questionId)) return;

    final correctAnswer = question['correct_answer'] as String;
    final answerIsRevealed = _isRevealed[questionId] ?? false;
    final correct = answer.toUpperCase() == correctAnswer.toUpperCase();

    setState(() {
      _selectedAnswers[questionId] = answer;
      _isCorrect[questionId] = correct;
    });

    // ✅ احفظ في السيرفر عبر /attempts/submit
    try {
      await ApiService.submitAttempt(
        questionId: questionId,
        submittedAnswer: answer,
        revealed: answerIsRevealed,
      );
    } catch (e) {
      debugPrint('فشل حفظ الإجابة: $e');
    }
  }

  void _revealAnswer(String questionId) {
    if (_selectedAnswers.containsKey(questionId)) return;
    setState(() {
      _isRevealed[questionId] = true;
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _removeAllProtections();
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_devToolsDetected) {
      return Scaffold(
        backgroundColor: Colors.red.shade50,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.dangerous_rounded, size: 60, color: Colors.red),
              const SizedBox(height: 20),
              const Text(
                '⚠️ Developer Tools Detected',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.red,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'Please close Developer Tools to continue.',
                style: TextStyle(color: Colors.redAccent),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.sectionName),
        centerTitle: true,
        elevation: 0,
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _questionsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, size: 60, color: Colors.red),
                  const SizedBox(height: 15),
                  Text(
                    snapshot.error is ApiException
                        ? (snapshot.error as ApiException).message
                        : 'Error loading questions',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 15),
                  ElevatedButton.icon(
                    onPressed: () {
                      setState(() {
                        _questionsFuture = ApiService.getQuestions(widget.sectionId);
                      });
                    },
                    icon: const Icon(Icons.refresh),
                    label: const Text('Retry'),
                  ),
                ],
              ),
            );
          }
          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(
                child: Text('No questions in this section.'));
          }

          final questions = snapshot.data!;
          final studentInfo =
              "$_studentName • $_studentEmail • ${DateTime.now().toString().split(' ')[0]}";

          return Stack(
            children: [
              // المحتوى الأصلي (يجب أن يكون الأول في الـ Stack ليكون تحت العلامات المائية)
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildTopControls(questions.length),
                  Expanded(
                    child: PageView.builder(
                      controller: _pageController,
                      itemCount: questions.length,
                      // ✅ الصفحات المجاورة تتحمل مسبقاً = صور أسرع
                      allowImplicitScrolling: true,
                      itemBuilder: (context, index) {
                        return _buildQuestionLayout(questions[index]);
                      },
                    ),
                  ),
                ],
              ),

              // === 🛡️ WATERMARK LAYER (Text and Logo) ===
              Positioned.fill(
                child: IgnorePointer(
                  child: Stack(
                    children: [
                      // --- Logo Watermark In Center ---
                      Positioned.fill(
                        child: Center(
                          child: Opacity(
                            opacity: 0.15, // ✅ تقليل الشفافية إلى 0.15
                            child: Image.asset(
                              'assets/logo.jpg',
                              fit: BoxFit.scaleDown,
                              width: 600, // ✅ تم مضاعفة الحجم إلى 600
                              height: 600,
                            ),
                          ),
                        ),
                      ),
                      // --- Text Watermarks ---
                      // 1. Triple Central Watermarks (Requested: Top, Center, Bottom)
                      Align(
                        alignment: Alignment.topCenter,
                        child: Padding(
                          padding: const EdgeInsets.only(top: 80),
                          child: _buildWatermarkText(studentInfo, 0.0),
                        ),
                      ),
                      Align(
                        alignment: Alignment.center,
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 100), // ✅ رفعها للأعلى (حوالي 3 سم)
                          child: _buildWatermarkText(studentInfo, 0.0),
                        ),
                      ),
                      Align(
                        alignment: Alignment.bottomCenter,
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 220), // ✅ رفعها للأعلى (حوالي 3 سم إضافي)
                          child: _buildWatermarkText(studentInfo, 0.0),
                        ),
                      ),

                      // 2. Extra Corner and Intermediate Watermarks for protection
                      Positioned(
                        top: 20,
                        left: 20,
                        child: _buildWatermarkText(studentInfo, -0.3),
                      ),
                      Positioned(
                        top: 50,
                        right: 30,
                        child: _buildWatermarkText(studentInfo, 0.2),
                      ),
                      Positioned(
                        top: MediaQuery.of(context).size.height * 0.25,
                        left: 50,
                        child: _buildWatermarkText(studentInfo, 0.1),
                      ),
                      Positioned(
                        top: MediaQuery.of(context).size.height * 0.25,
                        right: 50,
                        child: _buildWatermarkText(studentInfo, -0.15),
                      ),
                      Positioned(
                        top: MediaQuery.of(context).size.height * 0.45,
                        left: 10,
                        child: _buildWatermarkText(studentInfo, -0.1),
                      ),
                      Positioned(
                        top: MediaQuery.of(context).size.height * 0.45,
                        right: 10,
                        child: _buildWatermarkText(studentInfo, 0.12),
                      ),
                      Positioned(
                        top: MediaQuery.of(context).size.height * 0.65,
                        left: 60,
                        child: _buildWatermarkText(studentInfo, 0.25),
                      ),
                      Positioned(
                        top: MediaQuery.of(context).size.height * 0.65,
                        right: 60,
                        child: _buildWatermarkText(studentInfo, -0.2),
                      ),
                      Positioned(
                        bottom: 180,
                        left: 40,
                        child: _buildWatermarkText(studentInfo, -0.2),
                      ),
                      Positioned(
                        bottom: 180,
                        right: 40,
                        child: _buildWatermarkText(studentInfo, 0.3),
                      ),
                      Positioned(
                        bottom: 40,
                        right: 20,
                        child: _buildWatermarkText(studentInfo, 0.15),
                      ),
                      Positioned(
                        bottom: 40,
                        left: 20,
                        child: _buildWatermarkText(studentInfo, -0.12),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildTopControls(int totalQuestions) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0),
      color: Theme.of(context).appBarTheme.backgroundColor?.withOpacity(0.1),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_ios),
            onPressed: _currentPage == 0
                ? null
                : () => _pageController.previousPage(
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeInOut,
                    ),
          ),
          Expanded(
            child: Column(
              children: [
                Text('Question ${_currentPage + 1} / $totalQuestions',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                LinearProgressIndicator(
                  value: (totalQuestions > 0)
                      ? (_currentPage + 1) / totalQuestions
                      : 0,
                  minHeight: 8,
                  borderRadius: BorderRadius.circular(4),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.arrow_forward_ios),
            onPressed: _currentPage == totalQuestions - 1
                ? null
                : () => _pageController.nextPage(
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeInOut,
                    ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuestionLayout(Map<String, dynamic> question) {
    final questionId = question['id'].toString();
    // ✅ الـ image_url جاي من السيرفر جاهز
    final imageUrl = question['image_url'] as String?;
    final options =
        List<String>.from(question['options'] ?? ['A', 'B', 'C', 'D']);

    final hasAnswered = _selectedAnswers.containsKey(questionId);
    final answerIsRevealed = _isRevealed[questionId] ?? false;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 16),
          // ✅ صورة السؤال مع cacheWidth لتحسين الأداء
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              clipBehavior: Clip.antiAlias,
              child: imageUrl != null
                  ? InteractiveViewer(
                      panEnabled: true,
                      minScale: 1.0,
                      maxScale: 4.0,
                      child: Image.network(
                        imageUrl,
                        fit: BoxFit.contain,
                        // ✅ تحسين أداء الصور
                        cacheWidth: 800,
                        loadingBuilder: (context, child, progress) =>
                            progress == null
                                ? child
                                : Center(
                                    child: CircularProgressIndicator(
                                      value: progress.expectedTotalBytes != null
                                          ? progress.cumulativeBytesLoaded /
                                              progress.expectedTotalBytes!
                                          : null,
                                    ),
                                  ),
                        errorBuilder: (context, error, stackTrace) =>
                            _buildImageError(),
                      ),
                    )
                  : _buildImageError(message: 'No image for this question'),
            ),
          ),
          const SizedBox(height: 20),

          // ✅ مربعات الإجابات مع feedback بصري
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: options.map((option) {
              return _buildAnswerChoice(question, option);
            }).toList(),
          ),
          const SizedBox(height: 16),

          // ✅ زر كشف الإجابة — يختفي لو أجاب
          if (!hasAnswered)
            Center(
              child: TextButton.icon(
                onPressed:
                    answerIsRevealed ? null : () => _revealAnswer(questionId),
                icon: Icon(
                  answerIsRevealed
                      ? Icons.lightbulb
                      : Icons.lightbulb_outline,
                ),
                label: Text(
                    answerIsRevealed ? 'Revealed' : 'Reveal Answer'),
              ),
            )
          else
            // ✅ رسالة بعد الإجابة
            Center(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: _isCorrect[questionId] == true
                      ? Colors.green.shade50
                      : Colors.red.shade50,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  _isCorrect[questionId] == true
                      ? '✅ Correct!'
                      : '❌ Wrong!',
                  style: TextStyle(
                    color: _isCorrect[questionId] == true
                        ? Colors.green.shade700
                        : Colors.red.shade700,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          const SizedBox(height: 10),
        ],
      ),
    );
  }

  Widget _buildAnswerChoice(Map<String, dynamic> question, String option) {
    final questionId = question['id'].toString();
    final correctAnswer = question['correct_answer'] as String;
    final selectedAnswer = _selectedAnswers[questionId];
    final answerIsRevealed = _isRevealed[questionId] ?? false;
    final hasAnswered = selectedAnswer != null;

    Color borderColor = Colors.grey.shade400;
    Color backgroundColor = Colors.white;
    Color textColor = Colors.black87;

    if (hasAnswered) {
      if (selectedAnswer == option) {
        borderColor =
            _isCorrect[questionId] == true ? Colors.green : Colors.red;
        backgroundColor = _isCorrect[questionId] == true
            ? Colors.green.shade50
            : Colors.red.shade50;
        textColor =
            _isCorrect[questionId] == true ? Colors.green.shade700 : Colors.red.shade700;
      } else if (option.toUpperCase() == correctAnswer.toUpperCase()) {
        borderColor = Colors.green;
        backgroundColor = Colors.green.shade50;
        textColor = Colors.green.shade700;
      }
    }

    if (answerIsRevealed && option.toUpperCase() == correctAnswer.toUpperCase()) {
      borderColor = Colors.orange;
      backgroundColor = Colors.orange.shade50;
      textColor = Colors.orange.shade700;
    }

    return GestureDetector(
      onTap: hasAnswered ? null : () => _submitAnswer(questionId, option, question),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        width: 65,
        height: 65,
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: borderColor, width: 2.5),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 5,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Center(
          child: Text(
            option,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: textColor,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildImageError({String? message}) {
    return Container(
      color: Colors.grey[200],
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, color: Colors.red, size: 50),
          const SizedBox(height: 8),
          Text(
            message ?? 'Failed to load image',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}
