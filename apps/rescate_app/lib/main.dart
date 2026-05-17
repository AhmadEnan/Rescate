// Main App Entry Point
import 'dart:async';

import 'package:ai_inference/ai_inference.dart';
import 'package:biometric_estimators/biometric_estimators.dart';
import 'package:dev_profiler/dev_profiler.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map_tile_caching/flutter_map_tile_caching.dart';
import 'package:offline_data/offline_data.dart';
import 'package:sensor_availability/sensor_availability.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';
import 'package:sqflite/sqflite.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/providers/app_state.dart';
import 'features/ai_chat/state/llm_state.dart';
import 'features/home/screens/main_screen.dart';
import 'features/onboarding/screens/onboarding_screen.dart';

Future<void> main() async {
  Profiler.markSessionStart();
  WidgetsFlutterBinding.ensureInitialized();
  if (kIsWeb) {
    // Use WASM SQLite backed by IndexedDB on web.
    databaseFactory = databaseFactoryFfiWeb;
  }
  try {
    LlmDefaults.activeProfile = await Profiler.span(
      'bootstrap.deviceProfile',
      () => DeviceProfile.detect(),
    );
  } catch (e) {
    debugPrint('[main] DeviceProfile.detect failed: $e');
    LlmDefaults.activeProfile = DeviceProfile.fallback;
  }
  await Profiler.span('bootstrap.initOfflineMapCache', _initOfflineMapCache);
  unawaited(_detectSensorsAtStartup());

  final prefs = await Profiler.span(
    'bootstrap.sharedPreferences',
    () => SharedPreferences.getInstance(),
  );
  final isFirstLaunch = prefs.getBool('isFirstLaunch') ?? true;

  runApp(_BootstrapApp(
    measurementStore:
        Profiler.span('bootstrap.openMeasurementStore', () => MeasurementStore.open()),
    isFirstLaunch: isFirstLaunch,
  ));
}

Future<void> _initOfflineMapCache() async {
  try {
    await FMTCObjectBoxBackend().initialise();
    await const FMTCStore('rescate_offline_map').manage.create();
  } on Object catch (e) {
    debugPrint('Offline map cache initialization skipped: $e');
  }
}

Future<void> _detectSensorsAtStartup() async {
  await Profiler.span('bootstrap.detectSensors', () async {
    try {
      await SensorAvailabilityService.instance.detectAll().timeout(
        const Duration(seconds: 6),
      );
    } on Object catch (e) {
      debugPrint('Startup sensor detection skipped: $e');
    }
  });
}

// ── Loading wrapper ─────────────────────────────────────────────────────────────

class _BootstrapApp extends StatelessWidget {
  const _BootstrapApp({
    required this.measurementStore,
    required this.isFirstLaunch,
  });

  final Future<MeasurementStore> measurementStore;
  final bool isFirstLaunch;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<MeasurementStore>(
      future: measurementStore,
      builder: (context, snapshot) {
        if (snapshot.hasData) {
          return RescateApp(
            measurementStore: snapshot.data!,
            isFirstLaunch: isFirstLaunch,
          );
        }
        return MaterialApp(
          title: 'Rescate',
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(seedColor: Colors.red),
            useMaterial3: true,
          ),
          home: Scaffold(
            body: Center(
              child: snapshot.hasError
                  ? Text('Startup failed: ${snapshot.error}')
                  : const CircularProgressIndicator(),
            ),
          ),
        );
      },
    );
  }
}

// ── Main application ────────────────────────────────────────────────────────────

class RescateApp extends StatefulWidget {
  const RescateApp({
    required this.measurementStore,
    required this.isFirstLaunch,
    super.key,
  });

  final MeasurementStore measurementStore;
  final bool isFirstLaunch;

  @override
  State<RescateApp> createState() => _RescateAppState();
}

class _RescateAppState extends State<RescateApp> with WidgetsBindingObserver {
  final AppState _appState = AppState();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(LlmState.instance.tryAutoLoadModel());
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _appState.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      unawaited(Profiler.exportJson(label: 'autosave'));
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppStateProvider(
      notifier: _appState,
      child: MaterialApp(
        title: 'Rescate',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.red),
          useMaterial3: true,
        ),
        routes: <String, WidgetBuilder>{
          '/sensors': (BuildContext _) => const SensorAvailabilityScreen(),
          '/biometrics': (BuildContext context) => BiometricAvailabilityScreen(
            onTileTap: (BiometricId id) {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (BuildContext _) => BiometricDetailScreen(
                    id: id,
                    measurementStore: widget.measurementStore,
                  ),
                ),
              );
            },
          ),
        },
        home: widget.isFirstLaunch
            ? const OnboardingScreen()
            : MainScreen(key: mainScreenKey),
      ),
    );
  }
}
