import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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

class _QuestionScreenState extends State<QuestionScreen> {
  String? selectedAnswer;
  final TextEditingController _controller = TextEditingController();

  List<String> getOptions() {
    final baseOptions = ["A", "B", "C", "D"];
    if (widget.allowE) baseOptions.add("E");
    return baseOptions;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              Expanded(
                flex: 5,
                child: Center(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Image.network(
                      widget.questionImage,
                      fit: BoxFit.contain,
                      loadingBuilder: (context, child, progress) =>
                          progress == null
                              ? child
                              : const Center(child: CircularProgressIndicator()),
                      errorBuilder: (context, error, stack) =>
                          const Center(child: Icon(Icons.error)),
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
                    padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 16),
                    backgroundColor: Colors.blueAccent,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: () {
                    if (widget.answerType == "mcq" && selectedAnswer == null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text("Select an answer first")),
                      );
                      return;
                    }
                    if ((widget.answerType == "numeric" ||
                            widget.answerType == "text") &&
                        _controller.text.trim().isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text("Enter your answer first")),
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