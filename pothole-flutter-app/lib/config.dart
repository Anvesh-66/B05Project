/// Backend base URL, set at build time:
///
///   flutter run --dart-define=API_BASE_URL=http://192.168.1.50:8000
///
/// The default works on an emulator or a USB-connected phone after running
/// `adb reverse tcp:8000 tcp:8000`.
const String apiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://127.0.0.1:8000',
);

/// CPU inference plus the first-request model load can take a while.
const Duration apiTimeout = Duration(seconds: 90);

/// Photos are downscaled before upload; the model runs at 640px anyway.
const double maxUploadDimension = 1600;
const int uploadJpegQuality = 85;
