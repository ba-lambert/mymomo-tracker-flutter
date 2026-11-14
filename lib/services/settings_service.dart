import 'package:shared_preferences/shared_preferences.dart';

/// Persists this device's chosen phone name and the backend URL across
/// app restarts.
class SettingsService {
  static const _phoneNameKey = 'phone_name';
  static const _backendUrlKey = 'backend_url';

  /* Android emulator maps 10.0.2.2 to the host machine's localhost. */
  static const defaultBackendUrl = 'http://10.0.2.2:8000';

  Future<String?> getPhoneName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_phoneNameKey);
  }

  Future<void> setPhoneName(String name) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_phoneNameKey, name);
  }

  Future<String> getBackendUrl() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_backendUrlKey) ?? defaultBackendUrl;
  }

  Future<void> setBackendUrl(String url) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_backendUrlKey, url);
  }
}
