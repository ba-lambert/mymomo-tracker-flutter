import 'package:permission_handler/permission_handler.dart';
import 'package:sms_reader/sms_reader.dart';
import '../models/sms_message.dart';
import '../models/transaction.dart';
import 'contact_service.dart';
import 'momo_counterparty.dart';
import 'dart:developer' as developer;

class SmsService {
  final _contactService = ContactService();

  /// Reads every SMS in the device inbox, regardless of sender, and
  /// attaches each sender's saved contact name when one exists.
  Future<List<SmsMessage>> getAllMessages() async {
    // Only call request() when not already granted. request() needs a
    // foreground Activity to show its system dialog; the background sync
    // service and WorkManager's headless isolate have none, so calling it
    // there throws ("Unable to detect current Activity"). Once the user has
    // granted it once from the foreground (the app's first launch), status
    // stays granted and every later caller — foreground or background —
    // can skip straight past this check.
    var status = await Permission.sms.status;
    if (!status.isGranted) {
      status = await Permission.sms.request();
    }
    if (!status.isGranted) {
      throw Exception('SMS permission denied');
    }

    try {
      final messages = await SmsReader.getSmsMessages();

      developer.log('Read ${messages.length} SMS messages');

      final rawMessages = messages
          .where((message) => message['body'] != null)
          .map((message) => (
                address: (message['address'] as String?) ?? 'unknown',
                body: message['body'] as String,
                date: DateTime.fromMillisecondsSinceEpoch(message['date'] as int),
              ))
          .toList();

      final result = <SmsMessage>[];
      for (final raw in rawMessages) {
        /* The real sender/recipient name for MoMo texts is in the body, not
         * the address, since every MoMo SMS shares one shortcode sender. */
        final name = MomoCounterparty.extractName(raw.body) ??
            await _contactService.resolveName(raw.address);
        result.add(SmsMessage(
          address: raw.address,
          body: raw.body,
          date: raw.date,
          contactName: name,
        ));
      }

      result.sort((a, b) => b.date.compareTo(a.date));
      return result;
    } catch (e) {
      developer.log('Error reading SMS: $e', error: e);
      throw Exception('Failed to read SMS: $e');
    }
  }

  /// Reads MoMo ("M-Money") transaction messages only, parsed into
  /// [Transaction]s for the home screen's list and charts.
  ///
  /// Drops exact duplicates (the Android SMS provider occasionally returns
  /// the same delivered message twice) so totals and the running balance
  /// never double-count a transaction.
  Future<List<Transaction>> getTransactions() async {
    final allMessages = await getAllMessages();

    final momoMessages = allMessages.where((message) =>
        message.address == 'M-Money' &&
        (message.body.contains('transferred to') ||
         message.body.contains('payment of') ||
         message.body.contains('received') ||
         message.body.contains('withdr') ||
         message.body.contains('transaction of')));

    final seen = <String>{};
    final transactions = <Transaction>[];
    for (final message in momoMessages) {
      try {
        final transaction = Transaction.fromSms(message.body, messageDate: message.date);
        if (seen.add(transaction.dedupeKey)) {
          transactions.add(transaction);
        }
      } catch (e) {
        developer.log('Error processing message: $e');
      }
    }

    transactions.sort((a, b) => b.date.compareTo(a.date));
    return transactions;
  }
}
