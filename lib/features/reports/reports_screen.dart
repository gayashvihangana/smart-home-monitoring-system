/// Usage reporting.
///
/// The spec leaves presentation open — "you may decide the best way to present
/// this information" — so the choices here are deliberate and each answers a
/// different question:
///
///   Summary cards → is anything happening, and is the safety system working?
///   Daily bars    → WHEN does this device run?
///   Ranked list   → WHAT is consuming the most?
///
/// This screen does no computation on usage figures. The worker aggregates
/// `events` into `usageDaily` server-side, so rendering is a plain read. If a
/// duration is ever being calculated in here, the aggregation is incomplete and
/// belongs back in the worker.
library;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/device.dart';
import '../../data/providers.dart';

class ReportsScreen extends ConsumerWidget {
  const ReportsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final usage = ref.watch(allUsageProvider);
    final devices = ref.watch(allDevicesProvider);
    final alerts = ref.watch(alertsProvider);
    final range = ref.watch(reportRangeProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Usage reports'),
        actions: [
          SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 7, label: Text('7d')),
              ButtonSegment(value: 30, label: Text('30d')),
            ],
            selected: {range},
            onSelectionChanged: (s) =>
                ref.read(reportRangeProvider.notifier).select(s.first),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: usage.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Could not load usage: $e')),
        data: (usageByDevice) {
          if (usageByDevice.isEmpty) {
            return const Center(child: Text('No usage recorded yet.'));
          }

          final deviceList = devices.asData?.value ?? const <Device>[];
          final names = {for (final d in deviceList) d.id: d.name};
          final ranked = _rank(usageByDevice, names);
          final cutoffsThisWeek = (alerts.asData?.value ?? const <Alert>[])
              .where((a) => a.isCutoff && _withinDays(a.timestamp, 7))
              .length;

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _SummaryRow(
                totalTodayHours: _totalToday(usageByDevice),
                busiest: ranked.isEmpty ? null : ranked.first,
                cutoffsThisWeek: cutoffsThisWeek,
              ),
              const SizedBox(height: 24),
              Text('Daily usage — ${ranked.isEmpty ? '' : ranked.first.name}',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              SizedBox(
                height: 220,
                child: ranked.isEmpty
                    ? const SizedBox.shrink()
                    : _DailyBarChart(
                        days: usageByDevice[ranked.first.id] ?? const [],
                      ),
              ),
              const SizedBox(height: 32),
              Text('Devices by total on-time',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              ..._rankedRows(context, ranked),
            ],
          );
        },
      ),
    );
  }

  static bool _withinDays(int timestampMs, int days) {
    final cutoff = DateTime.now().subtract(Duration(days: days));
    return DateTime.fromMillisecondsSinceEpoch(timestampMs).isAfter(cutoff);
  }

  static double _totalToday(Map<String, List<UsageDay>> usage) {
    final today = DateTime.now().toIso8601String().substring(0, 10);
    var seconds = 0;
    for (final days in usage.values) {
      for (final d in days) {
        if (d.date == today) seconds += d.onSeconds;
      }
    }
    return seconds / 3600.0;
  }

  static List<_RankedDevice> _rank(
    Map<String, List<UsageDay>> usage,
    Map<String, String> names,
  ) {
    final ranked = usage.entries.map((entry) {
      final total = entry.value.fold<int>(0, (sum, d) => sum + d.onSeconds);
      return _RankedDevice(
        id: entry.key,
        name: names[entry.key] ?? entry.key,
        totalSeconds: total,
      );
    }).toList();
    ranked.sort((a, b) => b.totalSeconds.compareTo(a.totalSeconds));
    return ranked;
  }

  static List<Widget> _rankedRows(
      BuildContext context, List<_RankedDevice> ranked) {
    if (ranked.isEmpty) return const [];
    final max = ranked.first.totalSeconds;
    return ranked.map((d) {
      final fraction = max == 0 ? 0.0 : d.totalSeconds / max;
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(child: Text(d.name)),
                Text(_formatHours(d.totalSeconds / 3600.0),
                    style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
            const SizedBox(height: 4),
            // A bar behind each row reads faster than a number alone, and needs
            // no legend.
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: fraction,
                minHeight: 6,
                backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
              ),
            ),
          ],
        ),
      );
    }).toList();
  }
}

String _formatHours(double hours) {
  if (hours < 1) return '${(hours * 60).round()} min';
  return '${hours.toStringAsFixed(1)} h';
}

class _RankedDevice {
  const _RankedDevice({
    required this.id,
    required this.name,
    required this.totalSeconds,
  });

  final String id;
  final String name;
  final int totalSeconds;
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
    required this.totalTodayHours,
    required this.busiest,
    required this.cutoffsThisWeek,
  });

  final double totalTodayHours;
  final _RankedDevice? busiest;
  final int cutoffsThisWeek;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _SummaryCard(
          label: 'On-time today',
          value: _formatHours(totalTodayHours),
          icon: Icons.schedule,
        ),
        const SizedBox(width: 12),
        _SummaryCard(
          label: 'Most used',
          value: busiest?.name ?? '—',
          icon: Icons.trending_up,
        ),
        const SizedBox(width: 12),
        _SummaryCard(
          label: 'Cutoffs this week',
          value: '$cutoffsThisWeek',
          icon: Icons.shield_outlined,
          // Non-zero is not a fault — it means the safety system did its job.
          highlight: cutoffsThisWeek > 0,
        ),
      ],
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.label,
    required this.value,
    required this.icon,
    this.highlight = false,
  });

  final String label;
  final String value;
  final IconData icon;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Expanded(
      child: Card(
        color: highlight ? scheme.tertiaryContainer : null,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 18),
              const SizedBox(height: 8),
              Text(value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 2),
              Text(label, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      ),
    );
  }
}

class _DailyBarChart extends StatelessWidget {
  const _DailyBarChart({required this.days});

  final List<UsageDay> days;

  @override
  Widget build(BuildContext context) {
    if (days.isEmpty) return const Center(child: Text('No data'));

    final scheme = Theme.of(context).colorScheme;
    final maxHours = days
        .map((d) => d.onHours)
        .fold<double>(0, (a, b) => a > b ? a : b);

    return BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceAround,
        maxY: (maxHours * 1.2).clamp(1, double.infinity),
        borderData: FlBorderData(show: false),
        gridData: FlGridData(show: true, drawVerticalLine: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: true, reservedSize: 32),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 28,
              getTitlesWidget: (value, meta) {
                final i = value.toInt();
                if (i < 0 || i >= days.length) return const SizedBox.shrink();
                // Day-of-month only. Full dates overlap badly on a phone.
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(days[i].date.substring(8),
                      style: const TextStyle(fontSize: 10)),
                );
              },
            ),
          ),
        ),
        barGroups: [
          for (var i = 0; i < days.length; i++)
            BarChartGroupData(
              x: i,
              barRods: [
                BarChartRodData(
                  toY: days[i].onHours,
                  width: 12,
                  color: scheme.primary,
                  borderRadius: BorderRadius.circular(3),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
