import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import '../models/transaction.dart';
import '../utils/flow_totals.dart';
import '../utils/transaction_style.dart';

class ChartScreen extends StatefulWidget {
  final List<Transaction> transactions;

  const ChartScreen({super.key, required this.transactions});

  @override
  State<ChartScreen> createState() => _ChartScreenState();
}

/// One period bucket (a week/month/year) worth of money in vs money out,
/// for the trend chart.
class _PeriodFlow {
  final DateTime date;
  final double moneyIn;
  final double moneyOut;
  const _PeriodFlow(this.date, this.moneyIn, this.moneyOut);
}

class _ChartScreenState extends State<ChartScreen> {
  String _selectedPeriod = 'Monthly';
  final List<String> _periods = ['Weekly', 'Monthly', 'Yearly'];

  int? _touchedBarGroup;
  int _touchedPieIndex = -1;

  DateTime _bucketStart(DateTime date) {
    switch (_selectedPeriod) {
      case 'Weekly':
        return DateTime(date.year, date.month, date.day - (date.weekday - 1));
      case 'Monthly':
        return DateTime(date.year, date.month);
      case 'Yearly':
        return DateTime(date.year);
      default:
        return date;
    }
  }

  DateTime _nextBucket(DateTime date) {
    switch (_selectedPeriod) {
      case 'Weekly':
        return date.add(const Duration(days: 7));
      case 'Monthly':
        return DateTime(date.year, date.month + 1);
      case 'Yearly':
        return DateTime(date.year + 1);
      default:
        return date;
    }
  }

  String _bucketLabel(DateTime date) {
    switch (_selectedPeriod) {
      case 'Weekly':
        return DateFormat('MMM d').format(date);
      case 'Monthly':
        return DateFormat('MMM y').format(date);
      case 'Yearly':
        return DateFormat('yyyy').format(date);
      default:
        return '';
    }
  }

  /// Buckets every sized money movement into money-in/money-out totals per
  /// period, filling gaps so the trend doesn't skip quiet periods.
  List<_PeriodFlow> _getPeriodFlows() {
    final movements = sizedMovements(widget.transactions);
    if (movements.isEmpty) return [];

    final inByBucket = <DateTime, double>{};
    final outByBucket = <DateTime, double>{};
    DateTime? minBucket;
    DateTime? maxBucket;

    for (final movement in movements) {
      final bucket = _bucketStart(movement.date);
      if (movement.isIncoming) {
        inByBucket[bucket] = (inByBucket[bucket] ?? 0) + movement.amount;
      } else {
        outByBucket[bucket] = (outByBucket[bucket] ?? 0) + movement.amount;
      }
      minBucket = minBucket == null || bucket.isBefore(minBucket) ? bucket : minBucket;
      maxBucket = maxBucket == null || bucket.isAfter(maxBucket) ? bucket : maxBucket;
    }

    final buckets = <DateTime>[];
    var current = minBucket!;
    while (!current.isAfter(maxBucket!)) {
      buckets.add(current);
      current = _nextBucket(current);
    }

    return buckets
        .map((b) => _PeriodFlow(b, inByBucket[b] ?? 0, outByBucket[b] ?? 0))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final flows = computeFlows(widget.transactions);
    final periodFlows = _getPeriodFlows();
    final formatter = NumberFormat("#,##0", "en_US");

    if (widget.transactions.isEmpty) {
      return const Center(child: Text('No data available'));
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SegmentedButton<String>(
            segments: _periods
                .map((period) =>
                    ButtonSegment<String>(value: period, label: Text(period)))
                .toList(),
            selected: {_selectedPeriod},
            onSelectionChanged: (selection) {
              setState(() {
                _selectedPeriod = selection.first;
                _touchedBarGroup = null;
              });
            },
          ),
          const SizedBox(height: 16),
          _buildStatGrid(flows, formatter),
          const SizedBox(height: 20),
          Text('Money in vs out',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          if (periodFlows.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: Text('No data for this period')),
            )
          else
            _buildTrendChart(periodFlows, formatter),
          const SizedBox(height: 24),
          Text('Spending breakdown',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          _buildCategoryBreakdown(flows, formatter),
        ],
      ),
    );
  }

  Widget _buildStatGrid(FlowTotals flows, NumberFormat formatter) {
    final stats = <_StatCardData>[
      _StatCardData(
        label: 'Highest transaction',
        value: flows.largestAmount != null
            ? '${formatter.format(flows.largestAmount)} RWF'
            : '—',
        subtitle: flows.largestDate != null
            ? DateFormat('MMM d, yyyy').format(flows.largestDate!)
            : 'No data yet',
        icon: Icons.trending_up_rounded,
        color: flows.largestIsIncoming == true
            ? const Color(0xFF0A8754)
            : const Color(0xFFC0392B),
      ),
      _StatCardData(
        label: 'Total in',
        value: '${formatter.format(flows.totalIn)} RWF',
        subtitle: '${flows.countedTransactions} transactions counted',
        icon: Icons.arrow_downward_rounded,
        color: const Color(0xFF0A8754),
      ),
      _StatCardData(
        label: 'Total out',
        value: '${formatter.format(flows.totalOut)} RWF',
        subtitle: 'Across payments, transfers & more',
        icon: Icons.arrow_upward_rounded,
        color: const Color(0xFFC0392B),
      ),
      _StatCardData(
        label: 'Average transaction',
        value: '${formatter.format(flows.averageAmount)} RWF',
        subtitle: 'Per sized movement',
        icon: Icons.insights_rounded,
        color: const Color(0xFF5B3DC4),
      ),
    ];

    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 1.5,
      children: stats.map((s) => _StatCard(data: s)).toList(),
    );
  }

  Widget _buildTrendChart(List<_PeriodFlow> periodFlows, NumberFormat formatter) {
    final maxValue = periodFlows
        .map((f) => f.moneyIn > f.moneyOut ? f.moneyIn : f.moneyOut)
        .fold<double>(0, (a, b) => a > b ? a : b);
    final interval = maxValue <= 0 ? 1.0 : maxValue / 4;

    return SizedBox(
      height: 260,
      child: BarChart(
        BarChartData(
          maxY: maxValue <= 0 ? 1 : maxValue * 1.15,
          alignment: BarChartAlignment.spaceAround,
          gridData: FlGridData(show: true, drawVerticalLine: false, horizontalInterval: interval),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 52,
                interval: interval,
                getTitlesWidget: (value, meta) => Text(
                  formatter.format(value),
                  style: const TextStyle(fontSize: 10, color: Colors.black54),
                ),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 40,
                getTitlesWidget: (value, meta) {
                  final index = value.toInt();
                  if (index < 0 || index >= periodFlows.length) return const SizedBox();
                  /* Thin out labels so long ranges (many months/weeks) don't
                   * overlap into an unreadable smear. */
                  final labelEvery = (periodFlows.length / 6).ceil().clamp(1, periodFlows.length);
                  if (index % labelEvery != 0) return const SizedBox();
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: RotatedBox(
                      quarterTurns: 1,
                      child: Text(
                        _bucketLabel(periodFlows[index].date),
                        style: const TextStyle(fontSize: 10, color: Colors.black54),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              getTooltipItem: (group, groupIndex, rod, rodIndex) {
                final flow = periodFlows[groupIndex];
                final isIn = rodIndex == 0;
                return BarTooltipItem(
                  '${_bucketLabel(flow.date)}\n',
                  const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12),
                  children: [
                    TextSpan(
                      text: '${isIn ? "In" : "Out"}: ${formatter.format(isIn ? flow.moneyIn : flow.moneyOut)} RWF',
                      style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w400),
                    ),
                  ],
                );
              },
            ),
            touchCallback: (event, response) {
              if (!event.isInterestedForInteractions || response?.spot == null) {
                setState(() => _touchedBarGroup = null);
                return;
              }
              setState(() => _touchedBarGroup = response!.spot!.touchedBarGroupIndex);
            },
          ),
          barGroups: periodFlows.asMap().entries.map((entry) {
            final index = entry.key;
            final flow = entry.value;
            final isTouched = _touchedBarGroup == index;
            return BarChartGroupData(
              x: index,
              barsSpace: 4,
              barRods: [
                BarChartRodData(
                  toY: flow.moneyIn,
                  color: const Color(0xFF0A8754),
                  width: isTouched ? 12 : 8,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
                ),
                BarChartRodData(
                  toY: flow.moneyOut,
                  color: const Color(0xFFC0392B),
                  width: isTouched ? 12 : 8,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
                ),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildCategoryBreakdown(FlowTotals flows, NumberFormat formatter) {
    final entries = <MapEntry<TransactionType, double>>[
      MapEntry(TransactionType.payment, flows.payments),
      MapEntry(TransactionType.transfer, flows.transfers),
      MapEntry(TransactionType.withdrawal, flows.withdrawals),
      MapEntry(TransactionType.purchase, flows.purchases),
    ].where((e) => e.value > 0).toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    if (entries.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: Text('No outgoing transactions in this range')),
      );
    }

    final total = entries.fold<double>(0, (sum, e) => sum + e.value);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 140,
          height: 140,
          child: PieChart(
            PieChartData(
              sectionsSpace: 2,
              centerSpaceRadius: 32,
              pieTouchData: PieTouchData(
                touchCallback: (event, response) {
                  if (!event.isInterestedForInteractions ||
                      response?.touchedSection == null) {
                    setState(() => _touchedPieIndex = -1);
                    return;
                  }
                  setState(() => _touchedPieIndex =
                      response!.touchedSection!.touchedSectionIndex);
                },
              ),
              sections: entries.asMap().entries.map((entry) {
                final index = entry.key;
                final type = entry.value.key;
                final amount = entry.value.value;
                final isTouched = index == _touchedPieIndex;
                final style = transactionTypeStyles[type]!;
                return PieChartSectionData(
                  value: amount,
                  color: style.color,
                  radius: isTouched ? 32 : 26,
                  showTitle: false,
                );
              }).toList(),
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: entries.asMap().entries.map((entry) {
              final index = entry.key;
              final type = entry.value.key;
              final amount = entry.value.value;
              final style = transactionTypeStyles[type]!;
              final percent = total == 0 ? 0 : (amount / total * 100);
              final isTouched = index == _touchedPieIndex;

              return InkWell(
                onTap: () => setState(
                    () => _touchedPieIndex = isTouched ? -1 : index),
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: style.color,
                          shape: BoxShape.circle,
                          border: isTouched
                              ? Border.all(color: Colors.black45, width: 1.5)
                              : null,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(style.label,
                            style: TextStyle(
                                fontSize: 13,
                                fontWeight:
                                    isTouched ? FontWeight.w700 : FontWeight.w500)),
                      ),
                      Text(
                        '${formatter.format(amount)} (${percent.toStringAsFixed(0)}%)',
                        style: const TextStyle(fontSize: 12, color: Colors.black54),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }
}

class _StatCardData {
  final String label;
  final String value;
  final String subtitle;
  final IconData icon;
  final Color color;
  const _StatCardData({
    required this.label,
    required this.value,
    required this.subtitle,
    required this.icon,
    required this.color,
  });
}

class _StatCard extends StatelessWidget {
  final _StatCardData data;
  const _StatCard({required this.data});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              Icon(data.icon, color: data.color, size: 16),
              const SizedBox(width: 6),
              Expanded(
                child: Text(data.label,
                    style: const TextStyle(fontSize: 12, color: Colors.black54),
                    overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            data.value,
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: data.color),
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            data.subtitle,
            style: const TextStyle(fontSize: 10, color: Colors.black45),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
