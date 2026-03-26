import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class StudentSectionsScreen extends StatefulWidget {
  const StudentSectionsScreen({super.key});

  @override
  State<StudentSectionsScreen> createState() => _StudentSectionsScreenState();
}

class _StudentSectionsScreenState extends State<StudentSectionsScreen> {
  final _supabase = Supabase.instance.client;
  late final Future<List<Map<String, dynamic>>> _sectionsFuture;

  @override
  void initState() {
    super.initState();
    _sectionsFuture = _fetchSections();
  }

  Future<List<Map<String, dynamic>>> _fetchSections() async {
    try {
      final data = await _supabase
          .from('sections')
          .select()
          .order('created_at');
      return List<Map<String, dynamic>>.from(data);
    } on PostgrestException catch (error) {
      debugPrint(error.message);
      throw Exception('Failed to load sections: ${error.message}');
    }
  }

  void _openSection(Map<String, dynamic> section) {
    Navigator.pushNamed(
      context,
      '/quiz',
      arguments: {'sectionId': section['id']},
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Choose a Section")),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _sectionsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          final sections = snapshot.data!;
          if (sections.isEmpty) {
            return const Center(child: Text('No sections available.'));
          }

          return GridView.builder(
            padding: const EdgeInsets.all(10),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
              childAspectRatio: 0.9,
            ),
            itemCount: sections.length,
            itemBuilder: (context, index) {
              final section = sections[index];
              return Card(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () => _openSection(section),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Image.network(
                        section['image_url'] ?? '',
                        height: 100,
                        width: double.infinity,
                        fit: BoxFit.cover,
                        loadingBuilder: (context, child, progress) =>
                            progress == null
                                ? child
                                : const Center(child: CircularProgressIndicator()),
                        errorBuilder: (context, error, stackTrace) => Container(
                          height: 100,
                          color: Colors.grey[300],
                          child: const Icon(Icons.photo, size: 40, color: Colors.grey),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              section['name'] ?? 'Unnamed',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (section['description'] != null &&
                                section['description'].isNotEmpty)
                              Text(
                                section['description'],
                                style: const TextStyle(color: Colors.grey, fontSize: 12),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                          ],
                        ),
                      ),
                    ],
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
