import 'package:flutter/material.dart';
import 'package:wael_mcp/api_service.dart';

class StudentsScreen extends StatefulWidget {
  const StudentsScreen({super.key});

  @override
  State<StudentsScreen> createState() => _StudentsScreenState();
}

class _StudentsScreenState extends State<StudentsScreen> {
  late Future<List<Map<String, dynamic>>> _studentsFuture;

  @override
  void initState() {
    super.initState();
    _studentsFuture = _fetchStudents();
  }

  Future<List<Map<String, dynamic>>> _fetchStudents() async {
    try {
      // ✅ استخدام ApiService
      return await ApiService.getAllStudents();
    } on ApiException catch (error) {
      throw Exception('Failed to fetch students: ${error.message}');
    } catch (error) {
      throw Exception('An unexpected error occurred: $error');
    }
  }

  Future<void> _addStudent(String name, String email, String className) async {
    try {
      await ApiService.addStudent(
        fullName: name,
        email: email,
        className: className,
      );
      setState(() => _studentsFuture = _fetchStudents());
    } on ApiException catch (error) {
      _showError(error.message);
    } catch (error) {
      _showError('An unexpected error occurred.');
      setState(() => _studentsFuture = _fetchStudents());
    }
  }

  Future<void> _updateStudent(
    String id,
    String? name,
    String? email,
    String? className,
  ) async {
    try {
      await ApiService.updateStudent(
        id: id,
        fullName: name,
        email: email,
        className: className,
      );
      setState(() => _studentsFuture = _fetchStudents());
    } on ApiException catch (error) {
      _showError(error.message);
    } catch (error) {
      _showError('An unexpected error occurred.');
    }
  }

  Future<void> _deleteStudent(String id) async {
    try {
      await ApiService.deleteStudent(id);
      setState(() => _studentsFuture = _fetchStudents());
    } on ApiException catch (error) {
      _showError(error.message);
    } catch (error) {
      _showError('An unexpected error occurred.');
    }
  }

  Future<void> _toggleActivation(String id) async {
    try {
      await ApiService.toggleStudentActivation(id);
      setState(() => _studentsFuture = _fetchStudents());
    } on ApiException catch (error) {
      _showError(error.message);
    } catch (error) {
      _showError('An unexpected error occurred.');
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("❌ خطأ: $message"), backgroundColor: Colors.red),
    );
  }

  void _showAddDialog() {
    final nameController = TextEditingController();
    final emailController = TextEditingController();
    final classController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (context) {
        bool isDialogLoading = false;
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text("➕ إضافة طالب جديد"),
              content: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      controller: nameController,
                      decoration: const InputDecoration(
                        labelText: "الاسم الكامل",
                      ),
                      validator: (value) => (value == null || value.isEmpty)
                          ? 'الاسم مطلوب'
                          : null,
                    ),
                    TextFormField(
                      controller: emailController,
                      decoration: const InputDecoration(labelText: "الإيميل"),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'الإيميل مطلوب';
                        }
                        if (!RegExp(r'^[^@]+@[^@]+\.[^@]+').hasMatch(value)) {
                          return 'صيغة الإيميل غير صحيحة';
                        }
                        return null;
                      },
                    ),
                    TextFormField(
                      controller: classController,
                      decoration: const InputDecoration(
                        labelText: "الفصل/الصف",
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text("إلغاء"),
                ),
                ElevatedButton(
                  onPressed: isDialogLoading
                      ? null
                      : () async {
                          if (formKey.currentState!.validate()) {
                            setDialogState(() => isDialogLoading = true);
                            await _addStudent(
                              nameController.text.trim(),
                              emailController.text.trim(),
                              classController.text.trim(),
                            );
                            if (mounted) Navigator.pop(context);
                          }
                        },
                  child: isDialogLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text("إضافة"),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showEditDialog(Map<String, dynamic> student) {
    final nameController = TextEditingController(text: student['full_name']);
    final emailController = TextEditingController(text: student['email']);
    final classController = TextEditingController(text: student['class_name']);
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (context) {
        bool isDialogLoading = false;
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text("✏️ تعديل بيانات الطالب"),
              content: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      controller: nameController,
                      decoration: const InputDecoration(
                        labelText: "الاسم الكامل",
                      ),
                      validator: (value) => (value == null || value.isEmpty)
                          ? 'الاسم مطلوب'
                          : null,
                    ),
                    TextFormField(
                      controller: emailController,
                      decoration: const InputDecoration(labelText: "الإيميل"),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'الإيميل مطلوب';
                        }
                        if (!RegExp(r'^[^@]+@[^@]+\.[^@]+').hasMatch(value)) {
                          return 'صيغة الإيميل غير صحيحة';
                        }
                        return null;
                      },
                    ),
                    TextFormField(
                      controller: classController,
                      decoration: const InputDecoration(
                        labelText: "الفصل/الصف",
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text("إلغاء"),
                ),
                ElevatedButton(
                  onPressed: isDialogLoading
                      ? null
                      : () async {
                          if (formKey.currentState!.validate()) {
                            setDialogState(() => isDialogLoading = true);
                            await _updateStudent(
                              student['id'],
                              nameController.text.trim(),
                              emailController.text.trim(),
                              classController.text.trim(),
                            );
                            if (mounted) Navigator.pop(context);
                          }
                        },
                  child: isDialogLoading
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

  void _showDeleteConfirm(String id) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("⚠️ تأكيد الحذف"),
        content: const Text("هل أنت متأكد أنك تريد حذف هذا الطالب؟"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("إلغاء"),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              _deleteStudent(id);
              Navigator.pop(context);
            },
            child: const Text("حذف"),
          ),
        ],
      ),
    );
  }

  Widget _buildStudentCard(Map<String, dynamic> student) {
    final bool isActive = student['activated'] ?? student['is_active'] ?? false;
    return Card(
      elevation: 3,
      margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Colors.blueAccent,
          child: student['full_name'].isEmpty
              ? const Icon(Icons.person, color: Colors.white)
              : Text(
                  student['full_name'][0].toUpperCase(),
                  style: const TextStyle(color: Colors.white),
                ),
        ),
        title: Text(
          student['full_name'],
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(
          "${student['email']} • ${student['class_name'] ?? 'غير محدد'}",
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: Icon(
                isActive ? Icons.toggle_on : Icons.toggle_off,
                color: isActive ? Colors.green : Colors.grey,
                size: 30,
              ),
              onPressed: () => _toggleActivation(student['id']),
              tooltip: isActive ? 'إلغاء التفعيل' : 'تفعيل',
            ),
            IconButton(
              icon: const Icon(Icons.edit, color: Colors.blue),
              onPressed: () => _showEditDialog(student),
            ),
            IconButton(
              icon: const Icon(Icons.delete, color: Colors.red),
              onPressed: () => _showDeleteConfirm(student['id']),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.people_alt_outlined),
            SizedBox(width: 8),
            Text("إدارة الطلاب"),
          ],
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => setState(() => _studentsFuture = _fetchStudents()),
          ),
        ],
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _studentsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text("❌ خطأ: ${snapshot.error}"));
          }
          final students = snapshot.data ?? [];
          if (students.isEmpty) {
            return const Center(child: Text("لا يوجد طلاب بعد."));
          }
          return ListView.builder(
            itemCount: students.length,
            itemBuilder: (context, index) => _buildStudentCard(students[index]),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddDialog,
        child: const Icon(Icons.add),
      ),
    );
  }
}
