import 'dart:developer' as developer;
import 'dart:io';

import 'package:receive_sharing_intent/receive_sharing_intent.dart';

import 'settings_service.dart';
import 'upload_service.dart';
import 'whatsapp_import_service.dart';

/// Listens for a WhatsApp chat `.txt` shared into this app (via WhatsApp's
/// own "Export chat" → share sheet) and imports it automatically: no file
/// picker, no manual navigation.
///
/// WhatsApp still has to export the chat itself — Android gives no app
/// access to another app's data — but once the user taps this app in the
/// share sheet, everything from there (parsing, filtering to the last 30
/// days, uploading) happens on its own.
class WhatsAppShareService {
  final _settingsService = SettingsService();
  final _importService = WhatsAppImportService();

  /// Checks for a share that launched the app cold (app was not running),
  /// and starts listening for shares that arrive while it stays running.
  ///
  /// @param onImported - Called after each shared chat is parsed and uploaded, with a human-readable result message.
  /// @param onError - Called if reading, parsing or uploading a shared chat fails.
  void start({
    required void Function(String message) onImported,
    required void Function(String message) onError,
  }) {
    ReceiveSharingIntent.instance.getMediaStream().listen((files) {
      _handleSharedFiles(files, onImported, onError);
    }, onError: (e) {
      onError('Failed to receive shared file: $e');
    });

    ReceiveSharingIntent.instance.getInitialMedia().then((files) {
      ReceiveSharingIntent.instance.reset();
      _handleSharedFiles(files, onImported, onError);
    });
  }

  Future<void> _handleSharedFiles(
    List<SharedMediaFile> files,
    void Function(String message) onImported,
    void Function(String message) onError,
  ) async {
    for (final file in files) {
      final isTextFile = (file.mimeType?.startsWith('text/') ?? false) || file.path.endsWith('.txt');
      if (!isTextFile) continue;

      try {
        await _importOne(file);
        onImported('Imported "${_chatNameFrom(file.path)}" from WhatsApp');
      } catch (e) {
        developer.log('WhatsApp share import failed: $e');
        onError('WhatsApp import failed: $e');
      }
    }
  }

  Future<void> _importOne(SharedMediaFile file) async {
    final phoneName = await _settingsService.getPhoneName();
    if (phoneName == null || phoneName.isEmpty) {
      throw Exception('Set a phone name in Settings before importing WhatsApp chats');
    }

    final content = await File(file.path).readAsString();
    final since = DateTime.now().subtract(const Duration(days: 30));
    final messages = _importService.parse(content, since: since);
    if (messages.isEmpty) return;

    final chatName = _chatNameFrom(file.path);
    final backendUrl = await _settingsService.getBackendUrl();
    await UploadService(backendUrl).uploadRawMessages(
      phoneName: phoneName,
      messages: messages.map((m) => m.toUploadJson(chatName)).toList(),
    );
  }

  /// Derives a readable chat name from WhatsApp's export filename, e.g.
  /// "WhatsApp Chat with Alice.txt" -> "Alice", "WhatsApp Chat - Family.txt"
  /// -> "Family".
  String _chatNameFrom(String path) {
    final fileName = path.split(Platform.pathSeparator).last.replaceAll('.txt', '');
    return fileName
        .replaceFirst(RegExp(r'^WhatsApp Chat with '), '')
        .replaceFirst(RegExp(r'^WhatsApp Chat[ -]+'), '')
        .trim();
  }
}
