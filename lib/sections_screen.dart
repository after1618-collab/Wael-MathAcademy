import 'package:flutter/material.dart';
import 'package:wael_mcp/api_service.dart';
import 'package:wael_mcp/question_screen.dart';

class SectionsScreen extends StatefulWidget {
  const SectionsScreen({super.key});

  @override
  State<SectionsScreen> createState() => _SectionsScreenState();
}

class _SectionsScreenState extends State<SectionsScreen> {
  late Future<List<Map<String, dynamic>>> _sectionsFuture;

  @override
  void initState() {
    super.initState();
    _sectionsFuture = ApiService.getSections();
  }

  // ✅ ألوان مختلفة لكل section
  static const _sectionColors = [
    Color(0xFF6A11CB),
    Color(0xFF2575FC),
    Color(0xFF00B4D8),
    Color(0xFF06D6A0),
    Color(0xFFFF6B6B),
    Color(0xFFFFA726),
  ];

  static const _sectionIcons = [
    Icons.calculate_outlined,
    Icons.functions_outlined,
    Icons.auto_graph_outlined,
    Icons.schema_outlined,
    Icons.science_outlined,
    Icons.lightbulb_outlined,
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('اختر القسم'),
        centerTitle: true,
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _sectionsFuture,
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
                        : 'حدث خطأ أثناء تحميل الأقسام',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 15),
                  ElevatedButton.icon(
                    onPressed: () {
                      setState(() {
                        _sectionsFuture = ApiService.getSections();
                      });
                    },
                    icon: const Icon(Icons.refresh),
                    label: const Text('إعادة المحاولة'),
                  ),
                ],
              ),
            );
          }
          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.folder_off_outlined, size: 60, color: Colors.grey),
                  SizedBox(height: 15),
                  Text('لا توجد أقسام متاحة حالياً',
                      style: TextStyle(fontSize: 16, color: Colors.grey)),
                ],
              ),
            );
          }

          final sections = snapshot.data!;
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: sections.length,
            itemBuilder: (context, index) {
              final section = sections[index];
              final color = _sectionColors[index % _sectionColors.length];
              final icon = _sectionIcons[index % _sectionIcons.length];

              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Material(
                  borderRadius: BorderRadius.circular(16),
                  elevation: 3,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () {
                      Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => QuestionScreen(
                          sectionId: section['id'],
                          sectionName: section['name'],
                        ),
                      ));
                    },
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        border: Border(right: BorderSide(color: color, width: 5)),
                      ),
                      child: Row(
                        children: [
                          // ✅ أيقونة ملونة
                          Container(
                            width: 50,
                            height: 50,
                            decoration: BoxDecoration(
                              color: color.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(icon, color: color, size: 28),
                          ),
                          const SizedBox(width: 15),
                          // ✅ النص
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  section['name'] ?? 'بدون اسم',
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                ),
                                if (section['description'] != null) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    section['description'],
                                    style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ],
                            ),
                          ),
                          Icon(Icons.arrow_forward_ios,
                              size: 18, color: Colors.grey.shade400),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
