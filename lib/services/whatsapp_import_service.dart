import '../models/whatsapp_message.dart';

/// Parses a WhatsApp "Export chat" .txt file into [WhatsAppMessage]s.
///
/// WhatsApp writes one line per message as `date, time - sender: body` (or
/// `[date, time] sender: body` on iOS exports); a message that spans
/// multiple lines has its later lines with no date prefix at all, so those
/// are appended to the message currently being built.
class WhatsAppImportService {
  static final _androidLine = RegExp(
    r'^(\d{1,2}/\d{1,2}/\d{2,4}),\s*(\d{1,2}:\d{2}(?::\d{2})?\s*(?:[AaPp]\.?[Mm]\.?)?)\s*-\s*(.*)$',
  );
  static final _iosLine = RegExp(
    r'^\[(\d{1,2}/\d{1,2}/\d{2,4}),\s*(\d{1,2}:\d{2}(?::\d{2})?\s*(?:[AaPp]\.?[Mm]\.?)?)\]\s*(.*)$',
  );

  /// Parses the raw export text into messages, filtered to [since] onward.
  ///
  /// @param content - Full text of the exported .txt chat file.
  /// @param since - Oldest message date to keep; messages before it are dropped.
  /// @returns Parsed messages in file order (oldest first), each with a resolved sender and timestamp.
  List<WhatsAppMessage> parse(String content, {DateTime? since}) {
    final lines = content.split('\n');
    final messages = <WhatsAppMessage>[];

    String? pendingSender;
    DateTime? pendingDate;
    StringBuffer? pendingBody;

    void flush() {
      if (pendingSender != null && pendingDate != null && pendingBody != null) {
        if (since == null || !pendingDate.isBefore(since)) {
          messages.add(WhatsAppMessage(
            sender: pendingSender,
            body: pendingBody.toString().trim(),
            date: pendingDate,
          ));
        }
      }
    }

    for (final rawLine in lines) {
      final line = rawLine.replaceAll('‎', '').trimRight();
      if (line.isEmpty) continue;

      final match = _androidLine.firstMatch(line) ?? _iosLine.firstMatch(line);
      if (match == null) {
        pendingBody?.writeln(line);
        continue;
      }

      final date = _parseDate(match.group(1)!, match.group(2)!);
      if (date == null) {
        pendingBody?.writeln(line);
        continue;
      }

      flush();

      final rest = match.group(3)!;
      final separatorIndex = rest.indexOf(': ');
      if (separatorIndex == -1) {
        // System message (e.g. "Messages are end-to-end encrypted") — no sender.
        pendingSender = 'System';
        pendingBody = StringBuffer()..writeln(rest);
      } else {
        pendingSender = rest.substring(0, separatorIndex).trim();
        pendingBody = StringBuffer()..writeln(rest.substring(separatorIndex + 2));
      }
      pendingDate = date;
    }
    flush();

    return messages;
  }

  static DateTime? _parseDate(String datePart, String timePart) {
    final dateSegments = datePart.split('/').map(int.parse).toList();
    if (dateSegments.length != 3) return null;
    var a = dateSegments[0];
    var b = dateSegments[1];
    var year = dateSegments[2];
    if (year < 100) year += 2000;

    // WhatsApp's export uses the device's locale date order (DD/MM or
    // MM/DD); when one of the two leading numbers is over 12 it must be
    // the day, which disambiguates the order. Otherwise default to DD/MM,
    // the common convention outside the US.
    int day;
    int month;
    if (a > 12) {
      day = a;
      month = b;
    } else if (b > 12) {
      day = b;
      month = a;
    } else {
      day = a;
      month = b;
    }

    final timeMatch = RegExp(r'(\d{1,2}):(\d{2})(?::(\d{2}))?\s*([AaPp])?\.?[Mm]?\.?').firstMatch(timePart);
    if (timeMatch == null) return null;
    var hour = int.parse(timeMatch.group(1)!);
    final minute = int.parse(timeMatch.group(2)!);
    final second = timeMatch.group(3) != null ? int.parse(timeMatch.group(3)!) : 0;
    final meridiem = timeMatch.group(4)?.toLowerCase();
    if (meridiem == 'p' && hour != 12) hour += 12;
    if (meridiem == 'a' && hour == 12) hour = 0;

    try {
      return DateTime(year, month, day, hour, minute, second);
    } catch (_) {
      return null;
    }
  }
}
