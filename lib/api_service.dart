import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:wael_mcp/session_manager.dart';

class ApiService {
  // ✅ Change this when deploying to production
  static const String baseUrl = 'http://127.0.0.1:8000';
  static const Duration _timeout = Duration(seconds: 15);

  // --- Private: Build Headers ---
  static Map<String, String> _headers({bool withAuth = false}) {
    final headers = {'Content-Type': 'application/json'};
    if (withAuth) {
      final token = SessionManager().token;
      if (token != null) {
        headers['Authorization'] = 'Bearer $token';
      }
    }
    return headers;
  }

  // --- Private: Handle Response ---
  static dynamic _handleResponse(http.Response response) {
    final body = jsonDecode(response.body);

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return body;
    }

    final detail = body['detail'] ?? 'An unexpected error occurred';

    switch (response.statusCode) {
      case 401:
        throw ApiException('Unauthorized. Please login again', code: 401);
      case 403:
        throw ApiException(detail, code: 403);
      case 404:
        throw ApiException(detail, code: 404);
      case 429:
        throw ApiException('Too many attempts. Please wait', code: 429);
      default:
        throw ApiException(detail, code: response.statusCode);
    }
  }

  // ========================
  //  Auth
  // ========================
  static Future<Map<String, dynamic>> login({
    required String email,
    required String password,
    required String deviceId,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/sessions/login'),
        headers: _headers(),
        body: jsonEncode({
          'email': email,
          'password': password,
          'device_id': deviceId,
        }),
      ).timeout(_timeout);

      return _handleResponse(response);
    } on SocketException {
      throw ApiException('Cannot connect to server. Check your internet connection');
    } on TimeoutException {
      throw ApiException('Connection timed out. Please try again');
    }
  }

  static Future<void> logout() async {
    try {
      final token = SessionManager().token;
      if (token == null) return;

      await http.post(
        Uri.parse('$baseUrl/sessions/logout'),
        headers: _headers(),
        body: jsonEncode({'session_token': token}),
      ).timeout(_timeout);
    } catch (_) {
      // Even if server logout fails, we clear the local session
    }
  }

  static Future<bool> validateSession() async {
    try {
      final token = SessionManager().token;
      if (token == null) return false;

      final response = await http.get(
        Uri.parse('$baseUrl/sessions/validate/$token'),
        headers: _headers(),
      ).timeout(_timeout);

      final body = jsonDecode(response.body);
      return body['valid'] == true;
    } catch (_) {
      return false;
    }
  }

  // ========================
  //  Student Profile
  // ========================
  static Future<Map<String, dynamic>> getProfile() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/student/profile'),
        headers: _headers(withAuth: true),
      ).timeout(_timeout);

      final body = _handleResponse(response);
      return body['student'];
    } on SocketException {
      throw ApiException('Cannot connect to server');
    } on TimeoutException {
      throw ApiException('Connection timed out');
    }
  }

  // ========================
  //  Sections
  // ========================
  static Future<List<Map<String, dynamic>>> getSections() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/sections'),
        headers: _headers(withAuth: true),
      ).timeout(_timeout);

      final body = _handleResponse(response);
      return List<Map<String, dynamic>>.from(body['sections']);
    } on SocketException {
      throw ApiException('Cannot connect to server');
    } on TimeoutException {
      throw ApiException('Connection timed out');
    }
  }

  // ========================
  //  Questions
  // ========================
  static Future<List<Map<String, dynamic>>> getQuestions(String sectionId) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/sections/$sectionId/questions'),
        headers: _headers(withAuth: true),
      ).timeout(_timeout);

      final body = _handleResponse(response);
      return List<Map<String, dynamic>>.from(body['questions']);
    } on SocketException {
      throw ApiException('Cannot connect to server');
    } on TimeoutException {
      throw ApiException('Connection timed out');
    }
  }

  // ========================
  //  Submit Answer
  // ========================
  static Future<Map<String, dynamic>> submitAttempt({
    required String questionId,
    required String submittedAnswer,
    bool revealed = false,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/attempts/submit'),
        headers: _headers(withAuth: true),
        body: jsonEncode({
          'question_id': questionId,
          'submitted_answer': submittedAnswer,
          'revealed': revealed,
        }),
      ).timeout(_timeout);

      return _handleResponse(response);
    } on SocketException {
      throw ApiException('Cannot connect to server');
    } on TimeoutException {
      throw ApiException('Connection timed out');
    }
  }

  // ========================
  //  Wrong Answers
  // ========================
  static Future<Map<String, dynamic>> getWrongAnswers() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/student/wrong-answers'),
        headers: _headers(withAuth: true),
      ).timeout(_timeout);

      return _handleResponse(response);
    } on SocketException {
      throw ApiException('Cannot connect to server');
    } on TimeoutException {
      throw ApiException('Connection timed out');
    }
  }

  // ========================
  //  Progress
  // ========================
  static Future<Map<String, dynamic>> getProgress() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/student/progress'),
        headers: _headers(withAuth: true),
      ).timeout(_timeout);

      return _handleResponse(response);
    } on SocketException {
      throw ApiException('Cannot connect to server');
    } on TimeoutException {
      throw ApiException('Connection timed out');
    }
  }

  // ========================
  //  Admin / Students Management
  // ========================
  static Future<List<Map<String, dynamic>>> getAllStudents() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/students'),
        headers: _headers(withAuth: true),
      ).timeout(_timeout);

      final body = _handleResponse(response);
      return List<Map<String, dynamic>>.from(body['students']);
    } on SocketException {
      throw ApiException('Cannot connect to server');
    } on TimeoutException {
      throw ApiException('Connection timed out');
    }
  }

  static Future<void> addStudent({
    required String fullName,
    required String email,
    String? className,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/students'),
        headers: _headers(withAuth: true),
        body: jsonEncode({
          'full_name': fullName,
          'email': email,
          'class_name': className,
        }),
      ).timeout(_timeout);
      _handleResponse(response);
    } on SocketException {
      throw ApiException('Cannot connect to server');
    } on TimeoutException {
      throw ApiException('Connection timed out');
    }
  }

  static Future<void> updateStudent({
    required String id,
    String? fullName,
    String? email,
    String? className,
  }) async {
    try {
      final response = await http.put(
        Uri.parse('$baseUrl/students/$id'),
        headers: _headers(withAuth: true),
        body: jsonEncode({
          if (fullName != null) 'full_name': fullName,
          if (email != null) 'email': email,
          if (className != null) 'class_name': className,
        }),
      ).timeout(_timeout);
      _handleResponse(response);
    } on SocketException {
      throw ApiException('Cannot connect to server');
    } on TimeoutException {
      throw ApiException('Connection timed out');
    }
  }

  static Future<void> deleteStudent(String id) async {
    try {
      final response = await http.delete(
        Uri.parse('$baseUrl/students/$id'),
        headers: _headers(withAuth: true),
      ).timeout(_timeout);
      _handleResponse(response);
    } on SocketException {
      throw ApiException('Cannot connect to server');
    } on TimeoutException {
      throw ApiException('Connection timed out');
    }
  }

  static Future<void> toggleStudentActivation(String id) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/students/$id/toggle-activation'),
        headers: _headers(withAuth: true),
      ).timeout(_timeout);
      _handleResponse(response);
    } on SocketException {
      throw ApiException('Cannot connect to server');
    } on TimeoutException {
      throw ApiException('Connection timed out');
    }
  }
}

// ✅ Custom Exception class
class ApiException implements Exception {
  final String message;
  final int? code;

  ApiException(this.message, {this.code});

  @override
  String toString() => message;
}