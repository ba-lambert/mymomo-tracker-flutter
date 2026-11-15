import 'dart:math';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persists this device's chosen phone name and the backend URL across
/// app restarts.
class SettingsService {
  static const _phoneNameKey = 'phone_name';
  static const _backendUrlKey = 'backend_url';
  static const _autoExportEnabledKey = 'auto_export_enabled';
  static const _lastAutoExportAtKey = 'last_auto_export_at';

  /// Our own deployed backend; every device talks to this by default so
  /// there is nothing to configure on install.
  static const defaultBackendUrl = 'http://109.199.97.39:8000';

  Future<String?> getPhoneName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_phoneNameKey);
  }

  Future<void> setPhoneName(String name) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_phoneNameKey, name);
  }

  /// Returns the saved phone name, or generates and saves one from the
  /// device's make/model plus a short random suffix (to keep two phones
  /// of the same model from colliding) the first time this is called.
  ///
  /// This is what lets a freshly installed app register itself with the
  /// backend with no setup step.
  Future<String> getOrCreateDeviceName() async {
    final existing = await getPhoneName();
    if (existing != null && existing.isNotEmpty) return existing;

    String label;
    try {
      final info = await DeviceInfoPlugin().androidInfo;
      label = '${info.manufacturer} ${info.model}'.trim();
    } catch (_) {
      label = 'Android phone';
    }

    final suffix = Random().nextInt(0x1000000).toRadixString(16).padLeft(6, '0');
    final name = '$label-$suffix';
    await setPhoneName(name);
    return name;
  }

  Future<String> getBackendUrl() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_backendUrlKey) ?? defaultBackendUrl;
  }

  Future<void> setBackendUrl(String url) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_backendUrlKey, url);
  }

  /// Whether the periodic background export-and-upload task is turned on.
  Future<bool> isAutoExportEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_autoExportEnabledKey) ?? false;
  }

  Future<void> setAutoExportEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_autoExportEnabledKey, enabled);
  }

  /// When the background task last finished a successful export, used to
  /// export only messages newer than the previous run.
  Future<DateTime?> getLastAutoExportAt() async {
    final prefs = await SharedPreferences.getInstance();
    final millis = prefs.getInt(_lastAutoExportAtKey);
    return millis == null ? null : DateTime.fromMillisecondsSinceEpoch(millis);
  }

  Future<void> setLastAutoExportAt(DateTime time) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_lastAutoExportAtKey, time.millisecondsSinceEpoch);
  }
}
