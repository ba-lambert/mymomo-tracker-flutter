import 'package:flutter/services.dart';

/// Reads the device SMS inbox over a platform channel registered as a real
/// Flutter plugin, so it works from the main UI engine and from the headless
/// engines WorkManager and flutter_foreground_task create for background
/// work (a channel registered only in `MainActivity` would not).
class SmsReader {
  static const _channel = MethodChannel('com.example.momoapp/sms');

  /// Returns every SMS in the device inbox as raw maps with `address`,
  /// `body`, and `date` (epoch milliseconds) keys.
  ///
  /// @returns The raw inbox rows, newest first, as reported by the platform.
  static Future<List<dynamic>> getSmsMessages() {
    return _channel.invokeMethod('getSmsMessages').then((v) => v as List<dynamic>);
  }
}
