import '../models/transaction.dart';

/// A single money movement whose size is known — either because the SMS
/// carried a balance line (preferred) or because it parsed into a
/// recognized [TransactionType] with an amount.
class SizedMovement {
  final DateTime date;
  final double amount;
  final bool isIncoming;
  final TransactionType type;

  const SizedMovement({
    required this.date,
    required this.amount,
    required this.isIncoming,
    required this.type,
  });
}

/// Walks [transactions] in chronological order and yields every money
/// movement whose size can be determined, preferring the balance MTN
/// itself reported after each SMS over the SMS's own face amount.
///
/// Text-pattern totals drift badly in practice — bank deposits, self
/// transfers to a linked bank account, and per-transfer fees all use
/// wording this app doesn't specifically parse, and failed transactions
/// still mention an amount despite no money moving. The balance field is
/// ground truth: the real change between two consecutive readings is
/// exactly what left or entered the account, regardless of wording.
/// Falls back to the parsed type/amount only for the rare SMS with no
/// balance line.
List<SizedMovement> sizedMovements(List<Transaction> transactions) {
  final chronological = [...transactions]..sort((a, b) => a.date.compareTo(b.date));

  final movements = <SizedMovement>[];
  double? previousBalance;

  for (final transaction in chronological) {
    double amount = transaction.amount;
    bool isIncoming = transaction.isIncoming;
    bool known = transaction.type != TransactionType.other;

    if (transaction.balanceAfter != null) {
      if (previousBalance != null) {
        final delta = transaction.balanceAfter! - previousBalance;
        amount = delta.abs();
        isIncoming = delta > 0;
        known = delta != 0;
      }
      previousBalance = transaction.balanceAfter;
    }

    if (!known) continue;
    movements.add(SizedMovement(
      date: transaction.date,
      amount: amount,
      isIncoming: isIncoming,
      type: transaction.type,
    ));
  }

  return movements;
}

/// Result of [computeFlows]: totals per category, the single largest money
/// movement found, and the most recent balance reading seen while walking
/// the transactions.
class FlowTotals {
  final double received;
  final double payments;
  final double transfers;
  final double withdrawals;
  final double purchases;
  final double? latestBalance;
  final DateTime? latestBalanceDate;

  /// The single biggest money movement (in or out) in the period, or null
  /// if nothing in the period could be sized.
  final double? largestAmount;
  final DateTime? largestDate;
  final bool? largestIsIncoming;
  final TransactionType? largestType;

  /// How many transactions contributed a sized amount to the totals above.
  final int countedTransactions;

  const FlowTotals({
    required this.received,
    required this.payments,
    required this.transfers,
    required this.withdrawals,
    required this.purchases,
    required this.latestBalance,
    required this.latestBalanceDate,
    required this.largestAmount,
    required this.largestDate,
    required this.largestIsIncoming,
    required this.largestType,
    required this.countedTransactions,
  });

  double get totalIn => received;
  double get totalOut => payments + transfers + withdrawals + purchases;

  /// Average size of a sized transaction (in or out), or 0 if none.
  double get averageAmount =>
      countedTransactions == 0 ? 0 : (totalIn + totalOut) / countedTransactions;
}

/// Totals money in/out per category over [transactions], plus the latest
/// reported balance and the single largest movement. See [sizedMovements]
/// for how each transaction's size is determined.
FlowTotals computeFlows(List<Transaction> transactions) {
  double received = 0;
  double payments = 0;
  double transfers = 0;
  double withdrawals = 0;
  double purchases = 0;

  double? largestAmount;
  DateTime? largestDate;
  bool? largestIsIncoming;
  TransactionType? largestType;

  final movements = sizedMovements(transactions);
  for (final movement in movements) {
    if (largestAmount == null || movement.amount > largestAmount) {
      largestAmount = movement.amount;
      largestDate = movement.date;
      largestIsIncoming = movement.isIncoming;
      largestType = movement.type;
    }

    if (movement.isIncoming) {
      received += movement.amount;
      continue;
    }

    switch (movement.type) {
      case TransactionType.transfer:
        transfers += movement.amount;
        break;
      case TransactionType.withdrawal:
        withdrawals += movement.amount;
        break;
      case TransactionType.purchase:
        purchases += movement.amount;
        break;
      case TransactionType.payment:
      case TransactionType.other:
        payments += movement.amount;
        break;
      case TransactionType.received:
        break;
    }
  }

  DateTime? latestBalanceDate;
  double? latestBalance;
  for (final transaction in transactions) {
    if (transaction.balanceAfter == null) continue;
    if (latestBalanceDate == null || transaction.date.isAfter(latestBalanceDate)) {
      latestBalanceDate = transaction.date;
      latestBalance = transaction.balanceAfter;
    }
  }

  return FlowTotals(
    received: received,
    payments: payments,
    transfers: transfers,
    withdrawals: withdrawals,
    purchases: purchases,
    latestBalance: latestBalance,
    latestBalanceDate: latestBalanceDate,
    largestAmount: largestAmount,
    largestDate: largestDate,
    largestIsIncoming: largestIsIncoming,
    largestType: largestType,
    countedTransactions: movements.length,
  );
}
