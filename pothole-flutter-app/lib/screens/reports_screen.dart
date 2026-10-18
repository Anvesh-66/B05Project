import 'package:flutter/material.dart';

import '../app_state.dart';
import '../models/pothole.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'shell.dart';

enum _ReportFilter {
  all('All'),
  high('High'),
  medium('Medium'),
  low('Low'),
  unresolved('Unresolved'),
  resolved('Resolved');

  const _ReportFilter(this.label);

  final String label;

  bool matches(Pothole p) => switch (this) {
        _ReportFilter.all => true,
        _ReportFilter.high => p.severity == Severity.high,
        _ReportFilter.medium => p.severity == Severity.medium,
        _ReportFilter.low => p.severity == Severity.low,
        _ReportFilter.unresolved => !p.isResolved,
        _ReportFilter.resolved => p.isResolved,
      };
}

/// Every submitted report, with search and filters.
class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key, required this.state, required this.nav});

  final AppState state;
  final AppNavigator nav;

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  _ReportFilter _filter = _ReportFilter.all;
  String _query = '';

  bool _matchesQuery(Pothole p) {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return true;
    return '${p.code} ${p.id} ${p.area ?? ''} ${p.address ?? ''}'.toLowerCase().contains(query);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const PageHeader('All Reports'),
      body: ListenableBuilder(
        listenable: widget.state,
        builder: (context, _) {
          final shown = widget.state.potholes.where((p) => _filter.matches(p) && _matchesQuery(p)).toList();
          return ListView(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 28),
            children: [
              TextField(
                onChanged: (value) => setState(() => _query = value),
                textInputAction: TextInputAction.search,
                decoration: const InputDecoration(
                  hintText: 'Search ID, area or road',
                  prefixIcon: Icon(Icons.search_rounded),
                ),
              ),
              const SizedBox(height: Gap.md),
              ChoiceChips<_ReportFilter>(
                options: _ReportFilter.values,
                selected: _filter,
                label: (f) => f.label,
                onSelected: (f) => setState(() => _filter = f),
              ),
              const SizedBox(height: Gap.md),
              if (shown.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 32),
                  child: Center(
                    child: Text(
                      widget.state.potholes.isEmpty ? 'No reports yet' : 'No matching reports',
                      style: TextStyle(color: context.colors.muted, fontSize: 14),
                    ),
                  ),
                )
              else
                for (final p in shown)
                  PotholeTile(
                    pothole: p,
                    onTap: () => widget.nav.openPothole(p),
                    trailing: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        SeverityBadge(p.severity),
                        const SizedBox(height: 4),
                        StatusTag(resolved: p.isResolved),
                      ],
                    ),
                  ),
            ],
          );
        },
      ),
    );
  }
}
