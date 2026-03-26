import 'package:shared_preferences/shared_preferences.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:io' show Platform;

/// Singleton class to store the session token globally
class SessionManager {
  static final SessionManager _instance = SessionManager._internal();
  factory SessionManager() => _instance;
  SessionManager._internal();

  String? _sessionToken;
  String? _deviceId;

  String? get token => _sessionToken;
  String? get deviceId => _deviceId;

  // --- Session Token ---
  Future<void> setToken(String token) async {
    _sessionToken = token;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('session_token', token);
  }

  Future<void> loadToken() async {
    final prefs = await SharedPreferences.getInstance();
    _sessionToken = prefs.getString('session_token');
  }

  Future<void> clear() async {
    _sessionToken = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('session_token');
    // ملاحظة: مش بنمسح الـ device_id عشان يفضل ثابت
  }

  // --- Device ID ---
  Future<String> getOrCreateDeviceId() async {
    if (_deviceId != null) return _deviceId!;

    final prefs = await SharedPreferences.getInstance();
    _deviceId = prefs.getString('device_id');

    if (_deviceId == null) {
      _deviceId = await _generateDeviceId();
      await prefs.setString('device_id', _deviceId!);
    }

    return _deviceId!;
  }

  Future<String> _generateDeviceId() async {
    try {
      final deviceInfo = DeviceInfoPlugin();

      if (kIsWeb) {
        final webInfo = await deviceInfo.webBrowserInfo;
        // للويب: نعمل ID من معلومات المتصفح
        final raw = '${webInfo.browserName}_${webInfo.platform}_${webInfo.userAgent}';
        return 'web_${raw.hashCode.toRadixString(16)}';
      } else if (Platform.isAndroid) {
        final androidInfo = await deviceInfo.androidInfo;
        return 'android_${androidInfo.id}';
      } else if (Platform.isIOS) {
        final iosInfo = await deviceInfo.iosInfo;
        return 'ios_${iosInfo.identifierForVendor ?? DateTime.now().millisecondsSinceEpoch}';
      }
    } catch (e) {
      // fallback
    }
    return 'device_${DateTime.now().millisecondsSinceEpoch}';
  }
}