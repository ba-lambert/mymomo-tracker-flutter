import 'package:flutter/material.dart';
import '../models/transaction.dart';
import '../services/sms_service.dart';
import '../services/background_export_service.dart';
import '../utils/transaction_style.dart';
import '../utils/flow_totals.dart';
import 'package:intl/intl.dart';
import 'charts_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  final _smsService = SmsService();
  List<Transaction> _transactions = [];
  List<Transaction> _dateFilteredTransactions = [];
  List<Transaction> _filteredTransactions = [];
  bool _isLoading = true;
  String? _error;
  DateTimeRange? _selectedDateRange;
  TransactionType? _selectedType;
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    /* SMS/contacts permission dialogs (triggered while loading transactions)
     * and the notification permission dialog (triggered while registering
     * for auto-export) must not fire concurrently: Android allows only one
     * requestPermissions() call per Activity in flight, and the loser's
     * await never resolves, hanging the whole screen. Sequencing them keeps
     * exactly one dialog in flight at a time. */
    _loadTransactions().then((_) => registerDeviceAndEnableAutoExport());
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadTransactions() async {
    try {
      setState(() {
        _isLoading = true;
        _error = null;
      });

      final transactions = await _smsService.getTransactions();
      setState(() {
        _transactions = transactions;
        _filterTransactions();
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  void _filterTransactions() {
    _dateFilteredTransactions = _transactions.where((transaction) {
      return _selectedDateRange == null ||
          (transaction.date.isAfter(_selectedDateRange!.start) &&
              transaction.date.isBefore(
                  _selectedDateRange!.end.add(const Duration(days: 1))));
    }).toList();

    _filteredTransactions = _selectedType == null
        ? List.from(_dateFilteredTransactions)
        : _dateFilteredTransactions
            .where((t) => t.type == _selectedType)
            .toList();
  }

  void _setTypeFilter(TransactionType? type) {
    setState(() {
      _selectedType = _selectedType == type ? null : type;
      _filterTransactions();
    });
  }

  Future<void> _selectDateRange() async {
    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: _selectedDateRange ??
          DateTimeRange(
            start: DateTime.now().subtract(const Duration(days: 30)),
            end: DateTime.now(),
          ),
    );

    if (picked != null) {
      setState(() {
        _selectedDateRange = picked;
        _filterTransactions();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.asset(
                'assets/images/momoLogo.webp',
                width: 28,
                height: 28,
              ),
            ),
            const SizedBox(width: 10),
            const Flexible(
              child: Text(
                'MoMo Tracker',
                style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Filter by date',
            icon: const Icon(Icons.calendar_today_outlined),
            onPressed: _selectDateRange,
          ),
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loadTransactions,
          ),
          const SizedBox(width: 4),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.receipt_long_rounded), text: 'Transactions'),
            Tab(icon: Icon(Icons.insights_rounded), text: 'Analytics'),
          ],
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.white,
          indicatorWeight: 3,
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildTransactionList(),
          ChartScreen(transactions: _dateFilteredTransactions),
        ],
      ),
    );
  }

  Widget _buildTransactionList() {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: Color(0xFF0A8754)),
            SizedBox(height: 16),
            Text('Loading transactions...',
                style: TextStyle(color: Colors.black54, fontSize: 16)),
          ],
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline_rounded,
                  color: Colors.redAccent, size: 48),
              const SizedBox(height: 12),
              Text('Error: $_error',
                  style: const TextStyle(color: Colors.red),
                  textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _loadTransactions,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (_filteredTransactions.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inbox_outlined, color: Colors.grey[400], size: 56),
            const SizedBox(height: 12),
            const Text('No transactions found',
                style: TextStyle(color: Colors.black54)),
            if (_selectedDateRange != null || _selectedType != null)
              TextButton(
                onPressed: () {
                  setState(() {
                    _selectedDateRange = null;
                    _selectedType = null;
                    _filterTransactions();
                  });
                },
                child: const Text('Clear filters'),
              ),
          ],
        ),
      );
    }

    final sections = _groupByDay(_filteredTransactions);

    return RefreshIndicator(
      color: const Color(0xFF0A8754),
      onRefresh: _loadTransactions,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
        children: [
          if (_selectedDateRange != null) _buildDateRangeChip(),
          _buildSummary(),
          const SizedBox(height: 8),
          for (final section in sections) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 16, 8, 8),
              child: Text(
                section.label,
                style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: Colors.black54,
                    fontSize: 13),
              ),
            ),
            for (final transaction in section.transactions)
              _buildTransactionCard(transaction),
          ],
        ],
      ),
    );
  }

  Widget _buildDateRangeChip() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Card(
        elevation: 0,
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: Colors.grey.shade200),
        ),
        child: ListTile(
          leading: const Icon(Icons.date_range, color: Color(0xFF0A8754)),
          title: Text(
            '${DateFormat('MMM dd, yyyy').format(_selectedDateRange!.start)} - '
            '${DateFormat('MMM dd, yyyy').format(_selectedDateRange!.end)}',
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
          ),
          trailing: IconButton(
            icon: const Icon(Icons.close, color: Colors.grey),
            onPressed: () {
              setState(() {
                _selectedDateRange = null;
                _filterTransactions();
              });
            },
          ),
        ),
      ),
    );
  }

  /// Splits transactions into "Today" / "Yesterday" / a formatted date
  /// section, preserving the descending date order they already come in.
  List<_DaySection> _groupByDay(List<Transaction> transactions) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));

    final sections = <_DaySection>[];
    DateTime? currentDay;
    for (final transaction in transactions) {
      final day = DateTime(
          transaction.date.year, transaction.date.month, transaction.date.day);
      if (currentDay == null || day != currentDay) {
        currentDay = day;
        String label;
        if (day == today) {
          label = 'Today';
        } else if (day == yesterday) {
          label = 'Yesterday';
        } else {
          label = DateFormat('EEEE, MMM d').format(day);
        }
        sections.add(_DaySection(label, []));
      }
      sections.last.transactions.add(transaction);
    }
    return sections;
  }

  Widget _buildSummary() {
    final flows = computeFlows(_dateFilteredTransactions);
    final received = flows.received;
    final payments = flows.payments;
    final transfers = flows.transfers;
    final withdrawals = flows.withdrawals;
    final purchases = flows.purchases;
    final latestBalance = flows.latestBalance;
    final latestBalanceDate = flows.latestBalanceDate;

    final totalOut = payments + transfers + withdrawals + purchases;
    final formatter = NumberFormat("#,##0", "en_US");

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildBalanceCard(latestBalance, latestBalanceDate, formatter),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
                child: _buildFlowCard(
                    'Money in',
                    received,
                    const Color(0xFF0A8754),
                    Icons.arrow_downward_rounded,
                    formatter)),
            const SizedBox(width: 10),
            Expanded(
                child: _buildFlowCard(
                    'Money out',
                    totalOut,
                    const Color(0xFFC0392B),
                    Icons.arrow_upward_rounded,
                    formatter)),
          ],
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 96,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              _buildCategoryChip(TransactionType.received, received, formatter),
              _buildCategoryChip(TransactionType.payment, payments, formatter),
              _buildCategoryChip(
                  TransactionType.transfer, transfers, formatter),
              _buildCategoryChip(
                  TransactionType.withdrawal, withdrawals, formatter),
              _buildCategoryChip(
                  TransactionType.purchase, purchases, formatter),
            ],
          ),
        ),
        if (_selectedType != null)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => _setTypeFilter(_selectedType),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: transactionTypeStyles[_selectedType]!.color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.filter_alt,
                        size: 14, color: transactionTypeStyles[_selectedType]!.color),
                    const SizedBox(width: 6),
                    Text(
                      'Showing ${transactionTypeStyles[_selectedType]!.label} only',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: transactionTypeStyles[_selectedType]!.color),
                    ),
                    const SizedBox(width: 6),
                    Icon(Icons.close,
                        size: 14, color: transactionTypeStyles[_selectedType]!.color),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildBalanceCard(
      double? balance, DateTime? asOf, NumberFormat formatter) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0A8754), Color(0xFF0D9E63)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
              color: const Color(0xFF0A8754).withOpacity(0.25),
              blurRadius: 16,
              offset: const Offset(0, 8)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Current balance',
              style: TextStyle(
                  color: Colors.white70,
                  fontSize: 13,
                  fontWeight: FontWeight.w500)),
          const SizedBox(height: 6),
          Text(
            balance != null
                ? '${formatter.format(balance)} RWF'
                : 'Not available',
            style: const TextStyle(
                color: Colors.white, fontSize: 30, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(
            asOf != null
                ? 'As of last MoMo SMS · ${DateFormat('MMM d, HH:mm').format(asOf)}'
                : 'No balance reported in this range',
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildFlowCard(String label, double amount, Color color, IconData icon,
      NumberFormat formatter) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8)),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(height: 10),
          Text(label,
              style: const TextStyle(color: Colors.black54, fontSize: 13)),
          const SizedBox(height: 2),
          Text(
            '${formatter.format(amount)} RWF',
            style: TextStyle(
                fontSize: 17, fontWeight: FontWeight.w700, color: color),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryChip(
      TransactionType type, double amount, NumberFormat formatter) {
    final style = transactionTypeStyles[type]!;
    final selected = _selectedType == type;
    return GestureDetector(
      onTap: () => _setTypeFilter(type),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 128,
        margin: const EdgeInsets.only(right: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: selected ? style.color.withOpacity(0.12) : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: selected ? style.color : Colors.grey.shade200, width: 1.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(style.icon, color: style.color, size: 18),
            const SizedBox(height: 6),
            Text(style.label,
                style: const TextStyle(fontSize: 12, color: Colors.black54)),
            const Spacer(),
            Text(
              '${formatter.format(amount)} RWF',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: style.color),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTransactionCard(Transaction transaction) {
    final formatter = NumberFormat("#,##0", "en_US");
    final style = transactionTypeStyles[transaction.type]!;
    final amountPrefix = transaction.isIncoming ? '+' : '-';

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _showTransactionDetails(transaction),
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: style.color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(style.icon, color: style.color, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      transaction.description,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Text(
                          DateFormat('HH:mm').format(transaction.date),
                          style:
                              TextStyle(color: Colors.grey[600], fontSize: 12),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: style.color.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            style.label,
                            style: TextStyle(
                                color: style.color,
                                fontSize: 11,
                                fontWeight: FontWeight.w600),
                          ),
                        ),
                        if (transaction.reference != null) ...[
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'Ref ${transaction.reference}',
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  color: Colors.grey[500], fontSize: 11),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '$amountPrefix${formatter.format(transaction.amount)}',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: transaction.isIncoming
                      ? const Color(0xFF0A8754)
                      : const Color(0xFFC0392B),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Shows the raw SMS text and all parsed fields for one transaction, since
  /// the list view truncates the message to a single line.
  void _showTransactionDetails(Transaction transaction) {
    final formatter = NumberFormat("#,##0", "en_US");
    final style = transactionTypeStyles[transaction.type]!;

    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(style.icon, color: style.color, size: 20),
            const SizedBox(width: 8),
            Expanded(child: Text(style.label)),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${transaction.isIncoming ? '+' : '-'}${formatter.format(transaction.amount)} RWF',
                style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: style.color),
              ),
              const SizedBox(height: 4),
              Text(
                DateFormat('EEEE, MMM d, yyyy · HH:mm:ss')
                    .format(transaction.date),
                style: TextStyle(color: Colors.grey[600], fontSize: 13),
              ),
              if (transaction.reference != null) ...[
                const SizedBox(height: 4),
                Text(
                  'Reference: ${transaction.reference}',
                  style: TextStyle(color: Colors.grey[600], fontSize: 13),
                ),
              ],
              const Divider(height: 24),
              Text(
                transaction.body,
                style: const TextStyle(fontSize: 14, height: 1.4),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}

class _DaySection {
  final String label;
  final List<Transaction> transactions;
  _DaySection(this.label, this.transactions);
}

