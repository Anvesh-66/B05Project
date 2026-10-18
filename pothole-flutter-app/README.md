# RoadGuard AI (Flutter app)

Mobile client for the backend in `../pothole-detection-app/`.

- Create an account and sign in; the session is kept between launches
- **Home**: potholes near you, quick totals and the latest reports
- **Scan**: take a photo (location required) or pick one from the gallery (location optional,
  chosen on a map), review it, run detection, check the result, then submit
- **Map**: every geo-tagged pothole, filterable by severity and status
- **Alerts**: unresolved potholes within 500 m to 5 km, most severe first, with a
  notification and vibration when a new one comes into range
- **Dashboard**: totals, severity split, reports this week and area hotspots
- **All reports**: search and filter; each pothole has a detail page with a status timeline
- **Settings**: alert radius, alerts on/off, dark mode, account

Detection runs on the server, not on the phone.

## 1. Start the backend

See `../pothole-detection-app/README.md`. In short, from that folder:

```powershell
.\scripts\run_backend.ps1
```

## 2. Run the app

Connect an Android phone by USB with USB debugging on, then from this folder:

```powershell
.\run_app.ps1          # over USB
.\run_app.ps1 -Wifi    # over Wi-Fi, keeps working after the cable is unplugged
```

The script checks that the phone is connected and authorized, warns if the backend is not
running, and then starts the app.

- **USB mode** forwards the phone's port 8000 to this PC (`adb reverse`). The forwarding is
  lost when the cable is unplugged or the phone reconnects, and the app then cannot reach the
  server until the script is run again.
- **Wi-Fi mode** builds the app to use this PC's network address. The phone and PC must be on
  the same Wi-Fi, and Windows Firewall must allow port 8000.

The backend address is fixed when the app is built; there is no server setting inside the app.
To build an APK for a particular address:

```powershell
flutter build apk --release --dart-define=API_BASE_URL=http://192.168.1.50:8000
```

## Alerts

While the app is open it follows the phone's position. Each time the phone moves about 30 m it
asks the server for unresolved potholes within the chosen radius. A pothole that has just come
into range raises one notification with a vibration (longer for high severity); it will not
alert again until it has left the radius and come back. Alerts need the location and
notification permissions, and stop when the app is closed.

## Tests

```powershell
flutter analyze
flutter test
```

To exercise a running backend with the app's own API client (signs in, analyses and submits
one photo, then reads the map list, nearby search and dashboard):

```powershell
dart run tool/check_backend.dart <email> <password> <image> [base-url] [lat] [lng]
```

## Project layout

```
lib/
  main.dart                    App entry; shows login or the tabs
  config.dart                  Backend URL, timeout, upload size
  theme.dart                   Light and dark colours, Material theme
  auth_controller.dart         Sign in, sign up, sign out, saved session
  app_state.dart               Location, potholes, nearby alerts, dashboard, preferences
  scan_controller.dart         One photo: review, detection, result, submit
  models/                      Pothole, Report, Detection, Severity, DashboardData
  services/api_client.dart     HTTP client for the backend
  services/session_store.dart  Secure storage for the session and preferences
  services/location.dart       GPS position, once and as a stream
  services/alert_notifier.dart Notification with vibration
  screens/                     Login, the five tabs, scan flow, reports, detail, settings
  widgets/                     Shared cards, badges, tiles and the map
```

## Notes

- Cleartext HTTP is enabled because the backend runs on plain `http://`. Use HTTPS before deploying anywhere public.
- Maps and address lookups use OpenStreetMap, so they need an internet connection.
- `android/gradle.properties` turns off Kotlin incremental compilation. It fails on Windows when the project and
  Flutter's package cache are on different drives.
