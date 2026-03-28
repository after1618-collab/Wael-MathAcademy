import 'package:flutter/material.dart';
import 'package:wael_mcp/api_service.dart';

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

class _QuestionScreenState extends State<QuestionScreen> {
  late final Future<List<Map<String, dynamic>>> _questionsFuture;
  final PageController _pageController = PageController();
  final Map<String, String> _selectedAnswers = {};
  int _currentPage = 0;
  final Map<String, bool> _isCorrect = {};
  final Map<String, bool> _isRevealed = {};

  @override
  void initState() {
    super.initState();
    _pageController.addListener(() =>
        setState(() => _currentPage = _pageController.page?.round() ?? 0));
    _questionsFuture = ApiService.getQuestions(widget.sectionId);
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
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
          return Stack(
            children: [
              // العلامة المائية للوجو (شفافة ولا تعيق الضغط)
              Positioned.fill(
                child: IgnorePointer(
                  child: Opacity(
                    opacity: 0.15,
                    child: Center(
                      child: Image.asset(
                        'assets/logo.jpg',
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                ),
              ),
              // المحتوى الأصلي
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
