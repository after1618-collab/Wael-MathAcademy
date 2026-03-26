import 'package:flutter/material.dart';

class QuestionsScreen extends StatelessWidget {
  final Map<String, dynamic> section;
  const QuestionsScreen({super.key, required this.section});

  @override
  Widget build(BuildContext context) {
    // TODO: Fetch and display questions for the given section
    return Scaffold(
      appBar: AppBar(title: Text(section['name'])),
      body: Center(
        child: Text("الأسئلة الخاصة بقسم '${section['name']}' ستظهر هنا"),
      ),
    );
  }
}
