import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:wael_mcp/session_manager.dart';
import 'package:wael_mcp/api_service.dart';

class VideoService {
  // ✅ Use the centralized baseUrl from ApiService
  static String get baseUrl => ApiService.baseUrl;

  static Future<Map<String, String>> _headers() async {
    final token = SessionManager().token;
    return {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };
  }

  // ========== Student APIs ==========

  static Future<List<Map<String, dynamic>>> getCourses() async {
    final response = await http.get(
      Uri.parse('$baseUrl/courses'),
      headers: await _headers(),
    );
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      return List<Map<String, dynamic>>.from(data['courses']);
    }
    if (response.statusCode == 401) {
      // ✅ Fixed: use named parameter {code:}
      throw ApiException('Session expired', code: 401);
    }
    throw Exception('Failed to load courses: ${response.statusCode}');
  }

  static Future<List<Map<String, dynamic>>> getCourseLessons(
      String courseId) async {
    final response = await http.get(
      Uri.parse('$baseUrl/courses/$courseId/lessons'),
      headers: await _headers(),
    );
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      return List<Map<String, dynamic>>.from(data['lessons']);
    }
    if (response.statusCode == 401) {
      // ✅ Fixed: use named parameter {code:}
      throw ApiException('Session expired', code: 401);
    }
    throw Exception('Failed to load lessons: ${response.statusCode}');
  }

  /// Request protected video access (checks watch limit)
  static Future<Map<String, dynamic>> requestVideoAccess(
      String lessonId) async {
    final response = await http.post(
      Uri.parse('$baseUrl/video/request-access'),
      headers: await _headers(),
      body: json.encode({
        'lesson_id': lessonId,
        'check_only': true,
      }),
    );

    if (response.statusCode == 200) {
      return json.decode(response.body);
    }
    if (response.statusCode == 403) {
      final data = json.decode(response.body);
      throw Exception(data['detail'] ?? 'Access denied');
    }
    if (response.statusCode == 401) {
      throw ApiException('Session expired', code: 401);
    }
    throw Exception('Failed to request access: ${response.statusCode}');
  }

  /// Record a watch — called ONLY when student reaches 70%
  static Future<void> recordWatch(String lessonId) async {
    final response = await http.post(
      Uri.parse('$baseUrl/video/record-watch'),
      headers: await _headers(),
      body: json.encode({'lesson_id': lessonId}),
    );

    if (response.statusCode == 200) return;
    if (response.statusCode == 401)
      throw ApiException('Session expired', code: 401);
    throw Exception('Failed to record watch: ${response.statusCode}');
  }

  static Future<Map<String, dynamic>> updateProgress(
      String lessonId, int watchPercentage) async {
    final response = await http.post(
      Uri.parse('$baseUrl/lessons/progress'),
      headers: await _headers(),
      body: json.encode({
        'lesson_id': lessonId,
        'watch_percentage': watchPercentage,
      }),
    );
    if (response.statusCode == 200) {
      return json.decode(response.body);
    }
    throw Exception('Failed to update progress: ${response.statusCode}');
  }

  static Future<List<Map<String, dynamic>>> getStudentProgress() async {
    final response = await http.get(
      Uri.parse('$baseUrl/student/courses/progress'),
      headers: await _headers(),
    );
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      return List<Map<String, dynamic>>.from(data['progress']);
    }
    throw Exception('Failed to load progress: ${response.statusCode}');
  }

  // ========== Helpers ==========

  static String? extractYoutubeId(String url) {
    final regExp = RegExp(
      r'(?:youtube\.com\/(?:watch\?v=|embed\/|v\/)|youtu\.be\/)'
      r'([a-zA-Z0-9_-]{11})',
    );
    final match = regExp.firstMatch(url);
    return match?.group(1);
  }

  static String? getYoutubeThumbnail(String videoUrl) {
    final videoId = extractYoutubeId(videoUrl);
    if (videoId != null) {
      return 'https://img.youtube.com/vi/$videoId/hqdefault.jpg';
    }
    return null;
  }
}
