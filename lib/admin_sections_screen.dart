import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AdminSectionsScreen extends StatefulWidget {
  const AdminSectionsScreen({super.key});

  @override
  State<AdminSectionsScreen> createState() => _AdminSectionsScreenState();
}

class _AdminSectionsScreenState extends State<AdminSectionsScreen> {
  final _supabase = Supabase.instance.client;
  late Future<List<Map<String, dynamic>>> _sectionsFuture;

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
      _showError('فشل في جلب الأقسام: ${error.message}');
      return []; // Return empty list on error
    }
  }

  void _refreshSections() {
    setState(() {
      _sectionsFuture = _fetchSections();
    });
  }

  Future<void> _addOrEditSection({Map<String, dynamic>? section}) async {
    final formKey = GlobalKey<FormState>();
    final nameController = TextEditingController(text: section?['name'] ?? "");
    final descController = TextEditingController(
      text: section?['description'] ?? "",
    );
    // Use ValueNotifier to update the image preview inside the dialog
    final imageNotifier = ValueNotifier<String?>(section?['image_url']);
    bool isSaving = false;

    await showDialog(
      context: context,
      barrierDismissible: !isSaving,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(section == null ? "إضافة قسم جديد" : "تعديل القسم"),
              content: SingleChildScrollView(
                child: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ValueListenableBuilder<String?>(
                        valueListenable: imageNotifier,
                        builder: (context, currentImageUrl, child) {
                          return GestureDetector(
                            onTap: () async {
                              final picker = ImagePicker();
                              final pickedFile = await picker.pickImage(
                                source: ImageSource.gallery,
                                imageQuality: 80,
                              );
                              if (pickedFile == null) return;

                              setDialogState(() => isSaving = true);
                              try {
                                final file = File(pickedFile.path);
                                final fileName =
                                    "${DateTime.now().millisecondsSinceEpoch}_${pickedFile.name}";

                                await _supabase.storage
                                    .from('sections_images')
                                    .upload(fileName, file);

                                imageNotifier.value = _supabase.storage
                                    .from('sections_images')
                                    .getPublicUrl(fileName);
                              } on StorageException catch (error) {
                                _showError(
                                  'خطأ في رفع الصورة: ${error.message}',
                                );
                              } finally {
                                setDialogState(() => isSaving = false);
                              }
                            },
                            child: Container(
                              height: 120,
                              width: double.infinity,
                              clipBehavior: Clip.antiAlias,
                              decoration: BoxDecoration(
                                color: Colors.grey[200],
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: currentImageUrl != null
                                  ? Image.network(
                                      currentImageUrl,
                                      fit: BoxFit.cover,
                                    )
                                  : const Center(
                                      child: Icon(
                                        Icons.add_a_photo,
                                        size: 40,
                                        color: Colors.grey,
                                      ),
                                    ),
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: nameController,
                        decoration: const InputDecoration(
                          labelText: "اسم القسم",
                        ),
                        validator: (value) => (value == null || value.isEmpty)
                            ? 'اسم القسم مطلوب'
                            : null,
                      ),
                      TextFormField(
                        controller: descController,
                        decoration: const InputDecoration(labelText: "الوصف"),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSaving ? null : () => Navigator.pop(context),
                  child: const Text("إلغاء"),
                ),
                ElevatedButton(
                  onPressed: isSaving
                      ? null
                      : () async {
                          if (formKey.currentState!.validate()) {
                            setDialogState(() => isSaving = true);
                            try {
                              final upsertData = {
                                'name': nameController.text.trim(),
                                'description': descController.text.trim(),
                                'image_url': imageNotifier.value,
                              };
                              if (section == null) {
                                await _supabase
                                    .from('sections')
                                    .insert(upsertData);
                              } else {
                                await _supabase
                                    .from('sections')
                                    .update(upsertData)
                                    .eq('id', section['id']);
                              }
                              if (mounted) Navigator.pop(context);
                              _refreshSections();
                            } on PostgrestException catch (error) {
                              _showError('فشل الحفظ: ${error.message}');
                              setDialogState(() => isSaving = false);
                            }
                          }
                        },
                  child: isSaving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text("حفظ"),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _deleteSection(String id, String? imageUrl) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("⚠️ تأكيد الحذف"),
        content: const Text(
          "هل أنت متأكد من حذف هذا القسم؟ سيتم حذف الصورة المرتبطة به أيضاً.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("إلغاء"),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text("حذف", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await _supabase.from('sections').delete().eq('id', id);
        if (imageUrl != null) {
          final fileName = Uri.parse(imageUrl).pathSegments.last;
          await _supabase.storage.from('sections_images').remove([fileName]);
        }
        _refreshSections();
      } on PostgrestException catch (error) {
        _showError('فشل حذف القسم: ${error.message}');
      } on StorageException catch (error) {
        _showError('فشل حذف الصورة: ${error.message}');
      }
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.redAccent),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("إدارة الأقسام"),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_circle_outline),
            tooltip: "إضافة قسم جديد",
            onPressed: () => _addOrEditSection(),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: "تحديث",
            onPressed: _refreshSections,
          ),
        ],
      ),
      drawer: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            const DrawerHeader(
              decoration: BoxDecoration(color: Colors.indigo),
              child: Text(
                'لوحة تحكم المدير',
                style: TextStyle(color: Colors.white, fontSize: 24),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.category),
              title: const Text('إدارة الأقسام'),
              onTap: () => Navigator.pop(context), // Already on this screen
            ),
            ListTile(
              leading: const Icon(Icons.people),
              title: const Text('إدارة الطلاب'),
              onTap: () {
                Navigator.pop(context); // Close drawer
                Navigator.pushNamed(context, '/admin_students');
              },
            ),
            // TODO: Add route for reports in main.dart if it doesn't exist
            // ListTile(
            //   leading: const Icon(Icons.bar_chart),
            //   title: const Text('التقارير'),
            //   onTap: () {
            //     Navigator.pop(context);
            //     Navigator.pushNamed(context, '/reports');
            //   },
            // ),
          ],
        ),
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _sectionsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('خطأ: ${snapshot.error}'));
          }
          final sections = snapshot.data!;
          if (sections.isEmpty) {
            return const Center(
              child: Text('لا توجد أقسام. قم بإضافة قسم جديد.'),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(8),
            itemCount: sections.length,
            itemBuilder: (context, index) {
              final section = sections[index];
              return Card(
                margin: const EdgeInsets.symmetric(vertical: 6),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundImage: section['image_url'] != null
                        ? NetworkImage(section['image_url'])
                        : null,
                    child: section['image_url'] == null
                        ? const Icon(Icons.category)
                        : null,
                  ),
                  title: Text(section['name'] ?? 'بلا اسم'),
                  subtitle: Text(section['description'] ?? 'بلا وصف'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit, color: Colors.blue),
                        onPressed: () => _addOrEditSection(section: section),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        onPressed: () =>
                            _deleteSection(section['id'], section['image_url']),
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
