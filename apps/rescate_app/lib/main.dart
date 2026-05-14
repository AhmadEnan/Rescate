// Main App Entry Point
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map_tile_caching/flutter_map_tile_caching.dart';
import 'package:offline_data/offline_data.dart';
import 'package:p2p_mesh/p2p_mesh.dart';
import 'package:sensor_availability/sensor_availability.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';
import 'package:sqflite/sqflite.dart';

import 'core/providers/app_state.dart';
import 'features/home/screens/main_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (kIsWeb) {
    // Use WASM SQLite backed by IndexedDB on web.
    databaseFactory = databaseFactoryFfiWeb;
  }
  await _initOfflineMapCache();
  unawaited(_detectSensorsAtStartup());
  runApp(_BootstrapApp(measurementStore: MeasurementStore.open()));
}

Future<void> _initOfflineMapCache() async {
  try {
    await FMTCObjectBoxBackend().initialise();
    await FMTCStore('rescate_offline_map').manage.create();
  } on Object catch (e) {
    debugPrint('Offline map cache initialization skipped: $e');
  }
}

Future<void> _detectSensorsAtStartup() async {
  try {
    await SensorAvailabilityService.instance.detectAll().timeout(
      const Duration(seconds: 6),
    );
  } on Object catch (e) {
    debugPrint('Startup sensor detection skipped: $e');
  }
}

// ── Loading wrapper ─────────────────────────────────────────────────────────────

class _BootstrapApp extends StatelessWidget {
  const _BootstrapApp({required this.measurementStore});

  final Future<MeasurementStore> measurementStore;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<MeasurementStore>(
      future: measurementStore,
      builder: (context, snapshot) {
        if (snapshot.hasData) {
          return RescateApp(measurementStore: snapshot.data!);
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
  const RescateApp({required this.measurementStore, super.key});

  final MeasurementStore measurementStore;

  @override
  State<RescateApp> createState() => _RescateAppState();
}

class _RescateAppState extends State<RescateApp> {
  final AppState _appState = AppState();
  final MeshProvider _meshProvider = MeshProvider();

  @override
  void initState() {
    super.initState();
    // Initialize mesh networking in the background (non-blocking).
    unawaited(_meshProvider.init());
  }

  @override
  void dispose() {
    _appState.dispose();
    _meshProvider.dispose();
    super.dispose();
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
        home: MainScreen(key: mainScreenKey),
      ),
    );
  }
}
