import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// A screen that displays a series of questions for a given section.
/// It fetches questions and manages the quiz state, such as the current question and user answers.
class QuizScreen extends StatefulWidget {
  final String sectionId; // القسم اللي الطالب اختاره

  const QuizScreen({super.key, required this.sectionId});

  @override
  State<QuizScreen> createState() => _QuizScreenState();
}

class _QuizScreenState extends State<QuizScreen> {
  final _supabase = Supabase.instance.client;
  late final Future<List<Map<String, dynamic>>> _questionsFuture;
  int _currentIndex = 0;
  String? _selectedAnswer;
  final TextEditingController _answerController = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Fetch questions once when the widget is initialized.
    _questionsFuture = _fetchQuestions();
  }

  /// Fetches questions for the current section from the database.
  Future<List<Map<String, dynamic>>> _fetchQuestions() async {
    try {
      final data = await _supabase
          .from("questions")
          .select() // Selects all columns
          .eq("section_id", widget.sectionId)
          .order("created_at");
      return List<Map<String, dynamic>>.from(data);
    } on PostgrestException catch (e) {
      // This error will be caught by the FutureBuilder.
      throw Exception('فشل في تحميل الأسئلة: ${e.message}');
    }
  }

  /// Submits the user's answer and moves to the next question or finishes the quiz.
  Future<void> _submitAndNext(
    String answer,
    String questionId,
    int totalQuestions,
  ) async {
    // Show a loading indicator while submitting.
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('جارِ إرسال الإجابة...')));

    try {
      await _supabase.rpc(
        "add_attempt",
        params: {
          "p_student_id": _supabase.auth.currentUser?.id,
          "p_question_id": questionId,
          "p_submitted_answer": answer,
          "p_revealed": false,
        },
      );
    } on PostgrestException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ خطأ في الإرسال: ${e.message}'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return; // Stop execution if submission fails.
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();

    // Move to the next question or show finish dialog.
    if (_currentIndex < totalQuestions - 1) {
      setState(() {
        _currentIndex++;
        _selectedAnswer = null;
        _answerController.clear();
      });
    } else {
      _showFinishDialog();
    }
  }

  /// Shows a dialog when the user has answered all questions.
  void _showFinishDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: const Text("انتهيت 🎉"),
        content: const Text("لقد أجبت على جميع الأسئلة في هذا القسم. أحسنت!"),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop(); // Close dialog
              Navigator.of(context).pop(); // Go back from quiz screen
            },
            child: const Text("العودة للأقسام"),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _answerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Quiz"), centerTitle: true),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _questionsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('خطأ: ${snapshot.error}'));
          }
          final questions = snapshot.data!;
          if (questions.isEmpty) {
            return const Center(child: Text("لا توجد أسئلة في هذا القسم بعد."));
          }

          final question = questions[_currentIndex];
          final answerType = question['answer_type'] ?? 'mcq';

          return Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Question Number
                Text(
                  "السؤال ${_currentIndex + 1} من ${questions.length}",
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),

                // Question Content (Image/Text)
                Expanded(
                  flex: 3,
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        if (question['image_path'] != null)
                          ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.network(
                              _supabase.storage
                                  .from("questions")
                                  .getPublicUrl(question['image_path']),
                              fit: BoxFit.contain,
                              loadingBuilder: (context, child, progress) =>
                                  progress == null
                                  ? child
                                  : const Center(
                                      child: CircularProgressIndicator(),
                                    ),
                              errorBuilder: (context, error, stack) =>
                                  const Icon(Icons.error, size: 50),
                            ),
                          ),
                        if (question['question_text'] != null)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            child: Text(
                              question['question_text'],
                              style: const TextStyle(fontSize: 20),
                              textAlign: TextAlign.center,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // Answer Widget
                Expanded(flex: 2, child: _buildAnswerWidget(question)),

                // Submit Button
                ElevatedButton(
                  onPressed: () {
                    String? answer;
                    if (answerType == 'mcq') {
                      answer = _selectedAnswer;
                    } else {
                      answer = _answerController.text.trim();
                    }

                    if (answer == null || answer.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text("الرجاء إدخال إجابة")),
                      );
                      return;
                    }

                    _submitAndNext(answer, question['id'], questions.length);
                  },
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    textStyle: const TextStyle(fontSize: 18),
                  ),
                  child: Text(
                    _currentIndex < questions.length - 1
                        ? "إرسال والتالي"
                        : "إنهاء",
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  /// Builds the appropriate input widget based on the question's answer type.
  Widget _buildAnswerWidget(Map<String, dynamic> question) {
    final answerType = question['answer_type'] ?? 'mcq';
    final options = (question['options'] as List?)?.cast<String>() ?? [];

    switch (answerType) {
      case 'mcq':
        return ListView(
          children: options.map((opt) {
            return RadioListTile<String>(
              title: Text(opt),
              value: opt,
              groupValue: _selectedAnswer,
              onChanged: (val) => setState(() => _selectedAnswer = val),
            );
          }).toList(),
        );
      case 'numeric':
        return TextField(
          controller: _answerController,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: "أدخل إجابة رقمية",
            border: OutlineInputBorder(),
          ),
        );
      case 'text':
        return TextField(
          controller: _answerController,
          decoration: const InputDecoration(
            labelText: "اكتب إجابتك هنا",
            border: OutlineInputBorder(),
          ),
        );
      default:
        return const Center(child: Text("نوع السؤال غير مدعوم"));
    }
  }
}
