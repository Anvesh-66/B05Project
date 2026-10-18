// Exercises a running backend through the app's own API client: signs in, analyses one
// photo, submits the report, then reads it back from the community list, the nearby
// search and the dashboard.
//
//   dart run tool/check_backend.dart <email> <password> <image> [base-url] [lat] [lng]
import 'dart:io';

import 'package:pothole_detector/models/pothole.dart';
import 'package:pothole_detector/services/api_client.dart';

Future<void> main(List<String> args) async {
  if (args.length < 3) {
    stderr.writeln('Usage: dart run tool/check_backend.dart <email> <password> <image> [base-url] [lat] [lng]');
    exit(64);
  }
  final file = File(args[2]);
  final api = ApiClient(baseUrl: args.length > 3 ? args[3] : null);
  final latitude = args.length > 5 ? double.parse(args[4]) : 18.5204;
  final longitude = args.length > 5 ? double.parse(args[5]) : 73.8567;
  try {
    final session = await api.login(email: args[0], password: args[1]);
    api.token = session.token;
    stdout.writeln('signed in as ${session.user.name} <${session.user.email}>');

    final draft = await api.detect(
      await file.readAsBytes(),
      file.uri.pathSegments.last,
      latitude: latitude,
      longitude: longitude,
    );
    if (draft == null) {
      stdout.writeln('no potholes detected; nothing saved');
    } else {
      stdout.writeln('draft ${draft.code}: ${draft.severity.label} severity, submitted=${draft.submitted}, '
          'place: ${draft.address ?? '-'}, ${draft.area ?? '-'}');
      for (final d in draft.detections) {
        final depth = d.hasWater ? 'water' : (d.depthIndex?.toStringAsFixed(2) ?? 'not measured');
        stdout.writeln('  ${d.className} ${(d.confidence * 100).round()}% ${d.severity}, depth $depth');
      }
      final listedEarly = (await api.potholes()).any((p) => p.id == draft.id);
      stdout.writeln('listed before submit: $listedEarly (expected false)');

      final saved = await api.submitDraft(draft.id);
      stdout.writeln('submitted ${saved.code}: submitted=${saved.submitted}');
    }

    final potholes = await api.potholes();
    final nearby = await api.nearby(latitude: latitude, longitude: longitude, radiusM: 1000);
    final dashboard = await api.dashboard();
    stdout.writeln('community list: ${potholes.length} potholes');
    stdout.writeln('within 1 km: ${nearby.length}'
        '${nearby.isEmpty ? '' : ', nearest ${nearby.first.code} at ${formatDistance(nearby.first.distanceM ?? 0)}'}');
    stdout.writeln('dashboard: total ${dashboard.total}, unresolved ${dashboard.unresolved}, '
        'high ${dashboard.high}, medium ${dashboard.medium}, low ${dashboard.low}, '
        'hotspots ${dashboard.hotspots.map((h) => '${h.area} (${h.count})').join(', ')}');
  } on ApiException catch (e) {
    stderr.writeln('FAILED: ${e.message}');
    exitCode = 1;
  } finally {
    api.close();
  }
}
