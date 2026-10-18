/// How serious a report is. The backend sends it as LOW, MED or HIGH.
enum Severity {
  high('High'),
  medium('Medium'),
  low('Low');

  const Severity(this.label);

  final String label;

  static Severity parse(String value) => switch (value.toUpperCase()) {
        'HIGH' => Severity.high,
        'MED' || 'MEDIUM' => Severity.medium,
        _ => Severity.low,
      };

  /// A single detection's severity: "Severe", "Neutral" or "Not Severe".
  static Severity ofDetection(String value) => switch (value.toLowerCase()) {
        'severe' => Severity.high,
        'not severe' => Severity.low,
        _ => Severity.medium,
      };
}
