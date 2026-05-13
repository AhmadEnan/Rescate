# sensor_availability

Module 7 — Device Sensor Availability detection for the Rescate Flutter monorepo.

Runs once at app start, enumerates which of 26 hardware sensors are physically present on the current device, and caches the report in a singleton service so later biological-activity features can ask: *"is the heart-rate sensor available before I try to subscribe?"*

This is an **existence check only**. It does not read sensor values, does not request runtime permissions, and does not stream data.

## Usage

```dart
import 'package:flutter/material.dart';
import 'package:sensor_availability/sensor_availability.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SensorAvailabilityService.instance.detectAll();
  runApp(const MyApp());
}

// Later, anywhere:
final SensorReport hr = SensorAvailabilityService.instance.get(SensorId.heartRatePpg);
if (hr.status == SensorStatus.available) {
  // safe to subscribe
}
```

To show the report screen:

```dart
Navigator.of(context).push(
  MaterialPageRoute<void>(builder: (_) => const SensorAvailabilityScreen()),
);
```

## Status values

- `available` — sensor is physically present and the OS confirmed it
- `unavailable` — sensor is definitely not present
- `unknown` — the OS does not expose enough information to answer (e.g. fingerprint subtype)
- `needsPermission` — existence cannot be determined without a runtime permission grant

## Platforms

Android and iOS only. On other platforms (desktop, web) `detectAll()` returns a report where every sensor is `unknown`.

## Native channel

The Dart side talks to a single `MethodChannel` named `dev.rescate/sensor_availability`. The Android (Kotlin) and iOS (Swift) sides implement the methods listed in `lib/src/platform/native_sensor_channel.dart`.
