/// A raw SMS as read from the device inbox, before any MoMo-specific parsing.
class SmsMessage {
  final String address;
  final String body;
  final DateTime date;

  /// Saved contact name matching [address], if one exists on the device.
  final String? contactName;

  SmsMessage({
    required this.address,
    required this.body,
    required this.date,
    this.contactName,
  });
}
