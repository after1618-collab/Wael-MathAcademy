import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:wael_mcp/session_manager.dart';
import 'package:wael_mcp/api_service.dart';

class VideoService {
  static String get baseUrl => ApiService.baseUrl;

  static Future<Map<String, String>> _headers() async {
    final token = SessionManager().token;
    return {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };
  }

  // ========== Student APIs ==========

  /// Get all published courses with progress
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
      throw ApiException('Session expired', 401);
    }
    throw Exception('Failed to load courses: ${response.statusCode}');
  }

  /// Get lessons for a specific course
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
      throw ApiException('Session expired', 401);
    }
    throw Exception('Failed to load lessons: ${response.statusCode}');
  }

  /// Update watch progress for a lesson
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

  /// Get student's overall course progress
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

  // ========== Helper ==========

  /// Extract YouTube video ID from URL
  static String? extractYoutubeId(String url) {
    final regExp = RegExp(
      r'(?:youtube\.com\/(?:watch\?v=|embed\/|v\/)|youtu\.be\/)'
      r'([a-zA-Z0-9_-]{11})',
    );
    final match = regExp.firstMatch(url);
    return match?.group(1);
  }

  /// Get YouTube thumbnail URL
  static String? getYoutubeThumbnail(String videoUrl) {
    final videoId = extractYoutubeId(videoUrl);
    if (videoId != null) {
      return 'https://img.youtube.com/vi/$videoId/hqdefault.jpg';
    }
    return null;
  }
}
