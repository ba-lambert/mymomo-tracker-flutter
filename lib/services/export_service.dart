import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';

import '../models/sms_message.dart';

/// Builds a zip export of SMS messages, grouped by the sender's phone
/// number, ready to upload to the backend.
class ExportService {
  /// Groups [messages] by sender address and writes them to a zip file
  /// containing a single `messages.json`.
  ///
  /// @param messages - Raw SMS already filtered to the desired date range.
  /// @param directory - Folder to write the zip into; defaults to the system temp directory.
  /// @returns The zip file written to [directory].
  Future<File> buildZipExport(List<SmsMessage> messages, {Directory? directory}) async {
    final grouped = <String, List<Map<String, dynamic>>>{};
    for (final message in messages) {
      grouped.putIfAbsent(message.address, () => []).add({
        'address': message.address,
        'body': message.body,
        'date': message.date.toIso8601String(),
        'contact_name': message.contactName,
      });
    }

    final payload = {
      'exported_at': DateTime.now().toIso8601String(),
      'message_count': messages.length,
      'groups': grouped,
    };

    final jsonBytes = utf8.encode(jsonEncode(payload));
    final archive = Archive()
      ..addFile(ArchiveFile('messages.json', jsonBytes.length, jsonBytes));

    final zipBytes = ZipEncoder().encode(archive)!;
    final fileName =
        'sms_export_${DateTime.now().millisecondsSinceEpoch}.zip';
    final targetDir = directory ?? Directory.systemTemp;
    await targetDir.create(recursive: true);
    final file = File('${targetDir.path}/$fileName');
    await file.writeAsBytes(zipBytes);
    return file;
  }
}
