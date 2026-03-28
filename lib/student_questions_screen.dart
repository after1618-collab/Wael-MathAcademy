import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wael_mcp/api_service.dart';
import 'dart:html' as html;
import 'dart:js' as js;
import 'dart:async';

class StudentQuestionsScreen extends StatefulWidget {
  final Map<String, dynamic> section;

  const StudentQuestionsScreen({super.key, required this.section});

  @override
  State<StudentQuestionsScreen> createState() => _StudentQuestionsScreenState();
}

class _StudentQuestionsScreenState extends State<StudentQuestionsScreen> {
  final _supabase = Supabase.instance.client;
  late final Future<List<Map<String, dynamic>>> _questionsFuture;
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    _questionsFuture = _fetchQuestions();
  }

  Future<void> _fetchQuestions() async {
    try {
      final data = await _supabase
          .from('questions')
          .select()
          .eq('section_id', widget.section['id'])
          .order('created_at');
      return List<Map<String, dynamic>>.from(data);
    } on PostgrestException catch (e) {
      throw Exception('Failed to load questions: ${e.message}');
    }
  }

  void _submitAnswer(
    String answer,
    String questionId,
    List<dynamic> questions,
  ) async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Submitting answer...'),
        duration: Duration(seconds: 1),
      ),
    );

    await _supabase.rpc("add_attempt", {
      "p_student_id": _supabase.auth.currentUser?.id,
      "p_question_id": questionId,
      "p_submitted_answer": answer,
      "p_revealed": false,
    });

    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();

    if (_currentIndex < questions.length - 1) {
      setState(() {
        _currentIndex++;
      });
    } else {
      _showFinishDialog();
    }
  }

  void _showFinishDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: const Text("Finished! 🎉"),
        content: const Text("You have answered all questions in this section. Well done!"),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              Navigator.of(context).pop();
            },
            child: const Text("Back to Sections"),
          ),
        ],
      ),
    );
  }

  void _skipQuestion(int totalQuestions) {
    if (_currentIndex < totalQuestions - 1) {
      setState(() => _currentIndex++);
    } else {
      _showFinishDialog();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.section['name'])),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _questionsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          final questions = snapshot.data!;
          if (questions.isEmpty) {
            return const Center(child: Text("No questions in this section yet."));
          }

          final question = questions[_currentIndex];

          if (question['image_path'] == null) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text(
                      '❌ Question Data Error',
                      style: TextStyle(fontSize: 20, color: Colors.red),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Current question (ID: ${question['id']}) has no image.',
                    ),
                    const SizedBox(height: 20),
                    ElevatedButton(
                      onPressed: () => _skipQuestion(questions.length),
                      child: const Text('Skip this question'),
                    ),
                  ],
                ),
              ),
            );
          }

          return QuestionScreen(
            key: ValueKey(question['id']),
            questionImage: question['image_path'],
            answerType: question['answer_type'] ?? 'mcq',
            allowE: question['allow_e'] ?? false,
            revealImage: question['reveal_image'],
            onSubmit: (answer) =>
                _submitAnswer(answer, question['id'], questions),
          );
        },
      ),
    );
  }
}

class QuestionScreen extends StatefulWidget {
  final String questionImage;
  final String answerType;
  final bool allowE;
  final String? revealImage;
  final Function(String) onSubmit;

  const QuestionScreen({
    super.key,
    required this.questionImage,
    required this.answerType,
    this.allowE = false,
    this.revealImage,
    required this.onSubmit,
  });

  @override
  State<QuestionScreen> createState() => _QuestionScreenState();
}

class _QuestionScreenState extends State<QuestionScreen>
    with WidgetsBindingObserver {
  String? selectedAnswer;
  final TextEditingController _controller = TextEditingController();
  
  String _studentName = 'طالب';
  String _studentEmail = '';

  // 🛡️ Protection variables
  final List<StreamSubscription> _subscriptions = [];
  html.StyleElement? _protectionStyle;
  Timer? _devToolsTimer;
  bool _devToolsDetected = false;

  List<String> getOptions() {
    final baseOptions = ["A", "B", "C", "D"];
    if (widget.allowE) baseOptions.add("E");
    return baseOptions;
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

    return Transform.rotate(
      angle: angle,
      child: Text(
        text,
        style: TextStyle(
          color: Colors.black.withOpacity(0.19), // ✅ اللون الأسود
          fontSize: 12,
          fontWeight: FontWeight.bold,
          fontFamily: 'monospace',
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _injectGlobalProtectionCSS();
    _enableAllProtections();
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

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _removeAllProtections();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final studentInfo =
        "$_studentName • $_studentEmail • ${DateTime.now().toString().split(' ')[0]}";

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
      backgroundColor: Colors.grey[100],
      body: SafeArea(
        child: Stack(
          children: [
            // المحتوى الأصلي (يجب أن يكون الأول ليكون تحت العلامات المائية)
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  Expanded(
                    flex: 5,
                    child: Center(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: InteractiveViewer(
                          panEnabled: true,
                          minScale: 1.0,
                          maxScale: 4.0,
                          child: Image.network(
                            widget.questionImage,
                            fit: BoxFit.contain,
                            loadingBuilder: (context, child, progress) =>
                                progress == null
                                    ? child
                                    : const Center(
                                        child: CircularProgressIndicator()),
                            errorBuilder: (context, error, stack) =>
                                const Center(child: Icon(Icons.error)),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Expanded(flex: 3, child: _buildAnswerWidget()),
                  if (widget.revealImage != null) ...[
                    const SizedBox(height: 10),
                    GestureDetector(
                      onTap: () {
                        showDialog(
                          context: context,
                          builder: (_) =>
                              Dialog(child: Image.network(widget.revealImage!)),
                        );
                      },
                      child: const Text(
                        "🔷 Tap to show hint image",
                        style: TextStyle(
                          color: Colors.blue,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 40, vertical: 16),
                        backgroundColor: Colors.blueAccent,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: () {
                        if (widget.answerType == "mcq" &&
                            selectedAnswer == null) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text("Select an answer first")),
                          );
                          return;
                        }
                        if ((widget.answerType == "numeric" ||
                                widget.answerType == "text") &&
                            _controller.text.trim().isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text("Enter your answer first")),
                          );
                          return;
                        }
                        widget.onSubmit(
                          widget.answerType == "mcq"
                              ? selectedAnswer!
                              : _controller.text.trim(),
                        );
                      },
                      child: const Text(
                        "Submit Answer",
                        style: TextStyle(fontSize: 18, color: Colors.white),
                      ),
                    ),
                  ),
                ],
              ),
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
                      top: 40,
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
                      top: MediaQuery.of(context).size.height * 0.4,
                      left: 10,
                      child: _buildWatermarkText(studentInfo, -0.1),
                    ),
                    Positioned(
                      top: MediaQuery.of(context).size.height * 0.4,
                      right: 10,
                      child: _buildWatermarkText(studentInfo, 0.12),
                    ),
                    Positioned(
                      top: MediaQuery.of(context).size.height * 0.6,
                      left: 60,
                      child: _buildWatermarkText(studentInfo, 0.25),
                    ),
                    Positioned(
                      top: MediaQuery.of(context).size.height * 0.6,
                      right: 60,
                      child: _buildWatermarkText(studentInfo, -0.2),
                    ),
                    Positioned(
                      bottom: 80,
                      left: 40,
                      child: _buildWatermarkText(studentInfo, -0.2),
                    ),
                    Positioned(
                      bottom: 80,
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
        ),
      ),
    );
  }

  Widget _buildAnswerWidget() {
    switch (widget.answerType) {
      case "mcq":
        final options = getOptions();
        return ListView(
          children: options
              .map(
                (opt) => RadioListTile<String>(
                  title: Text(opt, style: const TextStyle(fontSize: 18)),
                  value: opt,
                  groupValue: selectedAnswer,
                  onChanged: (val) {
                    setState(() => selectedAnswer = val);
                  },
                ),
              )
              .toList(),
        );
      case "numeric":
        return TextField(
          controller: _controller,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: "Enter your answer (numeric)",
            border: OutlineInputBorder(),
          ),
        );
      case "text":
        return TextField(
          controller: _controller,
          decoration: const InputDecoration(
            labelText: "Enter your answer (text)",
            border: OutlineInputBorder(),
          ),
          maxLines: 3,
        );
      default:
        return const Center(child: Text("❌ Unsupported question type"));
    }
  }
}
