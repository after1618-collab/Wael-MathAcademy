import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:async';

class SectionQuestionsScreen extends StatefulWidget {
  final String sectionId;
  final String sectionName;

  const SectionQuestionsScreen({
    super.key,
    required this.sectionId,
    required this.sectionName,
  });

  @override
  State<SectionQuestionsScreen> createState() => _SectionQuestionsScreenState();
}

class _SectionQuestionsScreenState extends State<SectionQuestionsScreen> {
  final supabase = Supabase.instance.client;
  late final Future<List<Map<String, dynamic>>> _questionsFuture;
  int _currentIndex = 0;
  String? _selectedAnswer;
  final _answerController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _questionsFuture = _fetchQuestions();
  }

  Future<List<Map<String, dynamic>>> _fetchQuestions() async {
    try {
      final data = await supabase
          .from('questions')
          .select()
          .eq("section_id", widget.sectionId)
          .order("created_at");
      return List<Map<String, dynamic>>.from(data);
    } on PostgrestException catch (e) {
      throw Exception('Failed to load questions: ${e.message}');
    }
  }

  Future<void> _submitAndNext(
    String answer,
    String questionId,
    int totalQuestions,
  ) async {
    // Show a loading indicator to the user
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('Submitting answer...')));

    try {
      // Use the modern Supabase client syntax which throws an exception on error
      await supabase.rpc(
        // This is the correct modern syntax
        "add_attempt",
        params: {
          "p_student_id": supabase.auth.currentUser?.id,
          "p_question_id": questionId,
          "p_submitted_answer": answer,
          "p_revealed": false,
        },
      );
    } on PostgrestException catch (e) {
      // If an error occurs, show it to the user and stop execution
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text('❌ Submission Error: ${e.message}'),
            backgroundColor: Colors.redAccent,
          ),
        );
      return; // Stop if submission fails
    }

    // If submission is successful, hide the loading indicator
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();

    // Move to the next question or finish the quiz
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

  void _showFinishDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: const Text("Finished 🎉"),
        content: const Text(
            "You have answered all questions in this section. Well done!"),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop(); // Close dialog
              Navigator.of(context).pop(); // Go back from quiz screen
            },
            child: const Text("Back to Sections"),
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
      appBar: AppBar(title: Text(widget.sectionName)),
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
            return const Center(
                child: Text("There are no questions in this section yet."));
          }

          final question = questions[_currentIndex];
          final answerType = question['answer_type'] ?? 'mcq';

          return Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  "Question ${_currentIndex + 1} of ${questions.length}",
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 16),
                Expanded(flex: 3, child: _buildQuestionContent(question)),
                const SizedBox(height: 20),
                Expanded(flex: 2, child: _buildAnswerWidget(question)),
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
                        const SnackBar(content: Text("Please enter an answer")),
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
                        ? "Submit and Next"
                        : "Finish",
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildQuestionContent(Map<String, dynamic> question) {
    final imageUrl = question['image_path'] != null
        ? supabase.storage
            .from('questions')
            .getPublicUrl(question['image_path'])
        : null;

    return SingleChildScrollView(
      child: Column(
        children: [
          if (imageUrl != null)
            Image.network(
              imageUrl,
              fit: BoxFit.contain,
              height: 200,
              loadingBuilder: (context, child, progress) =>
                  progress == null ? child : const CircularProgressIndicator(),
              errorBuilder: (context, error, stack) =>
                  const Icon(Icons.error, size: 50),
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
    );
  }

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
            labelText: "Enter a numeric answer",
            border: OutlineInputBorder(),
          ),
        );
      case 'text':
      default:
        return TextField(
          controller: _answerController,
          decoration: const InputDecoration(
            labelText: "Type your answer here",
            border: OutlineInputBorder(),
          ),
        );
    }
  }
}
