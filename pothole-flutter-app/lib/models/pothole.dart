import 'severity.dart';

/// A submitted pothole report as every user sees it: where, how severe and its
/// repair status, with nothing about who reported it.
class Pothole {
  const Pothole({
    required this.id,
    required this.severity,
    required this.confidence,
    required this.detectionCount,
    required this.status,
    required this.createdAt,
    this.resolvedAt,
    this.latitude,
    this.longitude,
    this.address,
    this.area,
    this.mine = false,
    this.distanceM,
  });

  final int id;
  final Severity severity;

  /// Highest model confidence among the report's detections, 0 to 1.
  final double confidence;
  final int detectionCount;

  /// "pending", "in_review" or "resolved".
  final String status;
  final DateTime createdAt;
  final DateTime? resolvedAt;
  final double? latitude;
  final double? longitude;
  final String? address;
  final String? area;

  /// True when the signed-in user reported it.
  final bool mine;

  /// Distance from the user, in metres. Only set on results of a nearby search.
  final double? distanceM;

  String get code => 'PH-${id.toString().padLeft(4, '0')}';
  bool get hasLocation => latitude != null && longitude != null;
  bool get isResolved => status == 'resolved';

  /// An admin has looked at the report: it is under review or already resolved.
  bool get isVerified => status != 'pending';
  String get statusLabel => isResolved ? 'Resolved' : 'Unresolved';

  /// The best short name for the place: the road, else the area, else a fallback.
  String get title => address ?? area ?? (hasLocation ? 'Reported pothole' : 'No location attached');

  factory Pothole.fromJson(Map<String, dynamic> json) {
    final resolvedAt = json['resolved_at'] as String?;
    return Pothole(
      id: json['id'] as int,
      severity: Severity.parse(json['severity'] as String),
      confidence: (json['confidence'] as num).toDouble(),
      detectionCount: json['detection_count'] as int,
      status: json['status'] as String,
      createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
      resolvedAt: resolvedAt == null ? null : DateTime.parse(resolvedAt).toLocal(),
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
      address: json['address'] as String?,
      area: json['area'] as String?,
      mine: json['mine'] as bool? ?? false,
      distanceM: (json['distance_m'] as num?)?.toDouble(),
    );
  }
}

/// Figures for the dashboard, covering every submitted report.
class DashboardData {
  const DashboardData({
    required this.total,
    required this.unresolved,
    required this.resolved,
    required this.verified,
    required this.high,
    required this.medium,
    required this.low,
    required this.week,
    required this.hotspots,
  });

  static const empty = DashboardData(
    total: 0,
    unresolved: 0,
    resolved: 0,
    verified: 0,
    high: 0,
    medium: 0,
    low: 0,
    week: [],
    hotspots: [],
  );

  final int total;
  final int unresolved;
  final int resolved;
  final int verified;
  final int high;
  final int medium;
  final int low;

  /// Reports per day for the last seven days, oldest first.
  final List<({DateTime day, int count})> week;

  /// Areas with the most reports, largest first.
  final List<({String area, int count})> hotspots;

  int countOf(Severity severity) => switch (severity) {
        Severity.high => high,
        Severity.medium => medium,
        Severity.low => low,
      };

  factory DashboardData.fromJson(Map<String, dynamic> json) {
    return DashboardData(
      total: json['total'] as int,
      unresolved: json['unresolved'] as int,
      resolved: json['resolved'] as int,
      verified: json['verified'] as int,
      high: json['high'] as int,
      medium: json['medium'] as int,
      low: json['low'] as int,
      week: (json['week'] as List<dynamic>)
          .map((d) => (day: DateTime.parse(d['date'] as String), count: d['count'] as int))
          .toList(),
      hotspots: (json['hotspots'] as List<dynamic>)
          .map((h) => (area: h['area'] as String, count: h['count'] as int))
          .toList(),
    );
  }
}

String formatDistance(double metres) =>
    metres < 1000 ? '${metres.round()} m' : '${(metres / 1000).toStringAsFixed(1)} km';

/// "just now", "12 min ago", "3 h ago" or "5 d ago".
String timeAgo(DateTime time, {DateTime? now}) {
  final minutes = (now ?? DateTime.now()).difference(time).inMinutes;
  if (minutes < 1) return 'just now';
  if (minutes < 60) return '$minutes min ago';
  if (minutes < 1440) return '${(minutes / 60).round()} h ago';
  return '${(minutes / 1440).round()} d ago';
}

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/// "14 Oct, 09:30".
String formatDateTime(DateTime t) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(t.day)} ${_months[t.month - 1]}, ${two(t.hour)}:${two(t.minute)}';
}
