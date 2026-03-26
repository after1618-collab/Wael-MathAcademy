import 'package:flutter/material.dart';
import 'package:wael_mcp/api_service.dart';

class WrongAnswersScreen extends StatefulWidget {
  const WrongAnswersScreen({super.key});

  @override
  State<WrongAnswersScreen> createState() => _WrongAnswersScreenState();
}

class _WrongAnswersScreenState extends State<WrongAnswersScreen> {
  late Future<Map<String, dynamic>> _wrongAnswersFuture;

  @override
  void initState() {
    super.initState();
    _wrongAnswersFuture = ApiService.getWrongAnswers();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Wrong Answers'),
        centerTitle: true,
      ),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _wrongAnswersFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Text(
                  'Error: ${snapshot.error}',
                  style: const TextStyle(color: Colors.red, fontSize: 16),
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          final data = snapshot.data!;
          final List wrongAnswers = data['wrong_answers'] ?? [];
          final int total = data['total'] ?? 0;

          if (wrongAnswers.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.check_circle_outline, size: 80, color: Colors.green),
                  SizedBox(height: 16),
                  Text(
                    'No wrong answers! 🎉',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'You answered all questions correctly.',
                    style: TextStyle(fontSize: 14, color: Colors.grey),
                  ),
                ],
              ),
            );
          }

          return Column(
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                color: Colors.red.shade50,
                child: Text(
                  'Total wrong answers: $total',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.red.shade700,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: wrongAnswers.length,
                  itemBuilder: (context, index) {
                    final item = wrongAnswers[index];
                    return _buildWrongAnswerCard(item, index + 1);
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildWrongAnswerCard(Map<String, dynamic> item, int number) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor: Colors.red.shade100,
                  child: Text(
                    '$number',
                    style: TextStyle(
                      color: Colors.red.shade700,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    item['section_name'] ?? 'Unknown Section',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Colors.grey,
                    ),
                  ),
                ),
              ],
            ),

            // Question image
            if (item['image_url'] != null) ...[
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.network(
                  item['image_url'],
                  height: 150,
                  width: double.infinity,
                  fit: BoxFit.contain,
                  loadingBuilder: (context, child, progress) =>
                      progress == null
                          ? child
                          : const SizedBox(
                              height: 150,
                              child: Center(child: CircularProgressIndicator()),
                            ),
                  errorBuilder: (context, error, stack) => Container(
                    height: 100,
                    color: Colors.grey.shade200,
                    child: const Center(child: Icon(Icons.broken_image, size: 40)),
                  ),
                ),
              ),
            ],

            // Question text
            if (item['question_text'] != null && item['question_text'].isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                item['question_text'],
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
              ),
            ],

            const SizedBox(height: 12),
            const Divider(),

            // Your Answer
            Row(
              children: [
                const Icon(Icons.close, color: Colors.red, size: 20),
                const SizedBox(width: 8),
                const Text('Your answer: ', style: TextStyle(color: Colors.grey)),
                Expanded(
                  child: Text(
                    item['student_answer'] ?? '-',
                    style: const TextStyle(
                      color: Colors.red,
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Correct Answer
            Row(
              children: [
                const Icon(Icons.check, color: Colors.green, size: 20),
                const SizedBox(width: 8),
                const Text('Correct answer: ', style: TextStyle(color: Colors.grey)),
                Expanded(
                  child: Text(
                    item['correct_answer'] ?? '-',
                    style: const TextStyle(
                      color: Colors.green,
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
