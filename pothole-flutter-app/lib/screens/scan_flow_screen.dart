import 'dart:async';

import 'package:flutter/material.dart';

import '../models/pothole.dart';
import '../models/report.dart';
import '../scan_controller.dart';
import '../services/location.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/pothole_map.dart';
import 'location_picker_screen.dart';
import 'shell.dart';

/// One photo's journey: review it, watch it being analysed, check the result, submit.
class ScanFlowScreen extends StatelessWidget {
  const ScanFlowScreen({super.key, required this.scan, required this.nav});

  final ScanController scan;
  final AppNavigator nav;

  Future<void> _chooseLocation(BuildContext context) async {
    final chosen = await Navigator.of(context).push<Coordinates>(
      MaterialPageRoute(
        builder: (_) => LocationPickerScreen(initial: scan.draft?.location, locate: scan.locate),
      ),
    );
    if (chosen != null) scan.setDraftLocation(chosen);
  }

  /// Opens the camera or gallery again, the same way this photo was chosen.
  void _retake() => scan.pickPhoto(fromCamera: scan.draft?.fromCamera ?? true);

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: scan,
      builder: (context, _) {
        final draft = scan.draft;
        // The flow was cleared underneath this screen; there is nothing left to show.
        if (draft == null) return const Scaffold(body: SizedBox());
        final (title, body) = switch (scan.stage) {
          ScanStage.review => (
              'Review Photo',
              _Review(
                draft: draft,
                error: scan.error,
                onAnalyze: scan.analyze,
                onRetake: _retake,
                onLocate: scan.locateDraft,
                onChooseLocation: () => _chooseLocation(context),
                onRemoveLocation: () => scan.setDraftLocation(null),
              ),
            ),
          ScanStage.analyzing => ('Analyzing', _Analyzing(draft: draft)),
          ScanStage.result => (
              'Detection Result',
              _Result(
                scan: scan,
                draft: draft,
                report: scan.result!,
                onRetake: _retake,
              ),
            ),
          ScanStage.clear => ('Result', _Clear(draft: draft, onRetake: _retake)),
          ScanStage.submitted => ('', _Submitted(report: scan.result!, nav: nav)),
        };
        final done = scan.stage == ScanStage.submitted;
        return PopScope(
          // While the server is working, or once submitted, "back" goes home, not to the photo.
          canPop: scan.stage != ScanStage.analyzing,
          child: Scaffold(
            appBar: done ? null : PageHeader(title),
            body: SafeArea(top: done, child: body),
          ),
        );
      },
    );
  }
}

const _flowPadding = EdgeInsets.fromLTRB(18, 0, 18, 28);

Widget _photo(PhotoDraft draft, {double maxHeight = 320}) {
  return ClipRRect(
    borderRadius: BorderRadius.circular(cardRadius),
    child: ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: Image.memory(draft.bytes, fit: BoxFit.cover, width: double.infinity, gaplessPlayback: true),
    ),
  );
}

// ---------------------------------------------------------------- review

class _Review extends StatelessWidget {
  const _Review({
    required this.draft,
    required this.error,
    required this.onAnalyze,
    required this.onRetake,
    required this.onLocate,
    required this.onChooseLocation,
    required this.onRemoveLocation,
  });

  final PhotoDraft draft;
  final String? error;
  final VoidCallback onAnalyze;
  final VoidCallback onRetake;
  final VoidCallback onLocate;
  final VoidCallback onChooseLocation;
  final VoidCallback onRemoveLocation;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: _flowPadding,
      children: [
        _photo(draft),
        if (error != null) ...[
          const SizedBox(height: Gap.md),
          MessageBanner.error(error!),
        ],
        const SectionHeader('Location'),
        AppCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: _location(context))),
        const SizedBox(height: Gap.lg),
        FilledButton.icon(
          onPressed: draft.canAnalyze ? onAnalyze : null,
          icon: const Icon(Icons.auto_awesome_rounded, size: 20),
          label: const Text('Detect potholes'),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: onRetake,
          icon: Icon(draft.fromCamera ? Icons.photo_camera_outlined : Icons.photo_library_outlined, size: 20),
          label: Text(draft.fromCamera ? 'Retake' : 'Choose another'),
        ),
      ],
    );
  }

  List<Widget> _location(BuildContext context) {
    final c = context.colors;
    final location = draft.location;
    final problem = draft.locationProblem;

    Widget line(IconData icon, Color color, String title, String detail, {Widget? action}) {
      return Row(
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: context.text.titleSmall),
                Text(detail, style: context.text.bodySmall),
              ],
            ),
          ),
          ?action,
        ],
      );
    }

    if (draft.isLocating) {
      return [
        Row(
          children: [
            const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2)),
            const SizedBox(width: 12),
            Text('Getting your location...', style: context.text.bodyMedium),
          ],
        ),
      ];
    }
    if (location != null) {
      return [
        line(
          Icons.location_on_rounded,
          c.low,
          '${location.latitude.toStringAsFixed(5)}, ${location.longitude.toStringAsFixed(5)}',
          draft.fromCamera ? "This phone's location" : 'Location you chose',
        ),
        if (!draft.fromCamera)
          Wrap(
            spacing: 4,
            children: [
              TextButton(onPressed: onChooseLocation, child: const Text('Change')),
              TextButton(onPressed: onRemoveLocation, child: const Text('Remove')),
            ],
          ),
      ];
    }
    if (draft.fromCamera) {
      final canFixInSettings = problem == LocationProblem.serviceOff || problem == LocationProblem.deniedForever;
      return [
        line(
          Icons.location_off_rounded,
          c.high,
          problem == null ? 'Location not found yet.' : LocationException(problem).message,
          'A camera report cannot be sent without your location.',
        ),
        Wrap(
          spacing: 4,
          children: [
            TextButton(onPressed: onLocate, child: const Text('Try again')),
            if (canFixInSettings)
              TextButton(onPressed: () => openSettingsFor(problem!), child: const Text('Open settings')),
          ],
        ),
      ];
    }
    return [
      line(
        Icons.location_off_outlined,
        c.muted,
        'No location added',
        'Optional. Mark where this photo was taken.',
        action: TextButton(onPressed: onChooseLocation, child: const Text('Add location')),
      ),
    ];
  }
}

// ---------------------------------------------------------------- analyzing

class _Analyzing extends StatefulWidget {
  const _Analyzing({required this.draft});

  final PhotoDraft draft;

  @override
  State<_Analyzing> createState() => _AnalyzingState();
}

class _AnalyzingState extends State<_Analyzing> with SingleTickerProviderStateMixin {
  static const _steps = ['Uploading image', 'Running AI detection', 'Classifying severity', 'Geo-tagging location'];

  late final _sweep = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))
    ..repeat(reverse: true);
  // The server answers in one go, so the checklist only shows that work is under way:
  // it advances on a timer and holds on the last step until the answer arrives.
  int _active = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 900), (timer) {
      if (_active >= _steps.length - 1) return timer.cancel();
      setState(() => _active++);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _sweep.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ListView(
      padding: _flowPadding,
      children: [
        Stack(
          children: [
            _photo(widget.draft),
            Positioned.fill(
              child: AnimatedBuilder(
                animation: _sweep,
                builder: (context, _) => Align(
                  alignment: Alignment(0, _sweep.value * 2 - 1),
                  child: Container(
                    height: 3,
                    decoration: const BoxDecoration(
                      color: Color(0xFF38BDF8),
                      boxShadow: [BoxShadow(color: Color(0x8C38BDF8), blurRadius: 18, spreadRadius: 6)],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        AppCard(
          child: Column(
            children: [
              for (final (index, step) in _steps.indexed)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    children: [
                      SizedBox.square(
                        dimension: 22,
                        child: index < _active
                            ? DecoratedBox(
                                decoration: BoxDecoration(color: c.low, shape: BoxShape.circle),
                                child: const Icon(Icons.check_rounded, size: 14, color: Colors.white),
                              )
                            : index == _active
                                ? const CircularProgressIndicator(strokeWidth: 2)
                                : DecoratedBox(
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      border: Border.all(color: c.border, width: 2),
                                    ),
                                  ),
                      ),
                      const SizedBox(width: 10),
                      Text(step, style: TextStyle(fontSize: 14, color: index <= _active ? c.text : c.muted)),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------- result

class _Result extends StatelessWidget {
  const _Result({required this.scan, required this.draft, required this.report, required this.onRetake});

  final ScanController scan;
  final PhotoDraft draft;
  final Report report;
  final VoidCallback onRetake;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final tone = c.of(report.severity);
    final position = report.hasLocation ? (latitude: report.latitude!, longitude: report.longitude!) : null;
    final place = [report.address, report.area].whereType<String>().join(', ');

    return ListView(
      padding: _flowPadding,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(cardRadius),
          // The server's copy has the detection boxes drawn on it.
          child: Image.network(
            '${scan.api.reportImageUri(report.id)}?kind=annotated',
            headers: scan.api.authHeaders,
            fit: BoxFit.contain,
            gaplessPlayback: true,
            loadingBuilder: (context, child, progress) => progress == null ? child : _photo(draft),
            errorBuilder: (context, _, _) => _photo(draft),
          ),
        ),
        const SizedBox(height: Gap.md),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: tone.soft, borderRadius: BorderRadius.circular(cardRadius)),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Overall severity', style: TextStyle(color: tone.color, fontSize: 12)),
                    Text(
                      report.severity.label,
                      style: TextStyle(color: tone.color, fontSize: 22, fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ),
              Icon(Icons.warning_amber_rounded, size: 34, color: tone.color),
            ],
          ),
        ),
        const SizedBox(height: 10),
        EqualRow(children: [
          StatCard(value: '${report.detectionCount}', label: 'Potholes'),
          StatCard(value: '${(report.averageConfidence * 100).round()}%', label: 'Avg conf.'),
          StatCard(value: '${(report.confidence * 100).round()}%', label: 'Top conf.'),
        ]),
        const SectionHeader('Detections'),
        AppCard(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          child: Column(
            children: [
              for (final (index, d) in report.detections.indexed)
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    border: index == 0 ? null : Border(top: BorderSide(color: c.border)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text.rich(
                              TextSpan(
                                children: [
                                  TextSpan(text: '#${index + 1} ', style: const TextStyle(fontWeight: FontWeight.w700)),
                                  TextSpan(text: 'Pothole', style: TextStyle(color: c.muted)),
                                ],
                              ),
                              style: const TextStyle(fontSize: 13),
                            ),
                            Text(
                              d.hasWater
                                  ? 'Water in pothole, depth not measured'
                                  : d.depthIndex == null
                                      ? 'Depth not measured'
                                      : 'Depth index ${d.depthIndex!.toStringAsFixed(2)}',
                              style: context.text.bodySmall,
                            ),
                          ],
                        ),
                      ),
                      Text('${(d.confidence * 100).round()}%', style: TextStyle(color: c.muted, fontSize: 12)),
                      const SizedBox(width: 10),
                      SeverityBadge(d.level),
                    ],
                  ),
                ),
            ],
          ),
        ),
        const SectionHeader('Location'),
        AppCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              if (position != null)
                SizedBox(height: 140, child: PotholeMap(center: position, zoom: 16, interactive: false, potholes: [
                  Pothole(
                    id: report.id,
                    severity: report.severity,
                    confidence: report.confidence,
                    detectionCount: report.detectionCount,
                    status: report.status,
                    createdAt: report.createdAt,
                    latitude: position.latitude,
                    longitude: position.longitude,
                  ),
                ])),
              Padding(
                padding: const EdgeInsets.all(14),
                child: KeyValueGrid(entries: [
                  ('Latitude', Text(position == null ? 'Not attached' : position.latitude.toStringAsFixed(6))),
                  ('Longitude', Text(position == null ? 'Not attached' : position.longitude.toStringAsFixed(6))),
                  ('Place', Text(place.isEmpty ? '—' : place, maxLines: 2, overflow: TextOverflow.ellipsis)),
                  ('Source', Text(position == null ? '—' : (draft.fromCamera ? 'Device GPS' : 'Chosen on map'))),
                ]),
              ),
            ],
          ),
        ),
        if (scan.error != null) ...[
          const SizedBox(height: Gap.md),
          MessageBanner.error(scan.error!),
        ],
        const SizedBox(height: Gap.lg),
        FilledButton.icon(
          onPressed: scan.isSubmitting ? null : scan.submit,
          icon: scan.isSubmitting
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Icon(Icons.check_rounded, size: 20),
          label: const Text('Submit report'),
        ),
        const SizedBox(height: 10),
        OutlinedButton(onPressed: scan.isSubmitting ? null : onRetake, child: const Text('Retake')),
      ],
    );
  }
}

// ---------------------------------------------------------------- nothing found

class _Clear extends StatelessWidget {
  const _Clear({required this.draft, required this.onRetake});

  final PhotoDraft draft;
  final VoidCallback onRetake;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: _flowPadding,
      children: [
        _photo(draft),
        const SizedBox(height: 24),
        const _BigCheck(),
        const SizedBox(height: 20),
        Text('No potholes detected', style: context.text.titleLarge, textAlign: TextAlign.center),
        const SizedBox(height: 6),
        Text(
          'The road in this photo looks clear, so nothing was reported.',
          style: context.text.bodySmall,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 20),
        FilledButton(onPressed: onRetake, child: const Text('Scan another')),
      ],
    );
  }
}

class _BigCheck extends StatelessWidget {
  const _BigCheck();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Center(
      child: Container(
        width: 84,
        height: 84,
        decoration: BoxDecoration(color: c.lowSoft, shape: BoxShape.circle),
        child: Icon(Icons.check_rounded, size: 44, color: c.low),
      ),
    );
  }
}

// ---------------------------------------------------------------- submitted

class _Submitted extends StatelessWidget {
  const _Submitted({required this.report, required this.nav});

  final Report report;
  final AppNavigator nav;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 48, 18, 28),
      children: [
        const _BigCheck(),
        const SizedBox(height: 20),
        Text('Report submitted', style: context.text.headlineSmall, textAlign: TextAlign.center),
        const SizedBox(height: 8),
        Text(
          report.hasLocation
              ? 'Your geo-tagged report is now on the map and visible to nearby drivers.'
              : 'Your report is saved. It has no location, so it is not shown on the map.',
          style: TextStyle(color: context.colors.muted, fontSize: 14, height: 1.4),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        AppCard(
          child: KeyValueGrid(entries: [
            ('Report ID', Text(report.code)),
            ('Severity', Align(alignment: Alignment.centerLeft, child: SeverityBadge(report.severity))),
            (
              'Coordinates',
              Text(
                report.hasLocation
                    ? '${report.latitude!.toStringAsFixed(4)}, ${report.longitude!.toStringAsFixed(4)}'
                    : 'Not attached',
              ),
            ),
            ('Status', const Text('Pending verification')),
          ]),
        ),
        const SizedBox(height: 20),
        if (report.hasLocation) ...[
          FilledButton.icon(
            onPressed: () => nav.openOnMap(report.id),
            icon: const Icon(Icons.map_outlined, size: 20),
            label: const Text('View on map'),
          ),
          const SizedBox(height: 10),
        ],
        OutlinedButton(onPressed: () => nav.openTab(AppTab.home), child: const Text('Back to home')),
      ],
    );
  }
}
