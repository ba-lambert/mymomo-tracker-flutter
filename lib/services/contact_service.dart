import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:permission_handler/permission_handler.dart';

/// Resolves device phone numbers to their saved contact name.
class ContactService {
  Map<String, String>? _nameByDigits;

  /// Loads every contact's phone numbers once and caches a digits-only
  /// lookup table, so repeated lookups don't re-query the device.
  ///
  /// Silently yields an empty table if contacts permission is denied, so
  /// SMS export can still proceed without names.
  Future<void> _ensureLoaded() async {
    if (_nameByDigits != null) return;

    final status = await Permission.contacts.request();
    if (!status.isGranted) {
      _nameByDigits = {};
      return;
    }

    final contacts = await FlutterContacts.getContacts(withProperties: true);
    final table = <String, String>{};
    for (final contact in contacts) {
      for (final phone in contact.phones) {
        final digits = _digitsOnly(phone.number);
        if (digits.isNotEmpty) {
          table[digits] = contact.displayName;
        }
      }
    }
    _nameByDigits = table;
  }

  /// Returns the saved contact name for [address], or null if none is
  /// saved or the address isn't a phone number (e.g. a sender shortcode).
  ///
  /// @param address - SMS sender/recipient address as read from the inbox.
  /// @returns The matching contact's display name, or null.
  Future<String?> resolveName(String address) async {
    await _ensureLoaded();
    final digits = _digitsOnly(address);
    if (digits.isEmpty) return null;

    final table = _nameByDigits!;
    if (table.containsKey(digits)) return table[digits];

    /* Match by last 9 digits to tolerate +250/0 country-code prefixes. */
    final suffix = digits.length > 9 ? digits.substring(digits.length - 9) : digits;
    for (final entry in table.entries) {
      final otherSuffix =
          entry.key.length > 9 ? entry.key.substring(entry.key.length - 9) : entry.key;
      if (otherSuffix == suffix) return entry.value;
    }
    return null;
  }

  static String _digitsOnly(String value) => value.replaceAll(RegExp(r'\D'), '');
}
