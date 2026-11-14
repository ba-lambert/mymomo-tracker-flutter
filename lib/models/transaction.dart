/// The category a MoMo SMS falls into, used to pick an icon/color and to
/// decide whether it counts as money in or out.
enum TransactionType { received, payment, transfer, withdrawal, purchase, other }

class Transaction {
  final double amount;
  final String description;
  final DateTime date;
  final String? reference;
  final bool isIncoming;
  final String body;
  final TransactionType type;

  /// Account balance MTN reported right after this transaction, if the SMS
  /// included one. This is the authoritative number for "current balance" —
  /// unlike summing transaction amounts, it can't drift from double-counted
  /// or missing SMS.
  final double? balanceAfter;

  Transaction({
    required this.amount,
    required this.description,
    required this.date,
    this.reference,
    required this.isIncoming,
    required this.body,
    required this.type,
    this.balanceAfter,
  });

  factory Transaction.fromSms(String sms, {required DateTime messageDate}) {
    final reference = _extractReference(sms);
    final balanceAfter = _extractBalance(sms);
    final notSettled = _notSettledRe.hasMatch(sms);
    final amount = notSettled ? 0.0 : _extractAmount(sms);
    final type = notSettled ? TransactionType.other : _classify(sms);
    final isIncoming = type == TransactionType.received;

    return Transaction(
      amount: amount,
      description: _describe(sms, type),
      date: messageDate,
      reference: reference,
      isIncoming: isIncoming,
      body: sms,
      type: type,
      balanceAfter: balanceAfter,
    );
  }

  /// A key that identifies this transaction uniquely regardless of how many
  /// times the same SMS was delivered. Prefers the bank/MoMo reference
  /// number when present, since two distinct transactions never share one;
  /// falls back to the raw text + timestamp for messages without one.
  String get dedupeKey => reference ?? '$body|${date.millisecondsSinceEpoch}';

  /// Converts this transaction to the JSON shape the backend's upload
  /// endpoint expects.
  Map<String, dynamic> toUploadJson() {
    return {
      'body': body,
      'date': date.toIso8601String(),
      'amount': amount,
      'description': description,
      'reference': reference,
      'is_incoming': isIncoming,
      'transaction_type': type.name,
    };
  }

  static final _amountRe = RegExp(r'(\d[\d,]*(?:\.\d+)?)\s*RWF');
  static final _balanceRe = RegExp(r'Balance\s*[:.]?\s*(\d[\d,]*(?:\.\d+)?)\s*RWF', caseSensitive: false);
  static final _referenceRe = RegExp(
    r'(?:TxId|TransactionId|Ref(?:erence)?|Financial\s*Transaction\s*Id)\s*[:.]?\s*(\d{6,})',
    caseSensitive: false,
  );

  static final _receivedRe = RegExp(r'received\s+[\d,.]+\s*RWF\s+from\s+(.+?)(?:\s*\(|\s+at\s+\d|\.)', caseSensitive: false);
  static final _paymentRe = RegExp(r'payment of\s+[\d,.]+\s*RWF\s+to\s+(.+?)(?:\s+was\s+completed|\.)', caseSensitive: false);
  static final _transferRe = RegExp(r'[\d,.]+\s*RWF\s+transferred\s+to\s+(.+?)(?:\s*\(|\.)', caseSensitive: false);
  static final _withdrawRe = RegExp(r'withdr\w+\s+[\d,.]+\s*RWF.*?(?:from|at)\s+(.+?)(?:\s+was\s+completed|\.|$)', caseSensitive: false);
  static final _purchaseRe = RegExp(r'transaction of\s+[\d,.]+\s*RWF\s+by\s+(.+?)(?:\s+was\s+completed|\.|$)', caseSensitive: false);
  static final _bankDepositRe = RegExp(r'bank deposit of\s+[\d,.]+\s*RWF', caseSensitive: false);
  static final _selfTransferRe = RegExp(r'you have transferred\s+[\d,.]+\s*RWF\s+to\s+(.+?)(?:\s*\(|\.)', caseSensitive: false);
  static final _notSettledRe = RegExp(r'\b(?:has failed|was canceled|was cancelled|is rejected|was reversed)\b', caseSensitive: false);

  static double _extractAmount(String sms) {
    final match = _amountRe.firstMatch(sms);
    if (match == null) return 0;
    return double.parse(match.group(1)!.replaceAll(',', ''));
  }

  static double? _extractBalance(String sms) {
    final match = _balanceRe.firstMatch(sms);
    if (match == null) return null;
    return double.parse(match.group(1)!.replaceAll(',', ''));
  }

  static String? _extractReference(String sms) {
    final match = _referenceRe.firstMatch(sms);
    return match?.group(1);
  }

  static TransactionType _classify(String sms) {
    if (_receivedRe.hasMatch(sms)) return TransactionType.received;
    if (_bankDepositRe.hasMatch(sms)) return TransactionType.received;
    if (_paymentRe.hasMatch(sms)) return TransactionType.payment;
    if (_selfTransferRe.hasMatch(sms)) return TransactionType.transfer;
    if (_transferRe.hasMatch(sms)) return TransactionType.transfer;
    if (_withdrawRe.hasMatch(sms)) return TransactionType.withdrawal;
    if (_purchaseRe.hasMatch(sms)) return TransactionType.purchase;
    return TransactionType.other;
  }

  static String _describe(String sms, TransactionType type) {
    RegExpMatch? match;
    switch (type) {
      case TransactionType.received:
        match = _receivedRe.firstMatch(sms);
        if (match != null) return 'From ${match.group(1)!.trim()}';
        return _bankDepositRe.hasMatch(sms) ? 'Bank deposit' : sms.split('.').first;
      case TransactionType.payment:
        match = _paymentRe.firstMatch(sms);
        return match != null ? 'To ${match.group(1)!.trim()}' : sms.split('.').first;
      case TransactionType.transfer:
        match = _transferRe.firstMatch(sms) ?? _selfTransferRe.firstMatch(sms);
        return match != null ? 'To ${match.group(1)!.trim()}' : sms.split('.').first;
      case TransactionType.withdrawal:
        match = _withdrawRe.firstMatch(sms);
        return match != null ? 'At ${match.group(1)!.trim()}' : sms.split('.').first;
      case TransactionType.purchase:
        match = _purchaseRe.firstMatch(sms);
        return match != null ? 'By ${match.group(1)!.trim()}' : sms.split('.').first;
      case TransactionType.other:
        return sms.split('.').first;
    }
  }
}
