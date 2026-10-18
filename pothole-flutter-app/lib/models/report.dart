import 'severity.dart';

/// One bounding box found in a reported photo.
class Detection {
  const Detection({
    required this.className,
    required this.confidence,
    required this.severity,
    this.depthIndex,
    this.hasWater = false,
  });

  final String className;
  final double confidence;

  /// "Severe", "Neutral" or "Not Severe".
  final String severity;

  /// How far the pothole floor sits below the road around it, relative to the
  /// camera's distance (0 = flat). Not centimetres. Null when not measured.
  final double? depthIndex;

  /// The pothole looks filled with water, so its depth was not measured.
  final bool hasWater;

  Severity get level => Severity.ofDetection(severity);

  factory Detection.fromJson(Map<String, dynamic> json) {
    return Detection(
      className: json['class_name'] as String,
      confidence: (json['confidence'] as num).toDouble(),
      severity: json['severity'] as String,
      depthIndex: (json['depth_index'] as num?)?.toDouble(),
      hasWater: json['has_water'] as bool? ?? false,
    );
  }
}

/// The signed-in user's own report, with what the model found in the photo.
/// It starts as a draft ([submitted] false) that only its owner can see.
class Report {
  const Report({
    required this.id,
    required this.status,
    required this.risk,
    required this.detectionCount,
    required this.severeCount,
    required this.confidence,
    required this.createdAt,
    this.submitted = true,
    this.latitude,
    this.longitude,
    this.address,
    this.area,
    this.detections = const [],
  });

  final int id;

  /// "pending", "in_review" or "resolved".
  final String status;

  /// "LOW", "MED" or "HIGH".
  final String risk;
  final int detectionCount;
  final int severeCount;

  /// Highest confidence among [detections], 0 to 1.
  final double confidence;
  final DateTime createdAt;
  final bool submitted;
  final double? latitude;
  final double? longitude;
  final String? address;
  final String? area;
  final List<Detection> detections;

  Severity get severity => Severity.parse(risk);
  String get code => 'PH-${id.toString().padLeft(4, '0')}';
  bool get hasLocation => latitude != null && longitude != null;

  double get averageConfidence => detections.isEmpty
      ? confidence
      : detections.fold(0.0, (sum, d) => sum + d.confidence) / detections.length;

  factory Report.fromJson(Map<String, dynamic> json) {
    return Report(
      id: json['id'] as int,
      status: json['status'] as String,
      risk: json['risk'] as String,
      detectionCount: json['detection_count'] as int,
      severeCount: json['severe_count'] as int,
      confidence: (json['confidence'] as num).toDouble(),
      createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
      submitted: json['submitted'] as bool? ?? true,
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
      address: json['address'] as String?,
      area: json['area'] as String?,
      detections: ((json['detections'] as List<dynamic>?) ?? const [])
          .map((d) => Detection.fromJson(d as Map<String, dynamic>))
          .toList(),
    );
  }
}

class AppUser {
  const AppUser({required this.name, required this.email});

  final String name;
  final String email;

  factory AppUser.fromJson(Map<String, dynamic> json) {
    return AppUser(name: json['name'] as String, email: json['email'] as String);
  }

  Map<String, dynamic> toJson() => {'name': name, 'email': email};
}
