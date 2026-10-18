import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'shell.dart';

/// Totals, severity split, the week's reports and the worst areas, across all reports.
class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key, required this.state, required this.nav});

  final AppState state;
  final AppNavigator nav;

  static String _percent(int part, int whole) => whole == 0 ? '0%' : '${(part / whole * 100).round()}%';

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final data = state.dashboard;

    return RefreshIndicator(
      onRefresh: state.refresh,
      child: ListView(
        padding: screenPadding,
        children: [
          const TabHeader(overline: 'Monitoring', title: 'Dashboard'),
          if (state.loadError != null) ...[
            MessageBanner.error(state.loadError!, onRetry: state.refresh),
            const SizedBox(height: Gap.md),
          ],
          EqualRow(children: [
            StatCard(value: '${data.total}', label: 'Total reports'),
            StatCard(value: '${data.unresolved}', label: 'Unresolved', color: c.medium),
          ]),
          const SizedBox(height: 10),
          EqualRow(children: [
            StatCard(value: _percent(data.resolved, data.total), label: 'Resolution rate', color: c.low),
            StatCard(value: _percent(data.verified, data.total), label: 'Verified', color: c.primary),
          ]),
          const SizedBox(height: Gap.md),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Severity distribution', style: context.text.titleSmall?.copyWith(fontSize: 15)),
                const SizedBox(height: Gap.md),
                Row(
                  children: [
                    SizedBox.square(
                      dimension: 110,
                      child: CustomPaint(
                        painter: _DonutPainter(
                          values: [for (final s in Severity.values) data.countOf(s).toDouble()],
                          colors: [for (final s in Severity.values) c.of(s).color],
                          emptyColor: c.primarySoft,
                        ),
                      ),
                    ),
                    const SizedBox(width: 18),
                    Expanded(
                      child: Column(
                        children: [
                          for (final s in Severity.values)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Row(
                                children: [
                                  Container(
                                    width: 10,
                                    height: 10,
                                    decoration: BoxDecoration(
                                      color: c.of(s).color,
                                      borderRadius: BorderRadius.circular(3),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(child: Text(s.label, style: const TextStyle(fontSize: 13))),
                                  Text('${data.countOf(s)}', style: context.text.titleSmall?.copyWith(fontSize: 13)),
                                  const SizedBox(width: 8),
                                  SizedBox(
                                    width: 36,
                                    child: Text(
                                      _percent(data.countOf(s), data.total),
                                      style: TextStyle(color: c.muted, fontSize: 13),
                                      textAlign: TextAlign.right,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: Gap.md),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Reports this week', style: context.text.titleSmall?.copyWith(fontSize: 15)),
                const SizedBox(height: Gap.sm),
                SizedBox(height: 130, child: _WeekBars(week: data.week)),
              ],
            ),
          ),
          const SizedBox(height: Gap.md),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Area-wise hotspots', style: context.text.titleSmall?.copyWith(fontSize: 15)),
                const SizedBox(height: Gap.md),
                if (data.hotspots.isEmpty)
                  Text('No geo-tagged reports yet', style: TextStyle(color: c.muted, fontSize: 13))
                else
                  for (final spot in data.hotspots)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  spot.area,
                                  style: const TextStyle(fontSize: 13),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              Text('${spot.count}', style: context.text.titleSmall?.copyWith(fontSize: 13)),
                            ],
                          ),
                          const SizedBox(height: 5),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: spot.count / data.hotspots.first.count,
                              minHeight: 8,
                              color: c.primary,
                              backgroundColor: c.primarySoft,
                            ),
                          ),
                        ],
                      ),
                    ),
              ],
            ),
          ),
          const SizedBox(height: Gap.md),
          OutlinedButton.icon(
            onPressed: nav.openReports,
            icon: const Icon(Icons.format_list_bulleted_rounded, size: 20),
            label: const Text('All reports'),
          ),
        ],
      ),
    );
  }
}

/// One bar per day with its count above and the weekday letter below.
class _WeekBars extends StatelessWidget {
  const _WeekBars({required this.week});

  final List<({DateTime day, int count})> week;

  static const _letters = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    if (week.isEmpty) return const SizedBox();
    final peak = math.max(1, week.map((d) => d.count).reduce(math.max));
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (final (index, day) in week.indexed) ...[
          if (index > 0) const SizedBox(width: 8),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text(day.count == 0 ? '' : '${day.count}', style: context.text.labelSmall),
                const SizedBox(height: 4),
                Flexible(
                  child: FractionallySizedBox(
                    heightFactor: math.max(day.count / peak, 0.04),
                    alignment: Alignment.bottomCenter,
                    child: Container(
                      decoration: BoxDecoration(
                        color: day.count == 0 ? c.primarySoftBorder : c.primary,
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(6), bottom: Radius.circular(2)),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(_letters[day.day.weekday - 1], style: context.text.labelSmall),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// A ring split into one arc per value.
class _DonutPainter extends CustomPainter {
  const _DonutPainter({required this.values, required this.colors, required this.emptyColor});

  final List<double> values;
  final List<Color> colors;
  final Color emptyColor;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 14.0;
    final rect = Offset.zero & size;
    final ring = rect.deflate(stroke / 2);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;
    final total = values.fold(0.0, (a, b) => a + b);
    if (total == 0) {
      canvas.drawArc(ring, 0, math.pi * 2, false, paint..color = emptyColor);
      return;
    }
    // Start at the top and go clockwise.
    var start = -math.pi / 2;
    for (final (index, value) in values.indexed) {
      final sweep = value / total * math.pi * 2;
      canvas.drawArc(ring, start, sweep, false, paint..color = colors[index]);
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(_DonutPainter old) => old.values.toString() != values.toString() || old.colors != colors;
}
