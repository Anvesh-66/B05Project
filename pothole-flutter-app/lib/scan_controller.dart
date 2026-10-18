import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import 'config.dart';
import 'models/report.dart';
import 'services/api_client.dart';
import 'services/location.dart';

/// A photo the user has chosen but not sent yet, with the location it will carry.
class PhotoDraft {
  const PhotoDraft({
    required this.bytes,
    required this.filename,
    required this.fromCamera,
    this.location,
    this.isLocating = false,
    this.locationProblem,
  });

  final Uint8List bytes;
  final String filename;

  /// A camera photo was taken here and now, so it must carry the phone's location.
  /// A gallery photo was taken elsewhere, so its location is optional and set by hand.
  final bool fromCamera;
  final Coordinates? location;
  final bool isLocating;

  /// Why the phone's location could not be read, when it was needed.
  final LocationProblem? locationProblem;

  bool get canAnalyze => !isLocating && (!fromCamera || location != null);

  PhotoDraft _with({Coordinates? location, bool isLocating = false, LocationProblem? locationProblem}) {
    return PhotoDraft(
      bytes: bytes,
      filename: filename,
      fromCamera: fromCamera,
      location: location,
      isLocating: isLocating,
      locationProblem: locationProblem,
    );
  }
}

/// Where the user is in reporting one photo.
enum ScanStage {
  /// Looking at the chosen photo and its location, before anything is sent.
  review,

  /// The server is analysing the photo.
  analyzing,

  /// The server found potholes; the user decides whether to submit or retake.
  result,

  /// The server found no pothole, so there is nothing to report.
  clear,

  /// The report was submitted.
  submitted,
}

/// Opens the camera or the gallery and returns the chosen photo, or null if cancelled.
typedef PhotoPicker = Future<XFile?> Function(ImageSource source);

Future<XFile?> _pickWithDevice(ImageSource source) {
  return ImagePicker().pickImage(
    source: source,
    maxWidth: maxUploadDimension,
    maxHeight: maxUploadDimension,
    imageQuality: uploadJpegQuality,
  );
}

/// Takes one photo from "chosen" to "reported": review, analysis, result, submit.
class ScanController extends ChangeNotifier {
  ScanController({required this.api, required this.locate, this.onSubmitted, PhotoPicker? picker})
      : _picker = picker ?? _pickWithDevice;

  final ApiClient api;
  final LocationProvider locate;
  final PhotoPicker _picker;

  /// Called after a report is submitted, so lists and counts can reload.
  final void Function(Report report)? onSubmitted;

  PhotoDraft? draft;
  ScanStage stage = ScanStage.review;

  /// The server's analysis of [draft]: a private draft until [submit].
  Report? result;
  bool isSubmitting = false;
  String? error;

  // Bumped whenever the photo changes, so a slow answer about an old photo is ignored.
  int _generation = 0;

  /// Opens the camera or gallery. Returns true when a photo was chosen and is ready to
  /// review; false when the user cancelled or the picker could not open (see [error]).
  Future<bool> pickPhoto({required bool fromCamera}) async {
    final XFile? image;
    try {
      image = await _picker(fromCamera ? ImageSource.camera : ImageSource.gallery);
    } on PlatformException catch (e) {
      error = 'Could not open the ${fromCamera ? 'camera' : 'gallery'}: ${e.message ?? e.code}';
      notifyListeners();
      return false;
    }
    // Cancelling leaves any photo already under review in place.
    if (image == null) return false;
    await stageImage(image, fromCamera: fromCamera);
    return true;
  }

  /// Holds [image] for review. Nothing is sent until [analyze].
  Future<void> stageImage(XFile image, {required bool fromCamera}) async {
    final generation = ++_generation;
    final bytes = await image.readAsBytes();
    if (generation != _generation) return;
    _dropServerDraft();
    draft = PhotoDraft(bytes: bytes, filename: image.name, fromCamera: fromCamera);
    stage = ScanStage.review;
    error = null;
    notifyListeners();
    if (fromCamera) await locateDraft();
  }

  /// Reads the phone's position into the draft. Done for every camera photo.
  Future<void> locateDraft() async {
    final current = draft;
    if (current == null || current.isLocating) return;
    final generation = _generation;
    draft = current._with(location: current.location, isLocating: true);
    notifyListeners();

    Coordinates? location;
    LocationProblem? problem;
    try {
      location = await locate();
    } on LocationException catch (e) {
      problem = e.problem;
    } catch (_) {
      problem = LocationProblem.unavailable;
    }

    if (generation != _generation || draft == null) return;
    draft = draft!._with(location: location ?? current.location, locationProblem: problem);
    notifyListeners();
  }

  /// Sets or clears the location of a gallery photo. A camera photo keeps the phone's own.
  void setDraftLocation(Coordinates? location) {
    final current = draft;
    if (current == null || current.fromCamera) return;
    draft = current._with(location: location);
    notifyListeners();
  }

  /// Sends the photo for analysis. On failure the photo is kept so it can be sent again.
  Future<void> analyze() async {
    final sending = draft;
    if (sending == null || !sending.canAnalyze || stage == ScanStage.analyzing) return;
    final generation = ++_generation;
    stage = ScanStage.analyzing;
    error = null;
    notifyListeners();

    Report? found;
    String? failure;
    try {
      found = await api.detect(
        sending.bytes,
        sending.filename,
        latitude: sending.location?.latitude,
        longitude: sending.location?.longitude,
      );
    } on ApiException catch (e) {
      failure = e.message;
    } catch (e) {
      failure = 'Unexpected error: $e';
    }

    if (generation != _generation) {
      // The user moved on while the server was working; do not leave its draft behind.
      if (found != null) api.discardDraft(found.id).catchError((_) {});
      return;
    }
    if (failure != null) {
      stage = ScanStage.review;
      error = failure;
    } else {
      result = found;
      stage = found == null ? ScanStage.clear : ScanStage.result;
    }
    notifyListeners();
  }

  /// Confirms the analysed report so it appears on the map for everyone.
  Future<void> submit() async {
    final pending = result;
    if (pending == null || stage != ScanStage.result || isSubmitting) return;
    final generation = _generation;
    isSubmitting = true;
    error = null;
    notifyListeners();

    Report? saved;
    String? failure;
    try {
      saved = await api.submitDraft(pending.id);
    } on ApiException catch (e) {
      failure = e.message;
    } catch (e) {
      failure = 'Unexpected error: $e';
    }

    if (generation != _generation) return;
    isSubmitting = false;
    if (saved != null) {
      result = saved;
      stage = ScanStage.submitted;
    } else {
      error = failure;
    }
    notifyListeners();
    if (saved != null) onSubmitted?.call(saved);
  }

  /// Forgets the photo and any unsubmitted analysis of it.
  void clear() {
    _generation++;
    _dropServerDraft();
    draft = null;
    stage = ScanStage.review;
    isSubmitting = false;
    error = null;
    notifyListeners();
  }

  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  // A reply from the server can arrive after the app has shut this controller down.
  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  /// Deletes the server's copy of an analysis the user did not submit.
  void _dropServerDraft() {
    final pending = result;
    result = null;
    if (pending != null && !pending.submitted) {
      api.discardDraft(pending.id).catchError((_) {});
    }
  }
}
