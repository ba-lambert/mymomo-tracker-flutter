/// One message parsed out of a WhatsApp "Export chat" .txt file.
class WhatsAppMessage {
  final String sender;
  final String body;
  final DateTime date;

  WhatsAppMessage({required this.sender, required this.body, required this.date});

  /// Converts this message to the JSON shape the backend's generic
  /// `/api/messages/upload` endpoint expects, tagged so it stays distinct
  /// from MoMo SMS in the dashboard.
  ///
  /// @param chatName - Name of the WhatsApp chat/group this message came from, used as the sender address.
  Map<String, dynamic> toUploadJson(String chatName) {
    return {
      'sender': chatName,
      'contact_name': sender,
      'body': body,
      'date': date.toIso8601String(),
      'source': 'whatsapp',
    };
  }
}
