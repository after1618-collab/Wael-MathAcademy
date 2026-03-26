import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  final supabase = Supabase.instance.client;
  bool loading = true;
  List<Map<String, dynamic>> students = [];
  List<Map<String, dynamic>> questions = [];
  List<Map<String, dynamic>> sections = [];
  Map<String, dynamic>? global;

  @override
  void initState() {
    super.initState();
    fetchReports();
  }

  Future<void> fetchReports() async {
    setState(() => loading = true);

    try {
      final st = await supabase.rpc("get_student_report").select();
      final qs = await supabase.rpc("get_question_report").select();
      final sc = await supabase.rpc("get_section_report").select();
      final gl = await supabase.rpc("get_global_report").select();

      setState(() {
        students = List<Map<String, dynamic>>.from(st);
        questions = List<Map<String, dynamic>>.from(qs);
        sections = List<Map<String, dynamic>>.from(sc);
        global = gl.isNotEmpty ? Map<String, dynamic>.from(gl.first) : null;
        loading = false;
      });
    } catch (e) {
      debugPrint("Error fetching reports: $e");
      setState(() => loading = false);
    }
  }

  Widget buildCard(String title, Widget child) {
    return Card(
      margin: const EdgeInsets.all(12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Reports Dashboard")),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                if (global != null)
                  buildCard(
                    "🌍 Global",
                    Text(
                      "Total Attempts: ${global!['total_attempts']}, Correct %: ${global!['overall_correct_percentage']}",
                    ),
                  ),
                buildCard(
                  "👨‍🎓 Students",
                  Column(
                    children: students
                        .map(
                          (s) => ListTile(
                            title: Text(s['full_name'] ?? "Unknown"),
                            subtitle: Text(
                              "Correct: ${s['correct_attempts']} / ${s['total_attempts']}",
                            ),
                            trailing: Text("${s['correct_percentage']}%"),
                          ),
                        )
                        .toList(),
                  ),
                ),
                buildCard(
                  "❓ Questions",
                  Column(
                    children: questions
                        .map(
                          (q) => ListTile(
                            title: Text("QID: ${q['question_id']}"),
                            subtitle: Text("Attempts: ${q['total_attempts']}"),
                            trailing: Text("${q['correct_percentage']}%"),
                          ),
                        )
                        .toList(),
                  ),
                ),
                buildCard(
                  "📂 Sections",
                  Column(
                    children: sections
                        .map(
                          (s) => ListTile(
                            title: Text(s['section_name']),
                            subtitle: Text("Attempts: ${s['total_attempts']}"),
                            trailing: Text("${s['correct_percentage']}%"),
                          ),
                        )
                        .toList(),
                  ),
                ),
              ],
            ),
    );
  }
}
