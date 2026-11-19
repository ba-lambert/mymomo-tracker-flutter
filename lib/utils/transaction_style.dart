import 'package:flutter/material.dart';
import '../models/transaction.dart';

/// Visual styling (icon, color, label) for each [TransactionType], shared
/// across the transaction list, the summary cards, and the analytics
/// charts so all three stay in sync.
class TransactionTypeStyle {
  final IconData icon;
  final Color color;
  final String label;
  const TransactionTypeStyle(this.icon, this.color, this.label);
}

const transactionTypeStyles = <TransactionType, TransactionTypeStyle>{
  TransactionType.received: TransactionTypeStyle(
      Icons.call_received_rounded, Color(0xFF0A8754), 'Received'),
  TransactionType.payment: TransactionTypeStyle(
      Icons.storefront_rounded, Color(0xFFE08A00), 'Payment'),
  TransactionType.transfer: TransactionTypeStyle(
      Icons.call_made_rounded, Color(0xFFC0392B), 'Transfer'),
  TransactionType.withdrawal: TransactionTypeStyle(
      Icons.money_off_rounded, Color(0xFFAD1457), 'Withdrawal'),
  TransactionType.purchase: TransactionTypeStyle(
      Icons.shopping_bag_rounded, Color(0xFF5B3DC4), 'Purchase'),
  TransactionType.other: TransactionTypeStyle(
      Icons.receipt_long_rounded, Color(0xFF6B7A72), 'Other'),
};
