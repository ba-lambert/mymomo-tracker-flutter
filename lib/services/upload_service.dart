import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../models/transaction.dart';

/// Counts of how an upload batch was processed by the backend.
class UploadSummary {
  final int received;
  final int inserted;
  final int skippedDuplicates;

  UploadSummary({
    required this.received,
    required this.inserted,
    required this.skippedDuplicates,
  });
}

/// Sends exported transactions to the MoMo Tracker backend.
class UploadService {
  final String baseUrl;

  UploadService(this.baseUrl);

  /// Uploads a batch of transactions under the given phone name.
  ///
  /// The backend registers the phone automatically on first upload and
  /// skips messages it has already stored for that phone.
  ///
  /// @param phoneName - Name identifying this device on the backend.
  /// @param transactions - Transactions to upload, typically filtered to a chosen date range.
  /// @returns How many of the sent messages were received, newly inserted, and skipped as duplicates.
  /// @throws {Exception} If the backend responds with a non-200 status.
  Future<UploadSummary> uploadTransactions({
    required String phoneName,
    required List<Transaction> transactions,
  }) async {
    final uri = Uri.parse('$baseUrl/api/messages/upload');
    final response = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'phone_name': phoneName,
        'messages': transactions.map((t) => t.toUploadJson()).toList(),
      }),
    );

    if (response.statusCode != 200) {
      throw Exception('Upload failed (${response.statusCode}): ${response.body}');
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return UploadSummary(
      received: json['received'] as int,
      inserted: json['inserted'] as int,
      skippedDuplicates: json['skipped_duplicates'] as int,
    );
  }

  /// Uploads a zip export (built by [ExportService]) under the given phone
  /// name. The backend unzips it, groups the contained messages by sender,
  /// and stores them against this phone.
  ///
  /// @param phoneName - Name identifying this device on the backend.
  /// @param zipFile - Zip file containing a `messages.json` export.
  /// @throws {Exception} If the backend responds with a non-200 status.
  Future<UploadSummary> uploadZip({
    required String phoneName,
    required File zipFile,
  }) async {
    final uri = Uri.parse('$baseUrl/api/messages/upload-zip');
    final request = http.MultipartRequest('POST', uri)
      ..fields['phone_name'] = phoneName
      ..files.add(await http.MultipartFile.fromPath('file', zipFile.path));

    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);

    if (response.statusCode != 200) {
      throw Exception('Upload failed (${response.statusCode}): ${response.body}');
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return UploadSummary(
      received: json['received'] as int,
      inserted: json['inserted'] as int,
      skippedDuplicates: json['skipped_duplicates'] as int,
    );
  }
}
