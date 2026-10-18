import 'package:flutter/material.dart';

import '../app_state.dart';
import '../scan_controller.dart';
import '../services/location.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'scan_flow_screen.dart';
import 'shell.dart';

/// Where a report starts: take a photo or choose one.
class ScanScreen extends StatelessWidget {
  const ScanScreen({super.key, required this.state, required this.scan, required this.nav});

  final AppState state;
  final ScanController scan;
  final AppNavigator nav;

  Future<void> _pick(BuildContext context, {required bool fromCamera}) async {
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final picked = await scan.pickPhoto(fromCamera: fromCamera);
    if (!picked) {
      // A cancelled picker says nothing; one that failed to open explains why.
      final problem = scan.error;
      if (problem != null && scan.draft == null) messenger.showSnackBar(SnackBar(content: Text(problem)));
      return;
    }
    await navigator.push(MaterialPageRoute<void>(builder: (_) => ScanFlowScreen(scan: scan, nav: nav)));
    // Leaving the flow without submitting throws the photo and its analysis away.
    scan.clear();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final here = state.location;
    final problem = state.locationProblem;
    return ListView(
      padding: screenPadding,
      children: [
        const TabHeader(title: 'Scan Road'),
        _DashedBorder(
          color: c.primarySoftBorder,
          child: Material(
            color: c.card,
            borderRadius: BorderRadius.circular(20),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => _pick(context, fromCamera: true),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 30),
                child: Column(
                  children: [
                    const IconTile(icon: Icons.photo_camera_outlined, size: 60),
                    const SizedBox(height: Gap.md),
                    Text('Take a road photo', style: context.text.titleSmall?.copyWith(fontSize: 15)),
                    const SizedBox(height: 4),
                    Text('Your location is attached automatically', style: context.text.bodySmall),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: Gap.md),
        EqualRow(children: [
          OutlinedButton.icon(
            onPressed: () => _pick(context, fromCamera: false),
            icon: const Icon(Icons.photo_library_outlined, size: 20),
            label: const Text('From gallery'),
          ),
          OutlinedButton.icon(
            onPressed: state.isLocating ? null : state.updateLocation,
            icon: const Icon(Icons.my_location_rounded, size: 20),
            label: const Text('Get GPS'),
          ),
        ]),
        const SizedBox(height: Gap.md),
        AppCard(
          child: Row(
            children: [
              const IconTile(icon: Icons.location_on_outlined),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Geo-tag', style: context.text.titleSmall),
                    Text(
                      state.isLocating
                          ? 'Finding your location...'
                          : here != null
                              ? '${here.latitude.toStringAsFixed(5)}, ${here.longitude.toStringAsFixed(5)}'
                              : (problem == null
                                  ? 'Tap Get GPS to find your location'
                                  : LocationException(problem).message),
                      style: context.text.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SectionHeader('How it works'),
        const AppCard(
          child: Column(
            children: [
              _Step(1, 'Take a photo of the road, or choose one from your gallery'),
              _Step(2, 'The AI model detects potholes and draws a box around each'),
              _Step(3, 'Severity is classified as Low, Medium or High'),
              _Step(4, 'You review the result, then submit it to the map', isLast: true),
            ],
          ),
        ),
      ],
    );
  }
}

class _Step extends StatelessWidget {
  const _Step(this.number, this.text, {this.isLast = false});

  final int number;
  final String text;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : 10),
      child: Row(
        children: [
          Container(
            width: 26,
            height: 26,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: c.primarySoft, shape: BoxShape.circle),
            child: Text('$number', style: TextStyle(color: c.primary, fontSize: 12, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 13))),
        ],
      ),
    );
  }
}

/// Draws a dashed rounded outline around [child].
class _DashedBorder extends StatelessWidget {
  const _DashedBorder({required this.color, required this.child});

  final Color color;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(foregroundPainter: _DashedPainter(color), child: child);
  }
}

class _DashedPainter extends CustomPainter {
  const _DashedPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const dash = 7.0, gap = 5.0;
    final outline = Path()
      ..addRRect(RRect.fromRectAndRadius((Offset.zero & size).deflate(1), const Radius.circular(20)));
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    for (final metric in outline.computeMetrics()) {
      for (var at = 0.0; at < metric.length; at += dash + gap) {
        canvas.drawPath(metric.extractPath(at, at + dash), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DashedPainter old) => old.color != color;
}
